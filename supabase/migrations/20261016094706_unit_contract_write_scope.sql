-- Generated from the tested isolated schema; dependency order and grants reviewed.
SET LOCAL check_function_bodies = on;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE FUNCTION private.target_unit_module_enabled (
  p_organization uuid,
  p_unit         uuid,
  p_module       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare c public.saas_unit_contracts;
begin
 if auth.uid() is null or not private.can_access_unit(p_organization,p_unit) then return false; end if;
 if not exists(select 1 from public.saas_module_catalog where code=p_module) then return false; end if;
 select * into c from public.saas_unit_contracts where organization_id=p_organization and unit_id=p_unit;
 -- Preserve the existing onboarding compatibility. Do not silently introduce billing enforcement.
 if c.id is null or c.status='draft' then return true; end if;
 if c.status<>'active' then return false; end if;
 if c.module_decisions ? p_module then
  -- Malformed historical decisions deny access, rather than throwing a cast error or granting it.
  return c.module_decisions->p_module='true'::jsonb;
 end if;
 return exists(select 1 from public.saas_plan_modules where plan_id=c.plan_id and module_code=p_module and included);
end $function$;

CREATE OR REPLACE FUNCTION private.can_manage_person (
  target_person_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
 select exists(select 1 from public.people p
  where p.id=target_person_id
   and private.target_unit_module_enabled(p.organization_id,p.unit_id,'people')
   and private.has_organization_role(p.organization_id,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
   and private.can_access_unit(p.organization_id,p.unit_id,array['manage','admin']::public.unit_access_level[]));
$function$;

CREATE OR REPLACE FUNCTION private.guard_member_unit_contract()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
 if current_user='authenticated' then
  if not private.target_unit_module_enabled(new.organization_id,new.unit_id,'people') then
   raise exception 'target_unit_module_not_enabled' using errcode='42501';
  end if;
  if tg_op='UPDATE' and not private.target_unit_module_enabled(old.organization_id,old.unit_id,'people') then
   raise exception 'source_unit_module_not_enabled' using errcode='42501';
  end if;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.request_unit_modules (
  p_unit    uuid,
  p_modules text[],
  p_due_day integer,
  p_autopay boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare oid uuid;
begin
 select organization_id into oid from public.organization_units where id=p_unit;
 if auth.uid() is null or not private.has_organization_role(oid,array['owner','admin']::public.membership_role[])
  or not private.can_access_unit(oid,p_unit) then raise exception 'access_denied' using errcode='42501'; end if;
 if p_due_day not between 1 and 28 or p_due_day is null or p_modules is null or cardinality(p_modules)>30
  or exists(select 1 from unnest(p_modules) x where not exists(select 1 from public.saas_module_catalog m where m.code=x and m.active)) then
  raise exception 'invalid_request';
 end if;
 update public.saas_unit_contracts set requested_modules=p_modules,requested_due_day=p_due_day,
  autopay_requested=p_autopay,request_updated_at=now() where unit_id=p_unit and organization_id=oid;
 if not found then raise exception 'contract_not_configured'; end if;
end $function$;

CREATE OR REPLACE FUNCTION private.unit_module_enabled (
  p_organization uuid,
  p_module       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare selected_unit uuid;
begin
 if auth.uid() is null or not private.is_organization_member(p_organization) then return false; end if;
 select selected_unit_id into selected_unit from public.user_access_preferences
 where user_id=auth.uid() and selected_organization_id=p_organization;
 if selected_unit is null then
  select default_unit_id into selected_unit from public.organization_memberships
  where user_id=auth.uid() and organization_id=p_organization and status='active';
 end if;
 if selected_unit is null then
  select id into selected_unit from public.organization_units
  where organization_id=p_organization and unit_type='headquarters' and status='active' order by id limit 1;
 end if;
 -- An explicitly selected but revoked unit must not fall back to a more permissive one.
 return private.target_unit_module_enabled(p_organization,selected_unit,p_module);
end $function$;

CREATE TRIGGER member_unit_contract_guard
  BEFORE INSERT OR UPDATE ON public.people
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_member_unit_contract();

REVOKE ALL ON FUNCTION "private"."guard_member_unit_contract"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."target_unit_module_enabled"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."target_unit_module_enabled"(uuid, uuid, text) TO "authenticated";



-- Explicit negative grants retained even when default ACLs change.
REVOKE ALL ON FUNCTION private.guard_member_unit_contract() FROM anon, authenticated;
REVOKE ALL ON FUNCTION private.target_unit_module_enabled(uuid,uuid,text) FROM anon;
