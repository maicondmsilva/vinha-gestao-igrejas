-- Experimental unit-contract plan changes. Never invokes a payment provider.
create table public.saas_proration_cycles(
 contract_id uuid primary key references public.saas_unit_contracts(id),
 invoice_id uuid not null references public.saas_invoices(id),
 cycle_start bigint not null,cycle_end bigint not null check(cycle_end>cycle_start),
 net_cents bigint not null check(net_cents>=0),
 accumulated_numerator numeric not null default 0,
 rounded_adjustment bigint not null default 0,
 contract_updated_at timestamptz not null
);
create table public.saas_plan_adjustments(
 request_id uuid primary key,
 contract_id uuid not null references public.saas_unit_contracts(id),
 actor_id uuid not null references auth.users(id),
 fingerprint jsonb not null,
 snapshot jsonb not null,
 adjustment_cents bigint not null,
 created_at timestamptz not null default now()
);
create index plan_adjustments_contract_idx on public.saas_plan_adjustments(contract_id,created_at);
create index proration_cycles_invoice_idx on public.saas_proration_cycles(invoice_id);
create index plan_adjustments_actor_idx on public.saas_plan_adjustments(actor_id);
alter table public.saas_proration_cycles enable row level security;
alter table public.saas_plan_adjustments enable row level security;
revoke all on public.saas_proration_cycles,public.saas_plan_adjustments from public,anon,authenticated,service_role;
grant select on public.saas_proration_cycles,public.saas_plan_adjustments to authenticated;
create policy proration_manager_read on public.saas_proration_cycles for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create policy adjustments_manager_read on public.saas_plan_adjustments for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create function public.change_unit_contract_plan_pilot(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.saas_unit_contracts;inv public.saas_invoices;cy public.saas_proration_cycles;prior public.saas_plan_adjustments;
v_request uuid:=(p_data->>'requestId')::uuid;cid uuid:=(p_data->>'contractId')::uuid;
 next_plan text:=p_data->>'nextPlanId';start_ms bigint:=(p_data->>'cycleStart')::bigint;end_ms bigint:=(p_data->>'cycleEnd')::bigint;
 effective_ms bigint;old_net bigint;new_net bigint;total_numerator numeric;new_rounded bigint;delta bigint;result jsonb;new_stamp timestamptz;
begin
 perform private.require_platform_manager();
 perform private.require_confirmed_self_service_email();
 if v_request is null or cid is null or next_plan is null or p_data->>'baseInvoiceId' is null or p_data->>'expectedUpdatedAt' is null then raise exception 'invalid_plan_change' using errcode='22023';end if;
 select * into c from public.saas_unit_contracts where id=cid for update;
 if not found then raise exception 'contract_not_found' using errcode='22023';end if;
 select * into prior from public.saas_plan_adjustments where request_id=v_request;
 if found then
  if prior.contract_id<>cid or prior.actor_id<>auth.uid() or prior.fingerprint<>p_data then raise exception 'plan_change_idempotency_conflict' using errcode='22023';end if;
  return prior.snapshot;
 end if;
 if c.status<>'active' or c.updated_at<>(p_data->>'expectedUpdatedAt')::timestamptz then raise exception 'stale_or_inactive_contract' using errcode='40001';end if;
 if not exists(select 1 from public.organizations where id=c.organization_id and status not in ('suspended','cancelled')) then raise exception 'organization_unavailable' using errcode='42501';end if;
 if not exists(select 1 from public.organization_units where id=c.unit_id and organization_id=c.organization_id and status='active') or not exists(select 1 from public.saas_subscriptions where organization_id=c.organization_id and status in ('active','trialing')) then raise exception 'unit_or_subscription_unavailable' using errcode='42501';end if;
 if not exists(select 1 from public.saas_plans where id=next_plan and active and billing_cycle='monthly') then raise exception 'invalid_target_plan' using errcode='22023';end if;
 effective_ms:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
 if start_ms is null or end_ms is null or end_ms-start_ms not between 86400000 and 3024000000 or effective_ms<start_ms or effective_ms>=end_ms then raise exception 'invalid_billing_cycle' using errcode='22023';end if;
 select p.base_price_cents+coalesce((select sum(m.monthly_price_cents) from public.saas_module_catalog m where c.module_decisions->m.code='true'::jsonb and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=p.id and pm.module_code=m.code and pm.included)),0) into new_net from public.saas_plans p where p.id=next_plan;
 select * into cy from public.saas_proration_cycles where contract_id=cid for update;
 if not found then
  select * into inv from public.saas_invoices where id=(p_data->>'baseInvoiceId')::uuid for update;
  if not found or inv.unit_contract_id is distinct from cid or inv.status='cancelled' or inv.payer_unit_id is distinct from c.payer_unit_id or inv.church_id<>c.organization_id then raise exception 'invalid_base_invoice' using errcode='22023';end if;
  select p.base_price_cents+coalesce((select sum(m.monthly_price_cents) from public.saas_module_catalog m where c.module_decisions->m.code='true'::jsonb and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=p.id and pm.module_code=m.code and pm.included)),0) into old_net from public.saas_plans p where p.id=c.plan_id;
  if old_net is distinct from inv.amount_cents then raise exception 'legacy_price_requires_review' using errcode='22023';end if;
  insert into public.saas_proration_cycles(contract_id,invoice_id,cycle_start,cycle_end,net_cents,contract_updated_at) values(cid,inv.id,start_ms,end_ms,old_net,c.updated_at) returning * into cy;
 end if;
 if cy.invoice_id<>(p_data->>'baseInvoiceId')::uuid or cy.cycle_start<>start_ms or cy.cycle_end<>end_ms or cy.contract_updated_at<>c.updated_at then raise exception 'cycle_requires_review' using errcode='40001';end if;
 total_numerator:=cy.accumulated_numerator+(new_net-cy.net_cents)::numeric*(end_ms-effective_ms);
 new_rounded:=round(total_numerator/(end_ms-start_ms))::bigint;delta:=new_rounded-cy.rounded_adjustment;
 new_stamp:=clock_timestamp();
 result:=jsonb_build_object('requestId',v_request,'contractId',cid,'organizationId',c.organization_id,'unitId',c.unit_id,'payerUnitId',c.payer_unit_id,'baseInvoiceId',cy.invoice_id,'oldPlanId',c.plan_id,'nextPlanId',next_plan,'oldNetCents',cy.net_cents::text,'nextNetCents',new_net::text,'cycleStart',start_ms,'cycleEnd',end_ms,'effectiveAt',effective_ms,'adjustmentCents',delta::text,'chargeCents',greatest(delta,0)::text,'creditCents',greatest(-delta,0)::text,'creditDestination','next_invoice','automaticRefund',false,'settlementStatus','pending_integration','modules',c.module_decisions,'expectedUpdatedAt',new_stamp);
 result:=result||jsonb_build_object('nextPlanSnapshot',(select to_jsonb(p) from public.saas_plans p where id=next_plan),'nextPlanModulesSnapshot',(select coalesce(jsonb_agg(jsonb_build_object('module',m.code,'priceCents',m.monthly_price_cents,'included',coalesce(pm.included,false),'decision',c.module_decisions->m.code) order by m.code),'[]'::jsonb) from public.saas_module_catalog m left join public.saas_plan_modules pm on pm.module_code=m.code and pm.plan_id=next_plan where pm.included or c.module_decisions ? m.code));
 update public.saas_unit_contracts set plan_id=next_plan,updated_at=new_stamp where id=cid;
 update public.saas_proration_cycles set net_cents=new_net,accumulated_numerator=total_numerator,rounded_adjustment=new_rounded,contract_updated_at=new_stamp where contract_id=cid;
 insert into public.saas_plan_adjustments(request_id,contract_id,actor_id,fingerprint,snapshot,adjustment_cents) values(v_request,cid,auth.uid(),p_data,result,delta);
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'unit_contract.plan_changed_pilot','unit_contract',cid,jsonb_build_object('request_id',v_request));
 return result;
end $$;
revoke all on function public.change_unit_contract_plan_pilot(jsonb) from public,anon,service_role;
grant execute on function public.change_unit_contract_plan_pilot(jsonb) to authenticated;
