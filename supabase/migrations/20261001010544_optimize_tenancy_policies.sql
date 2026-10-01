create index memberships_default_unit_organization_idx
on public.organization_memberships (default_unit_id, organization_id);

drop policy units_write_admin on public.organization_units;
create policy units_insert_admin
on public.organization_units for insert to authenticated
with check (
  private.has_organization_role(organization_units.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);
create policy units_update_admin
on public.organization_units for update to authenticated
using (
  private.has_organization_role(organization_units.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
)
with check (
  private.has_organization_role(organization_units.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);
create policy units_delete_admin
on public.organization_units for delete to authenticated
using (
  private.has_organization_role(organization_units.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);

drop policy memberships_write_admin on public.organization_memberships;
create policy memberships_insert_admin
on public.organization_memberships for insert to authenticated
with check (
  private.has_organization_role(organization_memberships.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);
create policy memberships_update_admin
on public.organization_memberships for update to authenticated
using (
  private.has_organization_role(organization_memberships.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
)
with check (
  private.has_organization_role(organization_memberships.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);
create policy memberships_delete_admin
on public.organization_memberships for delete to authenticated
using (
  private.has_organization_role(organization_memberships.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);

drop policy unit_access_write_admin on public.membership_unit_access;
create policy unit_access_insert_admin
on public.membership_unit_access for insert to authenticated
with check (
  private.has_organization_role(
    private.membership_organization(membership_unit_access.membership_id),
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
);
create policy unit_access_update_admin
on public.membership_unit_access for update to authenticated
using (
  private.has_organization_role(
    private.membership_organization(membership_unit_access.membership_id),
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
)
with check (
  private.has_organization_role(
    private.membership_organization(membership_unit_access.membership_id),
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
);
create policy unit_access_delete_admin
on public.membership_unit_access for delete to authenticated
using (
  private.has_organization_role(
    private.membership_organization(membership_unit_access.membership_id),
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
);

