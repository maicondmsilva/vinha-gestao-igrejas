-- Candidate only. Monthly issuance delegates pilot contracts to the credit-aware issuer.
create or replace function public.generate_platform_invoices(p_reference text,p_due bigint,p_organization uuid default null) returns integer
language plpgsql security invoker set search_path='' as $$
declare affected integer;units_affected integer;pilot_affected integer:=0;locked record;pilot record;digest text;request uuid;
begin
 perform private.require_platform_manager();
 if p_reference is null or p_reference !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_billing_period';end if;
 -- Catalog -> operator -> contracts, matching the confirmation ordering.
 lock table public.saas_plans,public.saas_module_catalog,public.saas_plan_modules in share mode;
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found then raise exception 'platform_manager_required' using errcode='42501';end if;
 for locked in select id from public.saas_unit_contracts where p_organization is null or organization_id=p_organization order by id for update loop null;end loop;
 perform private.require_platform_manager();
 insert into public.saas_invoices(church_id,subscription_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at)
 select s.organization_id,s.id,p_reference,coalesce(p_due,(extract(epoch from ((p_reference||'-'||lpad(coalesce(bp.due_day,10)::text,2,'0')||' 12:00:00')::timestamp at time zone 'America/Sao_Paulo'))*1000)::bigint),
 greatest(0,round((p.base_price_cents+coalesce((select sum(c.monthly_price_cents) from public.saas_subscription_modules sm join public.saas_module_catalog c on c.code=sm.module_code where sm.subscription_id=s.id and sm.enabled and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=s.plan_id and pm.module_code=sm.module_code and pm.included)),0))*(1-coalesce(d.custom_percent,0)::numeric/100))-coalesce(d.custom_amount_cents,0)),
 coalesce(r.payer_church_id,s.organization_id),(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint
 from public.saas_subscriptions s join public.saas_plans p on p.id=s.plan_id
 left join public.saas_billing_responsibilities r on r.church_id=s.organization_id
 left join public.saas_billing_profiles bp on bp.church_id=coalesce(r.payer_church_id,s.organization_id)
 left join public.saas_subscription_discounts d on d.subscription_id=s.id and (d.valid_until is null or d.valid_until>now())
 where (s.status='active' or (s.status='trialing' and s.trial_ends_at<=now())) and (p_organization is null or s.organization_id=p_organization)
 and not exists(select 1 from public.saas_unit_contracts uc join public.organization_units u on u.id=uc.unit_id where uc.organization_id=s.organization_id and uc.status in ('active','suspended') and u.unit_type='headquarters')
 and not exists(select 1 from public.saas_invoices prior where prior.church_id=s.organization_id and prior.reference_month=p_reference and prior.unit_contract_id is not null)
 on conflict(subscription_id,reference_month) do nothing;
 get diagnostics affected=row_count;
 insert into public.saas_invoices(church_id,unit_contract_id,unit_id,payer_unit_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at)
 select uc.organization_id,uc.id,uc.unit_id,uc.payer_unit_id,p_reference,
 coalesce(p_due,(extract(epoch from ((p_reference||'-'||lpad(coalesce(payer.due_day,uc.due_day)::text,2,'0')||' 12:00:00')::timestamp at time zone 'America/Sao_Paulo'))*1000)::bigint),
 p.base_price_cents+coalesce((select sum(m.monthly_price_cents) from public.saas_module_catalog m where uc.module_decisions->m.code='true'::jsonb and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=uc.plan_id and pm.module_code=m.code and pm.included)),0),
 uc.organization_id,(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint
 from public.saas_unit_contracts uc join public.saas_plans p on p.id=uc.plan_id
 join public.saas_subscriptions s on s.organization_id=uc.organization_id
 left join public.saas_unit_contracts payer on payer.unit_id=uc.payer_unit_id
 where uc.status='active' and (s.status='active' or (s.status='trialing' and s.trial_ends_at<=now())) and (p_organization is null or uc.organization_id=p_organization)
 and not exists(select 1 from public.saas_proration_cycles cy where cy.contract_id=uc.id)
 and exists(select 1 from public.saas_unit_contracts head join public.organization_units u on u.id=head.unit_id where head.organization_id=uc.organization_id and head.status='active' and u.unit_type='headquarters')
 and not exists(select 1 from public.saas_invoices prior where prior.church_id=uc.organization_id and prior.reference_month=p_reference and prior.subscription_id is not null)
 on conflict(unit_contract_id,reference_month) where unit_contract_id is not null and status<>'cancelled' do nothing;
 get diagnostics units_affected=row_count;
 -- Dispatch eligible pilot contracts through the credit-aware issuer. The
 -- existing Central action therefore uses the same atomic billing path.
 for pilot in
  select uc.id from public.saas_unit_contracts uc
  join public.saas_proration_cycles cy on cy.contract_id=uc.id
  join public.saas_subscriptions s on s.organization_id=uc.organization_id
  join public.organizations o on o.id=uc.organization_id
  join public.organization_units u on u.id=uc.unit_id
  where uc.status='active' and u.status='active' and o.status not in ('suspended','cancelled')
  and (s.status='active' or (s.status='trialing' and s.trial_ends_at<=now()))
  and (p_organization is null or uc.organization_id=p_organization)
  and to_char(to_timestamp(cy.cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM')=p_reference
  and not exists(select 1 from public.saas_invoices i where i.unit_contract_id=uc.id and i.reference_month=p_reference)
  order by uc.id
 loop
  digest:=md5('vinha.monthly.proration.v1:'||pilot.id::text||':'||p_reference);
  request:=(substr(digest,1,8)||'-'||substr(digest,9,4)||'-5'||substr(digest,14,3)||'-8'||substr(digest,18,3)||'-'||substr(digest,21,12))::uuid;
  perform public.issue_proration_cycle_invoice_pilot(jsonb_build_object('requestId',request,'contractId',pilot.id,'referenceMonth',p_reference));
  pilot_affected:=pilot_affected+1;
 end loop;
 return affected+units_affected+pilot_affected;
end $$;
