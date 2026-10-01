create table public.user_access_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  selected_organization_id uuid references public.organizations(id) on delete set null,
  selected_unit_id uuid references public.organization_units(id) on delete set null,
  theme text not null default 'system' check (theme in ('light', 'dark', 'system')),
  updated_at timestamptz not null default now()
);

alter table public.user_access_preferences enable row level security;

create policy access_preferences_select_self
on public.user_access_preferences for select to authenticated
using (user_id = (select auth.uid()));

create policy access_preferences_insert_self
on public.user_access_preferences for insert to authenticated
with check (user_id = (select auth.uid()));

create policy access_preferences_update_self
on public.user_access_preferences for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

grant usage on schema public to authenticated;
grant select on public.organizations to authenticated;
grant select on public.organization_units to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.organization_memberships to authenticated;
grant select on public.membership_unit_access to authenticated;
grant select, insert, update on public.user_access_preferences to authenticated;

create or replace function public.bootstrap_organization(
  p_organization_name text,
  p_organization_slug text,
  p_headquarters_name text,
  p_full_name text default null
)
returns uuid
language plpgsql
security definer
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

  if exists (
    select 1 from public.organization_memberships
    where user_id = current_user_id and status in ('pending', 'active')
  ) then
    raise exception 'user_already_has_organization' using errcode = '23505';
  end if;

  insert into public.organizations (name, slug, status)
  values (trim(p_organization_name), p_organization_slug, 'trial')
  returning id into new_organization_id;

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

  insert into public.organization_memberships (
    organization_id,
    user_id,
    default_unit_id,
    role,
    status
  ) values (
    new_organization_id,
    current_user_id,
    new_unit_id,
    'owner',
    'active'
  );

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
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'email', (select email from auth.users where id = (select auth.uid())),
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

create or replace function public.set_access_context(
  organization_id uuid,
  unit_id uuid default null,
  selected_theme text default 'system'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  if selected_theme not in ('light', 'dark', 'system') then
    raise exception 'invalid_theme' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.organization_memberships m
    where m.organization_id = set_access_context.organization_id
      and m.user_id = current_user_id
      and m.status = 'active'
  ) then
    raise exception 'organization_access_denied' using errcode = '42501';
  end if;

  if unit_id is not null and not exists (
    select 1 from public.organization_units u
    where u.id = set_access_context.unit_id
      and u.organization_id = set_access_context.organization_id
      and u.status = 'active'
  ) then
    raise exception 'unit_access_denied' using errcode = '42501';
  end if;

  insert into public.user_access_preferences (
    user_id,
    selected_organization_id,
    selected_unit_id,
    theme,
    updated_at
  ) values (
    current_user_id,
    organization_id,
    unit_id,
    selected_theme,
    now()
  )
  on conflict (user_id) do update set
    selected_organization_id = excluded.selected_organization_id,
    selected_unit_id = excluded.selected_unit_id,
    theme = excluded.theme,
    updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.bootstrap_organization(text, text, text, text) from public, anon;
revoke all on function public.access_context() from public, anon;
revoke all on function public.set_access_context(uuid, uuid, text) from public, anon;
grant execute on function public.bootstrap_organization(text, text, text, text) to authenticated;
grant execute on function public.access_context() to authenticated;
grant execute on function public.set_access_context(uuid, uuid, text) to authenticated;
