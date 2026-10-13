-- Separate read and mutation policies so support/read-only operators can inspect
-- commercial records without gaining write or delete privileges.

drop policy if exists saas_plans_write on public.saas_plans;
create policy saas_plans_insert on public.saas_plans
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_plans_update on public.saas_plans
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_plans_delete on public.saas_plans
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));

drop policy if exists saas_module_catalog_write on public.saas_module_catalog;
create policy saas_module_catalog_insert on public.saas_module_catalog
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_module_catalog_update on public.saas_module_catalog
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_module_catalog_delete on public.saas_module_catalog
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));

drop policy if exists saas_plan_modules_write on public.saas_plan_modules;
create policy saas_plan_modules_insert on public.saas_plan_modules
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_plan_modules_update on public.saas_plan_modules
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_plan_modules_delete on public.saas_plan_modules
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));

drop policy if exists saas_promotions_write on public.saas_promotions;
create policy saas_promotions_insert on public.saas_promotions
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_promotions_update on public.saas_promotions
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_promotions_delete on public.saas_promotions
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));

drop policy if exists saas_subscriptions_operator on public.saas_subscriptions;
create policy saas_subscriptions_select on public.saas_subscriptions
  for select to authenticated
  using (public.is_platform_operator(array['owner', 'admin', 'support', 'read_only']));
create policy saas_subscriptions_insert on public.saas_subscriptions
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_subscriptions_update on public.saas_subscriptions
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_subscriptions_delete on public.saas_subscriptions
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));

drop policy if exists saas_subscription_modules_operator on public.saas_subscription_modules;
create policy saas_subscription_modules_select on public.saas_subscription_modules
  for select to authenticated
  using (public.is_platform_operator(array['owner', 'admin', 'support', 'read_only']));
create policy saas_subscription_modules_insert on public.saas_subscription_modules
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_subscription_modules_update on public.saas_subscription_modules
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_subscription_modules_delete on public.saas_subscription_modules
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));

drop policy if exists saas_discounts_operator on public.saas_subscription_discounts;
create policy saas_subscription_discounts_select on public.saas_subscription_discounts
  for select to authenticated
  using (public.is_platform_operator(array['owner', 'admin', 'support', 'read_only']));
create policy saas_subscription_discounts_insert on public.saas_subscription_discounts
  for insert to authenticated
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_subscription_discounts_update on public.saas_subscription_discounts
  for update to authenticated
  using (public.is_platform_operator(array['owner', 'admin']))
  with check (public.is_platform_operator(array['owner', 'admin']));
create policy saas_subscription_discounts_delete on public.saas_subscription_discounts
  for delete to authenticated
  using (public.is_platform_operator(array['owner', 'admin']));
