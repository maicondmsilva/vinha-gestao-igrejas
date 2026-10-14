-- Avoid overlapping SELECT policies and add explicit operator policies to the
-- operational tables used behind the platform RPCs.

drop policy if exists saas_plans_mutate_operator on public.saas_plans;
drop policy if exists saas_modules_mutate_operator on public.saas_module_catalog;
drop policy if exists saas_plan_modules_mutate_operator on public.saas_plan_modules;
drop policy if exists saas_promotions_mutate_operator on public.saas_promotions;
drop policy if exists saas_subscriptions_mutate_operator on public.saas_subscriptions;
drop policy if exists saas_subscription_modules_mutate_operator on public.saas_subscription_modules;
drop policy if exists saas_discounts_mutate_operator on public.saas_subscription_discounts;

do $$
declare item record;
begin
  for item in select * from (values
    ('saas_plans'),('saas_module_catalog'),('saas_plan_modules'),('saas_promotions'),
    ('saas_subscriptions'),('saas_subscription_modules'),('saas_subscription_discounts')
  ) as tables(name) loop
    execute format('create policy %I on public.%I for insert to authenticated with check (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'']::public.platform_operator_role[]))',item.name||'_insert_operator',item.name);
    execute format('create policy %I on public.%I for update to authenticated using (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'']::public.platform_operator_role[]))',item.name||'_update_operator',item.name);
    execute format('create policy %I on public.%I for delete to authenticated using (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'']::public.platform_operator_role[]))',item.name||'_delete_operator',item.name);
  end loop;
end $$;

create policy saas_organization_invites_manager on public.saas_organization_invites for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_customer_operations_manager on public.saas_customer_operations for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_onboarding_progress_manager on public.saas_onboarding_progress for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));

grant select,insert,update,delete on public.saas_organization_invites,public.saas_customer_operations,public.saas_onboarding_progress to authenticated;
create index platform_audit_events_actor_idx on public.platform_audit_events(actor_user_id);
create index saas_organization_invites_created_by_idx on public.saas_organization_invites(created_by);
