-- Keep catalog reads available to the whole internal team while restricting
-- every mutation, including DELETE, to owner/admin operators with AAL2.

drop policy if exists saas_catalog_write_operator on public.saas_plans;
drop policy if exists saas_modules_write_operator on public.saas_module_catalog;
drop policy if exists saas_plan_modules_write_operator on public.saas_plan_modules;
drop policy if exists saas_promotions_write_operator on public.saas_promotions;
drop policy if exists saas_subscriptions_operator on public.saas_subscriptions;
drop policy if exists saas_subscription_modules_operator on public.saas_subscription_modules;
drop policy if exists saas_discounts_operator on public.saas_subscription_discounts;

create policy saas_plans_mutate_operator on public.saas_plans for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_modules_mutate_operator on public.saas_module_catalog for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_plan_modules_mutate_operator on public.saas_plan_modules for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_promotions_mutate_operator on public.saas_promotions for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));

create policy saas_subscriptions_read_operator on public.saas_subscriptions for select to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_subscriptions_mutate_operator on public.saas_subscriptions for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_subscription_modules_read_operator on public.saas_subscription_modules for select to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_subscription_modules_mutate_operator on public.saas_subscription_modules for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_discounts_read_operator on public.saas_subscription_discounts for select to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_discounts_mutate_operator on public.saas_subscription_discounts for all to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
