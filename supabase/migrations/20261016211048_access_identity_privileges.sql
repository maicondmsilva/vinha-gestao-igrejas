-- Generated from the tested isolated schema; replace ACL normalization with revoke-only changes.
SET LOCAL check_function_bodies=on;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
 REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLES FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.guard_access_identity()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
 if current_user='authenticated' then
  if tg_table_name='organization_memberships' then
   if new.id is distinct from old.id or new.organization_id is distinct from old.organization_id
    or new.user_id is distinct from old.user_id or new.created_at is distinct from old.created_at then
    raise exception 'membership_identity_is_immutable' using errcode='42501';
   end if;
  else
   if new.membership_id is distinct from old.membership_id or new.organization_id is distinct from old.organization_id
    or new.unit_id is distinct from old.unit_id or new.created_at is distinct from old.created_at then
    raise exception 'unit_grant_identity_is_immutable' using errcode='42501';
   end if;
  end if;
 end if;
 return new;
end $function$;

CREATE TRIGGER access_identity_guard
  BEFORE UPDATE ON public.membership_unit_access
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_access_identity();

CREATE TRIGGER access_identity_guard
  BEFORE UPDATE ON public.organization_memberships
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_access_identity();

REVOKE ALL ON FUNCTION "private"."guard_access_identity"() FROM PUBLIC;


REVOKE ALL ON FUNCTION private.guard_access_identity() FROM anon, authenticated;
