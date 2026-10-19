-- Internal pilot documents only; no provider calls and no automatic refunds.
create table public.saas_proration_documents(
 id uuid primary key default extensions.gen_random_uuid(),
 adjustment_id uuid not null unique references public.saas_plan_adjustments(request_id),
 contract_id uuid not null references public.saas_unit_contracts(id),
 kind text not null check(kind in ('additional_invoice','credit')),
 amount_cents bigint not null check(amount_cents>0),
 snapshot jsonb not null,
 created_at timestamptz not null default now()
);
create index proration_docs_contract_idx on public.saas_proration_documents(contract_id,created_at,id);
create table public.saas_proration_invoice_runs(
 request_id uuid primary key,contract_id uuid not null references public.saas_unit_contracts(id),
 invoice_id uuid not null unique references public.saas_invoices(id),
 reference_month text not null, fingerprint jsonb not null,snapshot jsonb not null,
 unique(contract_id,reference_month)
);
create table public.saas_proration_credit_uses(
 document_id uuid not null references public.saas_proration_documents(id),
 invoice_id uuid not null references public.saas_invoices(id),
 amount_cents bigint not null check(amount_cents>0),
 created_at timestamptz not null default now(),primary key(document_id,invoice_id)
);
create index proration_uses_invoice_idx on public.saas_proration_credit_uses(invoice_id);
alter table public.saas_proration_documents enable row level security;
alter table public.saas_proration_invoice_runs enable row level security;
alter table public.saas_proration_credit_uses enable row level security;
revoke all on public.saas_proration_documents,public.saas_proration_invoice_runs,public.saas_proration_credit_uses from public,anon,authenticated,service_role;
grant select on public.saas_proration_documents,public.saas_proration_invoice_runs,public.saas_proration_credit_uses to authenticated;
create policy proration_docs_manager on public.saas_proration_documents for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create policy proration_runs_manager on public.saas_proration_invoice_runs for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create policy proration_uses_manager on public.saas_proration_credit_uses for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create function private.create_proration_document() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.adjustment_cents<>0 then
  insert into public.saas_proration_documents(adjustment_id,contract_id,kind,amount_cents,snapshot) values(new.request_id,new.contract_id,case when new.adjustment_cents>0 then 'additional_invoice' else 'credit' end,abs(new.adjustment_cents),new.snapshot);
 end if;
 return new;
end $$;
revoke all on function private.create_proration_document() from public,anon,authenticated,service_role;
create trigger proration_document_created after insert on public.saas_plan_adjustments for each row execute function private.create_proration_document();

create function public.issue_proration_cycle_invoice_pilot(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;cy public.saas_proration_cycles;prior public.saas_proration_invoice_runs;doc public.saas_proration_documents;
 v_request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;ref text:=p_data->>'referenceMonth';
 invoice uuid;gross bigint;remaining bigint;used bigint:=0;available bigint;take bigint;result jsonb;stamp bigint:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 if v_request is null or cid is null or ref is null or ref !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_issue_input' using errcode='22023';end if;
 select * into c from public.saas_unit_contracts where id=cid for update;
 if not found then raise exception 'contract_not_found' using errcode='22023';end if;
 select * into prior from public.saas_proration_invoice_runs where request_id=v_request;
 if found then
  if prior.contract_id<>cid or prior.fingerprint<>p_data then raise exception 'invoice_request_conflict' using errcode='22023';end if;
  return prior.snapshot;
 end if;
 select * into cy from public.saas_proration_cycles where contract_id=cid for update;
 if not found or c.status<>'active' or cy.contract_updated_at<>c.updated_at then raise exception 'unverified_billing_cycle' using errcode='40001';end if;
 if not exists(select 1 from public.organizations where id=c.organization_id and status not in ('suspended','cancelled')) or not exists(select 1 from public.saas_subscriptions where organization_id=c.organization_id and status in ('active','trialing')) then raise exception 'billing_unavailable' using errcode='42501';end if;
 if ref<>to_char(to_timestamp(cy.cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM') or exists(select 1 from public.saas_invoices where unit_contract_id=cid and reference_month=ref) then raise exception 'invoice_period_unavailable' using errcode='22023';end if;
 gross:=cy.net_cents;remaining:=gross;
 insert into public.saas_invoices(church_id,unit_contract_id,unit_id,payer_unit_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at) values(c.organization_id,cid,c.unit_id,c.payer_unit_id,ref,cy.cycle_end,gross,c.organization_id,stamp,stamp) returning id into invoice;
 for doc in select * from public.saas_proration_documents d where d.contract_id=cid and d.kind='credit' and d.snapshot->>'payerUnitId'=c.payer_unit_id::text and (d.snapshot->>'cycleEnd')::bigint<=cy.cycle_end order by d.created_at,d.id for update loop
  exit when remaining=0;
  select doc.amount_cents-coalesce(sum(u.amount_cents),0) into available from public.saas_proration_credit_uses u where u.document_id=doc.id;
  if available<0 then raise exception 'credit_balance_invalid' using errcode='23514';end if;
  take:=least(available,remaining);
  if take>0 then insert into public.saas_proration_credit_uses(document_id,invoice_id,amount_cents) values(doc.id,invoice,take);remaining:=remaining-take;used:=used+take;end if;
 end loop;
 update public.saas_invoices set amount_cents=remaining,status=case when remaining=0 then 'paid' else 'open' end,paid_at=case when remaining=0 then stamp else null end where id=invoice;
 result:=jsonb_build_object('requestId',v_request,'contractId',cid,'invoiceId',invoice,'referenceMonth',ref,'grossCents',gross::text,'creditAppliedCents',used::text,'amountCents',remaining::text,'payerUnitId',c.payer_unit_id,'providerChargeCreated',false);
 insert into public.saas_proration_invoice_runs(request_id,contract_id,invoice_id,reference_month,fingerprint,snapshot) values(v_request,cid,invoice,ref,p_data,result);
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.invoice_issued_pilot','invoice',invoice,jsonb_build_object('request_id',v_request,'credit_cents',used));
 return result;
end $$;
revoke all on function public.issue_proration_cycle_invoice_pilot(jsonb) from public,anon,service_role;
grant execute on function public.issue_proration_cycle_invoice_pilot(jsonb) to authenticated;

create function private.protect_proration_issued_invoice() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.saas_proration_invoice_runs where invoice_id=old.id) and (new.amount_cents is distinct from old.amount_cents or new.unit_contract_id is distinct from old.unit_contract_id or new.payer_unit_id is distinct from old.payer_unit_id or new.payer_church_id is distinct from old.payer_church_id or new.reference_month is distinct from old.reference_month or new.church_id is distinct from old.church_id or new.due_at is distinct from old.due_at or new.unit_id is distinct from old.unit_id or new.id is distinct from old.id or new.status='cancelled') then raise exception 'issued_proration_invoice_requires_review' using errcode='42501';end if;
 return new;
end $$;
revoke all on function private.protect_proration_issued_invoice() from public,anon,authenticated,service_role;
create trigger proration_issued_invoice_guard before update on public.saas_invoices for each row execute function private.protect_proration_issued_invoice();

-- Do not silently invalidate a future invoice's frozen price/payer snapshot.
create function private.protect_preissued_contract() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (new.plan_id is distinct from old.plan_id or new.module_decisions is distinct from old.module_decisions or new.payer_unit_id is distinct from old.payer_unit_id or new.due_day is distinct from old.due_day) and exists(
  select 1 from public.saas_proration_cycles cy join public.saas_proration_invoice_runs r on r.contract_id=cy.contract_id and r.reference_month=to_char(to_timestamp(cy.cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM')
  where cy.contract_id=old.id and cy.cycle_end>floor(extract(epoch from clock_timestamp())*1000)::bigint
 ) then raise exception 'preissued_invoice_requires_review' using errcode='40001';end if;
 return new;
end $$;
revoke all on function private.protect_preissued_contract() from public,anon,authenticated,service_role;
create trigger preissued_contract_guard before update on public.saas_unit_contracts for each row execute function private.protect_preissued_contract();
