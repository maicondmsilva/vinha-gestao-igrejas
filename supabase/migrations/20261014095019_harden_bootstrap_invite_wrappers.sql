-- Generate identifiers before the inserts so the bootstrap can remain an
-- invoker function. Avoiding INSERT ... RETURNING prevents the organization
-- SELECT policy from being evaluated before the owner membership exists.
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
  new_organization_id uuid := extensions.gen_random_uuid();
  new_unit_id uuid := extensions.gen_random_uuid();
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

  insert into public.organizations (id, name, slug, status)
  values (new_organization_id, trim(p_organization_name), p_organization_slug, 'trial');

  insert into public.organization_memberships (organization_id, user_id, role, status)
  values (new_organization_id, current_user_id, 'owner', 'active');

  insert into public.organization_units (id, organization_id, name, slug, unit_type, status)
  values (new_unit_id, new_organization_id, trim(p_headquarters_name), 'sede', 'headquarters', 'active');

  update public.organization_memberships
  set default_unit_id = new_unit_id
  where organization_id = new_organization_id
    and user_id = current_user_id;

  update public.profiles
  set full_name = coalesce(nullif(trim(p_full_name), ''), profiles.full_name)
  where id = current_user_id;

  insert into public.user_access_preferences (user_id, selected_organization_id, selected_unit_id)
  values (current_user_id, new_organization_id, new_unit_id);

  return new_organization_id;
end;
$$;

revoke all on function public.bootstrap_organization(text, text, text, text) from public, anon;
grant execute on function public.bootstrap_organization(text, text, text, text) to authenticated;
