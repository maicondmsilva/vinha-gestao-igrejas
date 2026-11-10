create table public.saas_proration_cancellations(
 request_id uuid primary key,invoice_id uuid not null unique references public.saas_invoices(id),
 contract_id uuid not null references public.saas_unit_contracts(id),actor_id uuid not null references auth.users(id),
 reason text not null check(char_length(reason) between 5 and 300),fingerprint jsonb not null,snapshot jsonb not null,
 created_at timestamptz not null default now()
);
create index proration_cancellations_contract_idx on public.saas_proration_cancellations(contract_id);
create index proration_cancellations_actor_idx on public.saas_proration_cancellations(actor_id);
create table public.saas_proration_credit_returns(
 document_id uuid not null,invoice_id uuid not null,cancellation_id uuid not null references public.saas_proration_cancellations(request_id),
 amount_cents bigint not null check(amount_cents>0),created_at timestamptz not null default now(),
 primary key(document_id,invoice_id),foreign key(document_id,invoice_id) references public.saas_proration_credit_uses(document_id,invoice_id)
);
create index proration_returns_invoice_idx on public.saas_proration_credit_returns(invoice_id);
create index proration_returns_cancellation_idx on public.saas_proration_credit_returns(cancellation_id);
alter table public.saas_proration_cancellations enable row level security;
alter table public.saas_proration_credit_returns enable row level security;
revoke all on public.saas_proration_cancellations,public.saas_proration_credit_returns from public,anon,authenticated,service_role;
grant select on public.saas_proration_cancellations,public.saas_proration_credit_returns to authenticated;
create policy proration_cancellation_read on public.saas_proration_cancellations for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create policy proration_returns_read on public.saas_proration_credit_returns for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create or replace function private.protect_proration_issued_invoice() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.saas_proration_invoice_runs where invoice_id=old.id) and (
 new.amount_cents is distinct from old.amount_cents or new.unit_contract_id is distinct from old.unit_contract_id or new.payer_unit_id is distinct from old.payer_unit_id or new.payer_church_id is distinct from old.payer_church_id or new.reference_month is distinct from old.reference_month or new.church_id is distinct from old.church_id or new.due_at is distinct from old.due_at or new.unit_id is distinct from old.unit_id or new.id is distinct from old.id or
 (new.status='cancelled' and not exists(select 1 from public.saas_proration_cancellations where invoice_id=old.id)) or
 (exists(select 1 from public.saas_proration_cancellations where invoice_id=old.id) and (new.status<>'cancelled' or new.paid_at is distinct from old.paid_at or new.provider is distinct from old.provider or new.provider_invoice_id is distinct from old.provider_invoice_id or new.payment_url is distinct from old.payment_url))
 ) then raise exception 'issued_proration_invoice_requires_review' using errcode='42501';end if;
 return new;
end $$;

create function public.cancel_proration_invoice_pilot(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;i public.saas_invoices;prior public.saas_proration_cancellations;u record;
 request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;iid uuid:=(p_data->>'invoiceId')::uuid;
 reason text:=btrim(p_data->>'reason');returned bigint;result jsonb;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 if request is null or cid is null or iid is null or reason is null or char_length(reason) not between 5 and 300 then raise exception 'invalid_cancellation' using errcode='22023';end if;
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found then raise exception 'platform_manager_required' using errcode='42501';end if;
 select * into c from public.saas_unit_contracts where id=cid for update;
 if not found then raise exception 'contract_unavailable' using errcode='22023';end if;
 select * into prior from public.saas_proration_cancellations where request_id=request;
 if found then
  if prior.actor_id<>auth.uid() or prior.fingerprint<>p_data then raise exception 'cancellation_request_conflict' using errcode='22023';end if;
  return prior.snapshot;
 end if;
 select * into i from public.saas_invoices where id=iid for update;
 if not found or i.unit_contract_id is distinct from cid or not exists(select 1 from public.saas_proration_invoice_runs where invoice_id=iid and contract_id=cid) then raise exception 'invoice_unavailable' using errcode='22023';end if;
 if i.status<>'open' or i.paid_at is not null or i.provider is not null or i.provider_invoice_id is not null or i.payment_url is not null or exists(select 1 from public.saas_consolidated_invoice_items where invoice_id=iid) then raise exception 'external_or_settled_invoice_requires_review' using errcode='22023';end if;
 if exists(select 1 from public.saas_proration_cycles where invoice_id=iid) or exists(select 1 from public.saas_proration_rollovers where invoice_id=iid) then raise exception 'active_or_historical_cycle_requires_review' using errcode='22023';end if;
 select coalesce(sum(amount_cents),0) into returned from public.saas_proration_credit_uses where invoice_id=iid;
 result:=jsonb_build_object('requestId',request,'contractId',cid,'invoiceId',iid,'status','cancelled','creditReturnedCents',returned::text,'automaticRefund',false,'providerCancellationCreated',false);
 insert into public.saas_proration_cancellations(request_id,invoice_id,contract_id,actor_id,reason,fingerprint,snapshot) values(request,iid,cid,auth.uid(),reason,p_data,result);
 for u in select * from public.saas_proration_credit_uses where invoice_id=iid order by document_id for update loop
  insert into public.saas_proration_credit_returns(document_id,invoice_id,cancellation_id,amount_cents) values(u.document_id,iid,request,u.amount_cents);
 end loop;
 update public.saas_invoices set status='cancelled',updated_at=floor(extract(epoch from clock_timestamp())*1000)::bigint where id=iid;
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.invoice_cancelled_pilot','invoice',iid,jsonb_build_object('request_id',request,'credit_returned_cents',returned));
 return result;
end $$;
revoke all on function public.cancel_proration_invoice_pilot(jsonb) from public,anon,service_role;
grant execute on function public.cancel_proration_invoice_pilot(jsonb) to authenticated;

-- Preserve cancelled originals while allowing an explicitly linked replacement.
drop index public.invoices_unit_contract_month_idx;
create unique index invoices_unit_contract_month_idx on public.saas_invoices(unit_contract_id,reference_month) where unit_contract_id is not null and status<>'cancelled';
alter table public.saas_proration_invoice_runs drop constraint saas_proration_invoice_runs_contract_id_reference_month_key;

create or replace function public.issue_proration_cycle_invoice_pilot(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;cy public.saas_proration_cycles;prior public.saas_proration_invoice_runs;doc public.saas_proration_documents;
 v_request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;ref text:=p_data->>'referenceMonth';
 invoice uuid;replaced uuid;gross bigint;remaining bigint;used bigint:=0;available bigint;take bigint;result jsonb;stamp bigint:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 if v_request is null or cid is null or ref is null or ref !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_issue_input' using errcode='22023';end if;
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found then raise exception 'platform_manager_required' using errcode='42501';end if;
 select * into c from public.saas_unit_contracts where id=cid for update;
 if not found then raise exception 'contract_not_found' using errcode='22023';end if;
 select * into prior from public.saas_proration_invoice_runs where request_id=v_request;
 if found then
  if prior.contract_id<>cid or prior.fingerprint<>p_data then raise exception 'invoice_request_conflict' using errcode='22023';end if;
  if exists(select 1 from public.saas_proration_cancellations where invoice_id=prior.invoice_id) then return prior.snapshot||'{"status":"cancelled"}'::jsonb;end if;
  return prior.snapshot;
 end if;
 select * into cy from public.saas_proration_cycles where contract_id=cid for update;
 if not found or c.status<>'active' or cy.contract_updated_at<>c.updated_at then raise exception 'unverified_billing_cycle' using errcode='40001';end if;
 if not exists(select 1 from public.organizations where id=c.organization_id and status not in ('suspended','cancelled')) or not exists(select 1 from public.saas_subscriptions where organization_id=c.organization_id and status in ('active','trialing')) then raise exception 'billing_unavailable' using errcode='42501';end if;
 if ref<>to_char(to_timestamp(cy.cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM') or exists(select 1 from public.saas_invoices where unit_contract_id=cid and reference_month=ref and status<>'cancelled') then raise exception 'invoice_period_unavailable' using errcode='22023';end if;
 select id into replaced from public.saas_invoices where unit_contract_id=cid and reference_month=ref and status='cancelled' order by created_at desc,id desc limit 1;
 if replaced is not null then
  if p_data->>'replacesInvoiceId' is null or (p_data->>'replacesInvoiceId')::uuid<>replaced or not exists(select 1 from public.saas_proration_cancellations where invoice_id=replaced) then raise exception 'explicit_replacement_required' using errcode='22023';end if;
 elsif p_data->>'replacesInvoiceId' is not null then raise exception 'unexpected_replacement' using errcode='22023';end if;
 gross:=cy.net_cents;remaining:=gross;
 insert into public.saas_invoices(church_id,unit_contract_id,unit_id,payer_unit_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at) values(c.organization_id,cid,c.unit_id,c.payer_unit_id,ref,cy.cycle_end,gross,c.organization_id,stamp,stamp) returning id into invoice;
 for doc in select * from public.saas_proration_documents d where d.contract_id=cid and d.kind='credit' and d.snapshot->>'payerUnitId'=c.payer_unit_id::text and (d.snapshot->>'cycleEnd')::bigint<=cy.cycle_end order by d.created_at,d.id for update loop
  exit when remaining=0;
  select doc.amount_cents-coalesce(sum(u.amount_cents-coalesce(r.amount_cents,0)),0) into available from public.saas_proration_credit_uses u left join public.saas_proration_credit_returns r using(document_id,invoice_id) where u.document_id=doc.id;
  if available<0 or available>doc.amount_cents then raise exception 'credit_balance_invalid' using errcode='23514';end if;
  take:=least(available,remaining);
  if take>0 then insert into public.saas_proration_credit_uses(document_id,invoice_id,amount_cents) values(doc.id,invoice,take);remaining:=remaining-take;used:=used+take;end if;
 end loop;
 update public.saas_invoices set amount_cents=remaining,status=case when remaining=0 then 'paid' else 'open' end,paid_at=case when remaining=0 then stamp else null end where id=invoice;
 result:=jsonb_build_object('requestId',v_request,'contractId',cid,'invoiceId',invoice,'replacesInvoiceId',replaced,'referenceMonth',ref,'grossCents',gross::text,'creditAppliedCents',used::text,'amountCents',remaining::text,'payerUnitId',c.payer_unit_id,'providerChargeCreated',false);
 insert into public.saas_proration_invoice_runs(request_id,contract_id,invoice_id,reference_month,fingerprint,snapshot) values(v_request,cid,invoice,ref,p_data,result);
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.invoice_issued_pilot','invoice',invoice,jsonb_build_object('request_id',v_request,'credit_cents',used));
 return result;
end $$;
