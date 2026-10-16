set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- No user-id argument or Data API wrapper: only the caller's current account.
-- This privileged read does not grant table access to auth.users.
create function private.require_confirmed_self_service_email()
returns text language plpgsql security definer set search_path='' as $$
declare account auth.users;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select * into account from auth.users where id=auth.uid() for share;
 if account.id is null or nullif(trim(account.email),'') is null or account.email_confirmed_at is null
  or account.deleted_at is not null or coalesce(account.is_anonymous,false) or account.banned_until>clock_timestamp() then
  raise exception 'self_service_identity_unavailable' using errcode='42501';
 end if;
 return lower(account.email);
end $$;
revoke all on function private.require_confirmed_self_service_email() from public,anon,authenticated,service_role;
grant execute on function private.require_confirmed_self_service_email() to authenticated;

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

  perform private.require_confirmed_self_service_email();

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

create or replace function public.register_organization_trial(p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare oid uuid; slug text; email text; existing public.saas_trial_registrations; begin
 email:=private.require_confirmed_self_service_email();
 perform pg_advisory_xact_lock(hashtext('trial:'||auth.uid()::text));
 select * into existing from public.saas_trial_registrations where user_id=auth.uid();
 if existing.organization_id is not null then
  select o.slug into slug from public.organizations o where o.id=existing.organization_id;
  return jsonb_build_object('ok',true,'slug',slug,'alreadyCreated',true);
 end if;
 if coalesce(p_data->>'accepted','')<>'true' or char_length(trim(coalesce(p_data->>'fullName','')))<3 or
  char_length(trim(coalesce(p_data->>'pastor','')))<3 or length(regexp_replace(coalesce(p_data->>'phone',''),'[^0-9]','','g')) not between 10 and 15 or
  char_length(trim(coalesce(p_data->>'city','')))<2 or coalesce(p_data->>'state','') !~ '^[A-Z]{2}$' or
  coalesce(p_data->>'units','') !~ '^[0-9]{1,4}$' or (p_data->>'units')::integer<1 then raise exception 'invalid_trial_data' using errcode='22023'; end if;
 slug:=trim(both '-' from regexp_replace(translate(lower(trim(p_data->>'ministry')),'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),'[^a-z0-9]+','-','g'));
 slug:=left(slug,85)||'-'||substr(replace(auth.uid()::text,'-',''),1,8);
 oid:=public.bootstrap_organization(p_data->>'ministry',slug,p_data->>'headquarters',p_data->>'fullName');
 perform public.save_organization_onboarding(oid,jsonb_build_object('step','identity','name',p_data->>'ministry','appName',p_data->>'ministry','seniorPastorName',p_data->>'pastor','primaryColor','#285c45','accentColor','#d9b960'));
 perform public.save_organization_onboarding(oid,jsonb_build_object('step','headquarters','name',p_data->>'headquarters','pastorName',p_data->>'pastor','email',email,'phone',p_data->>'phone','city',p_data->>'city','state',p_data->>'state'));
 perform public.save_organization_onboarding(oid,'{"step":"structure"}');
 perform public.save_organization_onboarding(oid,'{"step":"people"}');
 perform public.save_organization_onboarding(oid,'{"step":"completed"}');
 insert into public.saas_trial_registrations(organization_id,user_id,full_name,email,phone,city,state,units_estimate,terms_version)
 values(oid,auth.uid(),trim(p_data->>'fullName'),email,p_data->>'phone',trim(p_data->>'city'),p_data->>'state',(p_data->>'units')::integer,'teste-2026-10-14');
 return jsonb_build_object('ok',true,'slug',slug,'alreadyCreated',false);
end $$;


create or replace function private.guard_organization_client_fields()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if current_user<>'authenticated' then return new; end if;
 if tg_op='INSERT' then
  perform private.require_confirmed_self_service_email();
  if auth.uid() is null or new.bootstrap_user_id is distinct from auth.uid()
   or new.status<>'trial' or new.created_at is distinct from transaction_timestamp() then
   raise exception 'organization_bootstrap_fields_denied' using errcode='42501';
  end if;
 else
  -- Deny new administrative columns by default, not only today's known fields.
  if (to_jsonb(new)-array['name','legal_name','tax_id','primary_color','app_name','senior_pastor_name','accent_color','updated_at'])
   is distinct from
   (to_jsonb(old)-array['name','legal_name','tax_id','primary_color','app_name','senior_pastor_name','accent_color','updated_at']) then
   raise exception 'organization_admin_fields_immutable' using errcode='42501';
  end if;
  if old.status not in ('active','trial') then
   raise exception 'organization_configuration_unavailable' using errcode='42501';
  end if;
 end if;
 new.updated_at:=transaction_timestamp();
 return new;
end $$;
revoke all on function private.guard_organization_client_fields() from public,anon,authenticated,service_role;

-- Direct table writes must not fabricate the authenticated registration email.
create function private.guard_trial_registration_identity()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if current_user='authenticated' then
  if new.user_id is distinct from auth.uid() or new.email is distinct from private.require_confirmed_self_service_email() then
   raise exception 'trial_registration_identity_mismatch' using errcode='42501';
  end if;
 end if;
 return new;
end $$;
revoke all on function private.guard_trial_registration_identity() from public,anon,authenticated,service_role;
create trigger trial_registration_identity_guard before insert on public.saas_trial_registrations
for each row execute function private.guard_trial_registration_identity();

