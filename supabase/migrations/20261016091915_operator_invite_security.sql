-- Generated from isolated, tested database. Excludes unrelated local ACL normalization.
SET LOCAL check_function_bodies = on;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DROP POLICY "platform_operator_invites_update_scope" ON "public"."platform_operator_invites";

CREATE OR REPLACE FUNCTION private.accept_platform_operator_invite (
  p_token     uuid,
  p_full_name text
)
  RETURNS TABLE (
    user_id   uuid,
    role      public.platform_operator_role,
    full_name text,
    active    boolean
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare invitation public.platform_operator_invites; actor uuid:=auth.uid(); actor_email text; begin
 if actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select lower(u.email) into actor_email from auth.users u where u.id=actor and u.email_confirmed_at is not null;
 if actor_email is null then raise exception 'confirmed_email_required' using errcode='42501'; end if;
 if p_full_name is null or char_length(trim(p_full_name)) not between 2 and 120 then
  raise exception 'invalid_operator_name' using errcode='22023';
 end if;
 -- Serialize acceptance for the same account, then lock the invitation.
 perform pg_catalog.pg_advisory_xact_lock(17291016,pg_catalog.hashtext(actor::text));
 select * into invitation from public.platform_operator_invites i where i.token=p_token for update;
 if invitation.id is null or invitation.email<>actor_email or invitation.revoked_at is not null then
  raise exception 'invalid_or_expired_invitation' using errcode='42501';
 end if;
 if invitation.accepted_at is not null then
  if not exists(select 1 from public.platform_operators o where o.user_id=actor and o.email=actor_email and o.active) then
   raise exception 'invitation_already_used' using errcode='42501';
  end if;
  return query select * from public.platform_operator_context();
  return;
 end if;
 if invitation.expires_at<=now() or not exists(
  select 1 from public.platform_operators o where o.user_id=invitation.invited_by and o.active
   and (o.role='owner' or (o.role='admin' and invitation.role<>'owner'))
 ) then raise exception 'invalid_or_expired_invitation' using errcode='42501'; end if;
 if exists(select 1 from public.platform_operators o where o.user_id=actor) then
  raise exception 'operator_already_registered' using errcode='42501';
 end if;
 insert into public.platform_operators(user_id,email,role,full_name)
 values(actor,actor_email,invitation.role,trim(p_full_name));
 update public.platform_operator_invites set accepted_at=clock_timestamp() where id=invitation.id;
 return query select * from public.platform_operator_context();
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_operator_invitation()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO ''
  AS $function$
begin
 if current_user='authenticated' then
  if tg_op='INSERT' then
   if new.accepted_at is not null or new.revoked_at is not null then
    raise exception 'invitation_must_start_pending' using errcode='42501';
   end if;
   new.created_at:=clock_timestamp();
   if new.expires_at<=new.created_at or new.expires_at>new.created_at+interval '7 days' then
    raise exception 'invalid_invitation_expiry' using errcode='22023';
   end if;
  else
   if new.id is distinct from old.id or new.email is distinct from old.email
    or new.role is distinct from old.role or new.token is distinct from old.token
    or new.invited_by is distinct from old.invited_by or new.created_at is distinct from old.created_at
    or new.expires_at is distinct from old.expires_at or new.accepted_at is distinct from old.accepted_at
    or old.revoked_at is not null or new.revoked_at is null then
    raise exception 'invitation_is_immutable_create_a_new_one' using errcode='42501';
   end if;
   new.revoked_at:=clock_timestamp();
  end if;
 end if;
 return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_platform_operator()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
 if new.user_id is distinct from old.user_id or new.email is distinct from old.email
  or new.created_at is distinct from old.created_at then
  raise exception 'operator_identity_is_immutable' using errcode='42501';
 end if;
 if old.user_id=(select auth.uid()) and not new.active then
  raise exception 'an operator cannot suspend their own access';
 end if;
 if old.role='owner' and old.active and (new.role<>'owner' or not new.active) then
  perform pg_catalog.pg_advisory_xact_lock(17291016,1);
  if (select count(*) from public.platform_operators where role='owner' and active)<=1 then
   raise exception 'the last active owner cannot be removed';
  end if;
 end if;
 return new;
end;
$function$;

CREATE TRIGGER operator_invitation_guard
  BEFORE INSERT OR UPDATE ON public.platform_operator_invites
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_operator_invitation();

CREATE POLICY "platform_operator_invites_update_scope" ON "public"."platform_operator_invites"
  FOR UPDATE
  TO "authenticated"
  USING
    ((private.has_aal2() AND private.is_platform_operator(ARRAY['owner'::public.platform_operator_role, 'admin'::public.platform_operator_role]) AND
    (private.is_platform_operator(ARRAY['owner'::public.platform_operator_role]) OR (ROLE <> 'owner'::public.platform_operator_role)) AND (accepted_at IS NULL) AND
    (revoked_at IS NULL)))
  WITH
    CHECK
    ((private.has_aal2() AND private.is_platform_operator(ARRAY['owner'::public.platform_operator_role, 'admin'::public.platform_operator_role]) AND
    (private.is_platform_operator(ARRAY['owner'::public.platform_operator_role]) OR (role <> 'owner'::public.platform_operator_role))));

REVOKE ALL ON FUNCTION "private"."guard_operator_invitation"() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.guard_operator_invitation() FROM anon,authenticated;
REVOKE ALL ON public.platform_operators,public.platform_operator_invites,public.platform_operator_events FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.platform_operators,public.platform_operator_invites TO authenticated;
GRANT SELECT ON public.platform_operator_events TO authenticated;

