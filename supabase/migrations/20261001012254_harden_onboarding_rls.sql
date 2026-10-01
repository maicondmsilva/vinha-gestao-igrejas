create index access_preferences_organization_idx
on public.user_access_preferences (selected_organization_id);

create index access_preferences_unit_idx
on public.user_access_preferences (selected_unit_id);

create or replace function private.current_user_has_memberships()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_memberships
    where user_id = (select auth.uid())
      and status in ('pending', 'active')
  );
$$;

create or replace function private.organization_has_memberships(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_memberships
    where organization_id = target_organization_id
  );
$$;

revoke all on function private.current_user_has_memberships() from public, anon;
revoke all on function private.organization_has_memberships(uuid) from public, anon;
grant execute on function private.current_user_has_memberships() to authenticated;
grant execute on function private.organization_has_memberships(uuid) to authenticated;

create policy organizations_insert_bootstrap
on public.organizations for insert to authenticated
with check (not private.current_user_has_memberships());

create policy memberships_insert_bootstrap
on public.organization_memberships for insert to authenticated
with check (
  user_id = (select auth.uid())
  and role = 'owner'
  and status = 'active'
  and not private.current_user_has_memberships()
  and not private.organization_has_memberships(organization_id)
);

grant insert on public.organizations to authenticated;
grant insert on public.organization_units to authenticated;
grant insert, update on public.organization_memberships to authenticated;

create or replace function public.bootstrap_organization(
  p_organization_name text,
  p_organization_slug text,
  p_headquarters_name text,
  p_full_name text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  new_organization_id uuid;
  new_unit_id uuid;
begin
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  if char_length(trim(p_organization_name)) not between 2 and 120 then
    raise exception 'invalid_organization_name' using errcode = '22023';
  end if;

  if p_organization_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'invalid_organization_slug' using errcode = '22023';
  end if;

  if char_length(trim(p_headquarters_name)) not between 2 and 120 then
    raise exception 'invalid_headquarters_name' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext(current_user_id::text));

  if private.current_user_has_memberships() then
    raise exception 'user_already_has_organization' using errcode = '23505';
  end if;

  insert into public.organizations (name, slug, status)
  values (trim(p_organization_name), p_organization_slug, 'trial')
  returning id into new_organization_id;

  insert into public.organization_memberships (
    organization_id,
    user_id,
    role,
    status
  ) values (
    new_organization_id,
    current_user_id,
    'owner',
    'active'
  );

  insert into public.organization_units (
    organization_id,
    name,
    slug,
    unit_type,
    status
  ) values (
    new_organization_id,
    trim(p_headquarters_name),
    'sede',
    'headquarters',
    'active'
  ) returning id into new_unit_id;

  update public.organization_memberships
  set default_unit_id = new_unit_id
  where organization_id = new_organization_id
    and user_id = current_user_id;

  update public.profiles
  set full_name = coalesce(nullif(trim(p_full_name), ''), profiles.full_name)
  where id = current_user_id;

  insert into public.user_access_preferences (
    user_id,
    selected_organization_id,
    selected_unit_id
  ) values (
    current_user_id,
    new_organization_id,
    new_unit_id
  );

  return new_organization_id;
end;
$$;

create or replace function public.access_context()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'email', auth.jwt() ->> 'email',
    'preference', coalesce((
      select jsonb_build_object(
        'selected_organization_id', p.selected_organization_id,
        'selected_unit_id', p.selected_unit_id,
        'theme', p.theme
      )
      from public.user_access_preferences p
      where p.user_id = (select auth.uid())
    ), '{}'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'membership_id', m.id,
          'organization_id', o.id,
          'organization_name', o.name,
          'organization_slug', o.slug,
          'primary_color', o.primary_color,
          'role', m.role,
          'status', m.status,
          'default_unit_id', m.default_unit_id,
          'units', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', u.id,
                'name', u.name,
                'type', u.unit_type,
                'parent_unit_id', u.parent_unit_id
              ) order by (u.unit_type = 'headquarters') desc, u.name
            )
            from public.organization_units u
            where u.organization_id = m.organization_id
              and u.status = 'active'
          ), '[]'::jsonb)
        ) order by o.name
      )
      from public.organization_memberships m
      join public.organizations o on o.id = m.organization_id
      where m.user_id = (select auth.uid())
        and m.status = 'active'
        and o.status in ('active', 'trial')
    ), '[]'::jsonb)
  )
  where (select auth.uid()) is not null;
$$;

alter function public.set_access_context(uuid, uuid, text) security invoker;
