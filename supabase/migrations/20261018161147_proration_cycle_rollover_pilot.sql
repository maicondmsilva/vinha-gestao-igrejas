alter table public.saas_proration_cycles add column anchor_day integer check(anchor_day between 1 and 31);
create table public.saas_proration_rollovers(
 request_id uuid primary key,contract_id uuid not null references public.saas_unit_contracts(id),
 invoice_id uuid not null unique references public.saas_invoices(id),actor_id uuid not null references auth.users(id),
 cycle_start bigint not null,fingerprint jsonb not null,snapshot jsonb not null,created_at timestamptz not null default now(),
 unique(contract_id,cycle_start)
);
create index proration_rollovers_actor_idx on public.saas_proration_rollovers(actor_id);
alter table public.saas_proration_rollovers enable row level security;
revoke all on public.saas_proration_rollovers from public,anon,authenticated,service_role;
grant select on public.saas_proration_rollovers to authenticated;
create policy proration_rollovers_manager on public.saas_proration_rollovers for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create function private.proration_next_boundary(p_boundary bigint,p_anchor integer) returns bigint language plpgsql stable set search_path='' as $$
declare local_start timestamp;target_month timestamp;last_day integer;new_local timestamp;
begin
 if p_boundary is null or p_boundary<0 or p_anchor is null or p_anchor not between 1 and 31 then raise exception 'invalid_cycle_boundary' using errcode='22023';end if;
 local_start:=to_timestamp(p_boundary/1000.0) at time zone 'America/Sao_Paulo';
 target_month:=date_trunc('month',local_start)+interval '1 month';
 last_day:=extract(day from target_month+interval '1 month'-interval '1 day');
 new_local:=target_month+(least(p_anchor,last_day)-1)*interval '1 day'+(local_start-date_trunc('day',local_start));
 return floor(extract(epoch from (new_local at time zone 'America/Sao_Paulo'))*1000)::bigint;
end $$;
revoke all on function private.proration_next_boundary(bigint,integer) from public,anon,authenticated,service_role;

create function public.rollover_proration_cycle_pilot(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;cy public.saas_proration_cycles;run public.saas_proration_invoice_runs;inv public.saas_invoices;prior public.saas_proration_rollovers;
 v_request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;v_invoice uuid:=(p_data->>'invoiceId')::uuid;
 now_ms bigint;new_end bigint;anchor integer;new_stamp timestamptz;result jsonb;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 if v_request is null or cid is null or v_invoice is null or p_data->>'expectedUpdatedAt' is null then raise exception 'invalid_rollover' using errcode='22023';end if;
 select * into c from public.saas_unit_contracts where id=cid for update;
 if not found then raise exception 'contract_not_found' using errcode='22023';end if;
 select * into prior from public.saas_proration_rollovers where request_id=v_request;
 if found then
  if prior.contract_id<>cid or prior.fingerprint<>p_data then raise exception 'rollover_request_conflict' using errcode='22023';end if;
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
 if now_ms<cy.cycle_end or now_ms>=new_end then raise exception 'rollover_outside_period' using errcode='22023';end if;
 new_stamp:=clock_timestamp();
 result:=jsonb_build_object('requestId',v_request,'contractId',cid,'invoiceId',v_invoice,'cycleStart',cy.cycle_end,'cycleEnd',new_end,'anchorDay',anchor,'expectedUpdatedAt',new_stamp,'netCents',cy.net_cents::text,'automaticRefund',false);
 update public.saas_unit_contracts set updated_at=new_stamp where id=cid;
 update public.saas_proration_cycles set invoice_id=v_invoice,cycle_start=cy.cycle_end,cycle_end=new_end,accumulated_numerator=0,rounded_adjustment=0,contract_updated_at=new_stamp,anchor_day=anchor where contract_id=cid;
 insert into public.saas_proration_rollovers(request_id,contract_id,invoice_id,actor_id,cycle_start,fingerprint,snapshot) values(v_request,cid,v_invoice,auth.uid(),cy.cycle_end,p_data,result);
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.cycle_rolled_pilot','unit_contract',cid,jsonb_build_object('request_id',v_request,'invoice_id',v_invoice));
 return result;
end $$;
revoke all on function public.rollover_proration_cycle_pilot(jsonb) from public,anon,service_role;
grant execute on function public.rollover_proration_cycle_pilot(jsonb) to authenticated;
