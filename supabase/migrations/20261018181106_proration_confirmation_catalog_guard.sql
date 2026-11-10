-- Local candidate. Catalog locks are deliberately coarse for this pilot.
create function private.proration_catalog_snapshot(plan text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('plan',to_jsonb(p),'modules',
  (select coalesce(jsonb_agg(to_jsonb(m) order by m.code),'[]'::jsonb) from public.saas_module_catalog m),
  'links',(select coalesce(jsonb_agg(to_jsonb(l) order by l.module_code),'[]'::jsonb) from public.saas_plan_modules l where l.plan_id=p.id))
 from public.saas_plans p where p.id=plan
$$;
revoke all on function private.proration_catalog_snapshot(text) from public,anon,authenticated,service_role;

create function public.proration_catalog_preview_pilot(p_plan text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 return private.proration_catalog_snapshot(p_plan);
end $$;
revoke all on function public.proration_catalog_preview_pilot(text) from public,anon,service_role;
grant execute on function public.proration_catalog_preview_pilot(text) to authenticated;

create function public.confirm_unit_contract_plan_pilot(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior public.saas_plan_adjustments;actual jsonb;
begin
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 -- All callers use catalog-before-contract order. SHARE blocks price/link DML
 -- until this transaction finishes, including inserts/deletes in the catalog.
 lock table public.saas_plans,public.saas_module_catalog,public.saas_plan_modules in share mode;
 -- Revalidate after any catalog wait. Keep the permission row locked through
 -- commit so a concurrent suspension is ordered before or after confirmation.
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found then raise exception 'platform_manager_no_longer_available' using errcode='42501';end if;
 perform private.require_platform_manager();perform private.require_confirmed_self_service_email();
 perform 1 from public.saas_unit_contracts where id=(p_data->>'contractId')::uuid for update;
 select * into prior from public.saas_plan_adjustments where request_id=(p_data->>'requestId')::uuid;
 if found then
  if prior.actor_id<>auth.uid() or prior.fingerprint<>p_data then raise exception 'confirmation_conflict' using errcode='22023';end if;
  return prior.snapshot;
 end if;
 actual:=private.proration_catalog_snapshot(p_data->>'nextPlanId');
 if actual is null or p_data->'expectedCatalog' is null or actual is distinct from p_data->'expectedCatalog' then
  raise exception 'catalog_changed_refresh_preview' using errcode='40001';
 end if;
 return public.change_unit_contract_plan_pilot(p_data);
end $$;
revoke all on function public.confirm_unit_contract_plan_pilot(jsonb) from public,anon,service_role;
grant execute on function public.confirm_unit_contract_plan_pilot(jsonb) to authenticated;
-- Prevent bypassing the comparison through the previous RPC.
revoke execute on function public.change_unit_contract_plan_pilot(jsonb) from authenticated;
