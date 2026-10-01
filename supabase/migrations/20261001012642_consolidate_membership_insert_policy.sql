drop policy memberships_insert_admin on public.organization_memberships;
drop policy memberships_insert_bootstrap on public.organization_memberships;

create policy memberships_insert_authorized
on public.organization_memberships for insert to authenticated
with check (
  private.has_organization_role(
    organization_memberships.organization_id,
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
  or (
    user_id = (select auth.uid())
    and role = 'owner'
    and status = 'active'
    and not private.current_user_has_memberships()
    and not private.organization_has_memberships(organization_id)
  )
);
