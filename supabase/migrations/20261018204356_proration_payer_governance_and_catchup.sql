create table public.saas_proration_payer_changes(
 request_id uuid primary key,contract_id uuid not null references public.saas_unit_contracts(id),actor_id uuid not null references auth.users(id),
 fingerprint jsonb not null,snapshot jsonb not null,created_at timestamptz not null default now()
);
create index proration_payer_contract_idx on public.saas_proration_payer_changes(contract_id);
create index proration_payer_actor_idx on public.saas_proration_payer_changes(actor_id);
alter table public.saas_proration_payer_changes enable row level security;
revoke all on public.saas_proration_payer_changes from public,anon,authenticated,service_role;
grant select on public.saas_proration_payer_changes to authenticated;
create policy proration_payer_changes_read on public.saas_proration_payer_changes for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create function public.change_proration_payer_pilot(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;cy public.saas_proration_cycles;prior public.saas_proration_payer_changes;
 request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;payer uuid:=(p_data->>'payerUnitId')::uuid;
 stamp timestamptz;now_ms bigint;result jsonb;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 if request is null or cid is null or payer is null or p_data->>'expectedUpdatedAt' is null or char_length(coalesce(btrim(p_data->>'reason'),'')) not between 5 and 300 then raise exception 'invalid_payer_change' using errcode='22023';end if;
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found then raise exception 'platform_manager_required' using errcode='42501';end if;
 -- Lock all involved contracts in UUID order, including the target payer.
 perform id from public.saas_unit_contracts where id=cid or unit_id=payer order by id for update;
 select * into c from public.saas_unit_contracts where id=cid;
 if not found then raise exception 'contract_unavailable' using errcode='22023';end if;
 select * into prior from public.saas_proration_payer_changes where request_id=request;
 if found then
  if prior.actor_id<>auth.uid() or prior.fingerprint<>p_data then raise exception 'payer_request_conflict' using errcode='22023';end if;
  return prior.snapshot;
 end if;
 select * into cy from public.saas_proration_cycles where contract_id=cid for update;
 now_ms:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
 if not found or c.status<>'active' or cy.contract_updated_at<>c.updated_at or c.updated_at<>(p_data->>'expectedUpdatedAt')::timestamptz or now_ms<cy.cycle_start or now_ms>=cy.cycle_end then raise exception 'payer_cycle_requires_review' using errcode='40001';end if;
 if not exists(select 1 from public.organizations where id=c.organization_id and status not in ('suspended','cancelled')) or not exists(select 1 from public.organization_units where id=payer and organization_id=c.organization_id and status='active') or not exists(select 1 from public.saas_unit_contracts where unit_id=payer and organization_id=c.organization_id and status='active') then raise exception 'payer_unavailable' using errcode='42501';end if;
 if c.payer_unit_id=payer then raise exception 'payer_unchanged' using errcode='22023';end if;
 stamp:=clock_timestamp();
 result:=jsonb_build_object('requestId',request,'contractId',cid,'oldPayerUnitId',c.payer_unit_id,'payerUnitId',payer,'effectiveAt',stamp,'expectedUpdatedAt',stamp,'existingInvoicesChanged',false,'existingCreditsTransferred',false);
 update public.saas_unit_contracts set payer_unit_id=payer,updated_at=stamp where id=cid;
 update public.saas_proration_cycles set contract_updated_at=stamp where contract_id=cid;
 insert into public.saas_proration_payer_changes(request_id,contract_id,actor_id,fingerprint,snapshot) values(request,cid,auth.uid(),p_data,result);
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.payer_changed_pilot','unit_contract',cid,jsonb_build_object('request_id',request,'old_payer',c.payer_unit_id,'new_payer',payer));
 return result;
end $$;
revoke all on function public.change_proration_payer_pilot(jsonb) from public,anon,service_role;
grant execute on function public.change_proration_payer_pilot(jsonb) to authenticated;

-- Catch-up is deliberately one verified period per call. No skipped competence.
create or replace function public.rollover_proration_cycle_pilot(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;cy public.saas_proration_cycles;run public.saas_proration_invoice_runs;inv public.saas_invoices;prior public.saas_proration_rollovers;
 v_request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;v_invoice uuid:=(p_data->>'invoiceId')::uuid;
 now_ms bigint;new_end bigint;anchor integer;new_stamp timestamptz;result jsonb;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 if v_request is null or cid is null or v_invoice is null or p_data->>'expectedUpdatedAt' is null then raise exception 'invalid_rollover' using errcode='22023';end if;
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found then raise exception 'platform_manager_required' using errcode='42501';end if;
 select * into c from public.saas_unit_contracts where id=cid for update;
 if not found then raise exception 'contract_not_found' using errcode='22023';end if;
 select * into prior from public.saas_proration_rollovers where request_id=v_request;
 if found then
  if prior.actor_id<>auth.uid() or prior.contract_id<>cid or prior.fingerprint<>p_data then raise exception 'rollover_request_conflict' using errcode='22023';end if;
  return prior.snapshot;
 end if;
 select * into cy from public.saas_proration_cycles where contract_id=cid for update;
 if not found or c.status<>'active' or cy.contract_updated_at<>c.updated_at or c.updated_at<>(p_data->>'expectedUpdatedAt')::timestamptz then raise exception 'stale_rollover' using errcode='40001';end if;
 if not exists(select 1 from public.organizations where id=c.organization_id and status not in ('suspended','cancelled')) or not exists(select 1 from public.organization_units where id=c.unit_id and organization_id=c.organization_id and status='active') or not exists(select 1 from public.saas_subscriptions where organization_id=c.organization_id and status in ('active','trialing')) then raise exception 'rollover_access_denied' using errcode='42501';end if;
 select * into run from public.saas_proration_invoice_runs where invoice_id=v_invoice and contract_id=cid;
 if not found then raise exception 'rollover_invoice_unverified' using errcode='22023';end if;
 select * into inv from public.saas_invoices where id=v_invoice for update;
 if not found or inv.status='cancelled' or inv.unit_contract_id is distinct from cid or inv.payer_unit_id is distinct from c.payer_unit_id or inv.church_id<>c.organization_id or run.reference_month<>to_char(to_timestamp(cy.cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM') or (run.snapshot->>'grossCents')::bigint is distinct from cy.net_cents then raise exception 'rollover_invoice_mismatch' using errcode='22023';end if;
 anchor:=coalesce(cy.anchor_day,extract(day from to_timestamp(cy.cycle_end/1000.0) at time zone 'America/Sao_Paulo')::integer);
 new_end:=private.proration_next_boundary(cy.cycle_end,anchor);now_ms:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
 if now_ms<cy.cycle_end then raise exception 'rollover_outside_period' using errcode='22023';end if;
 new_stamp:=clock_timestamp();
 result:=jsonb_build_object('requestId',v_request,'contractId',cid,'invoiceId',v_invoice,'cycleStart',cy.cycle_end,'cycleEnd',new_end,'anchorDay',anchor,'expectedUpdatedAt',new_stamp,'netCents',cy.net_cents::text,'automaticRefund',false,'catchupRemaining',now_ms>=new_end);
 update public.saas_unit_contracts set updated_at=new_stamp where id=cid;
 update public.saas_proration_cycles set invoice_id=v_invoice,cycle_start=cy.cycle_end,cycle_end=new_end,accumulated_numerator=0,rounded_adjustment=0,contract_updated_at=new_stamp,anchor_day=anchor where contract_id=cid;
 insert into public.saas_proration_rollovers(request_id,contract_id,invoice_id,actor_id,cycle_start,fingerprint,snapshot) values(v_request,cid,v_invoice,auth.uid(),cy.cycle_end,p_data,result);
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.cycle_rolled_pilot','unit_contract',cid,jsonb_build_object('request_id',v_request,'invoice_id',v_invoice));
 return result;
end $$;
