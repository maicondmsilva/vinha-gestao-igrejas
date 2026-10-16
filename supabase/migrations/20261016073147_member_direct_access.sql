-- Generated from tested local schema; reviewed grants are intentionally narrower.
SET LOCAL check_function_bodies = on;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DROP POLICY "pastoral_notes_delete_pastoral" ON "public"."pastoral_notes";

DROP POLICY "pastoral_notes_insert_pastoral" ON "public"."pastoral_notes";

DROP POLICY "pastoral_notes_select_pastoral" ON "public"."pastoral_notes";

DROP POLICY "pastoral_notes_update_pastoral" ON "public"."pastoral_notes";

DROP POLICY "people_delete_admin" ON "public"."people";

DROP POLICY "people_insert_scope" ON "public"."people";

DROP POLICY "person_consents_update_scope" ON "public"."person_consents";

DROP POLICY "access_preferences_insert_self" ON "public"."user_access_preferences";

DROP POLICY "access_preferences_update_self" ON "public"."user_access_preferences";

CREATE OR REPLACE FUNCTION private.can_manage_person (
  target_person_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
 select exists(select 1 from public.people p join public.organizations o on o.id=p.organization_id
  where p.id=target_person_id and o.status in ('active','trial')
   and private.has_organization_role(p.organization_id,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
   and (private.has_organization_role(p.organization_id,array['owner','pastor','admin']::public.membership_role[])
    or (p.unit_id is not null and private.can_access_unit(p.organization_id,p.unit_id,array['manage','admin']::public.unit_access_level[]))));
$function$;

CREATE OR REPLACE FUNCTION private.can_view_person (
  target_person_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
 select exists(select 1 from public.people p join public.organizations o on o.id=p.organization_id
  where p.id=target_person_id and o.status in ('active','trial') and (
   (p.auth_user_id=(select auth.uid()) and private.is_organization_member(p.organization_id))
   or (private.has_organization_role(p.organization_id,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
    and (private.has_organization_role(p.organization_id,array['owner','pastor','admin']::public.membership_role[])
     or (p.unit_id is not null and private.can_access_unit(p.organization_id,p.unit_id))))));
$function$;

CREATE OR REPLACE FUNCTION private.guard_member_identity()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO ''
  AS $function$
begin
 if current_user='authenticated' then
  if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if tg_op='INSERT' then
   if new.auth_user_id is not null or new.app_role<>'member' then
    raise exception 'member_identity_requires_verified_workflow' using errcode='42501';
   end if;
   new.created_at:=clock_timestamp();
  elsif new.id is distinct from old.id or new.organization_id is distinct from old.organization_id
   or new.auth_user_id is distinct from old.auth_user_id or new.app_role is distinct from old.app_role
   or new.created_at is distinct from old.created_at then
   raise exception 'member_identity_requires_verified_workflow' using errcode='42501';
  end if;
 end if;
 return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.stamp_member_history()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO ''
  AS $function$
begin
 if current_user='authenticated' then
  if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
  new.created_at:=clock_timestamp();
  if tg_table_name='person_consents' then
   if new.consent_type not in ('privacy','image','messages') then
    raise exception 'consent_requires_verified_workflow' using errcode='42501';
   end if;
   new.source:=case when private.can_manage_person(new.person_id) then 'admin' else 'self' end;
   new.term_id:=null;new.accepted_by_person_id:=null;new.subject_person_id:=null;
   new.ip_address:=null;new.user_agent:=null;
   new.acceptance_snapshot:=jsonb_build_object('recorded_by_user_id',auth.uid(),
    'record_type',case when new.source='admin' then 'administrative_record' else 'self_reported_preference' end,
    'verified_member_acceptance',false);
   new.granted_at:=case when new.granted then new.created_at end;
   new.revoked_at:=case when not new.granted then new.created_at end;
  else
   new.updated_at:=new.created_at;
  end if;
 end if;
 return new;
end;
$function$;

CREATE TRIGGER pastoral_history_stamp
  BEFORE INSERT ON public.pastoral_notes
  FOR EACH ROW
  EXECUTE FUNCTION private.stamp_member_history();

CREATE TRIGGER member_identity_guard
  BEFORE INSERT OR UPDATE ON public.people
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_member_identity();

CREATE TRIGGER consent_history_stamp
  BEFORE INSERT ON public.person_consents
  FOR EACH ROW
  EXECUTE FUNCTION private.stamp_member_history();

CREATE POLICY "pastoral_notes_insert_pastoral" ON "public"."pastoral_notes"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((author_user_id = ( SELECT auth.uid() AS uid)) AND private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'pastor'::public.membership_role])
    AND private.can_manage_person(person_id)));

CREATE POLICY "pastoral_notes_select_pastoral" ON "public"."pastoral_notes"
  FOR SELECT
  TO "authenticated"
  USING ((private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'pastor'::public.membership_role]) AND private.can_view_person(person_id)));

CREATE POLICY "people_insert_scope" ON "public"."people"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    ((private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'pastor'::public.membership_role, 'admin'::public.membership_role,
    'secretary'::public.membership_role, 'leader'::public.membership_role]) AND (EXISTS ( SELECT 1
   FROM public.organizations o
  WHERE ((o.id = people.organization_id) AND (o.status = ANY (ARRAY['active'::public.organization_status, 'trial'::public.organization_status]))))) AND
    (private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'pastor'::public.membership_role, 'admin'::public.membership_role]) OR
    private.can_access_unit(organization_id, unit_id, ARRAY['manage'::public.unit_access_level, 'admin'::public.unit_access_level]))));

CREATE POLICY "access_preferences_insert_self" ON "public"."user_access_preferences"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND (((selected_organization_id IS NULL) AND (selected_unit_id IS NULL)) OR (private.is_organization_member(selected_organization_id)
    AND (EXISTS ( SELECT 1
   FROM public.organizations o
  WHERE ((o.id = user_access_preferences.selected_organization_id) AND (o.status = ANY (ARRAY['active'::public.organization_status, 'trial'::public.organization_status]))))) AND
    ((selected_unit_id IS NULL) OR private.can_access_unit(selected_organization_id, selected_unit_id))))));

CREATE POLICY "access_preferences_update_self" ON "public"."user_access_preferences"
  FOR UPDATE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND (((selected_organization_id IS NULL) AND (selected_unit_id IS NULL)) OR (private.is_organization_member(selected_organization_id)
    AND (EXISTS ( SELECT 1
   FROM public.organizations o
  WHERE ((o.id = user_access_preferences.selected_organization_id) AND (o.status = ANY (ARRAY['active'::public.organization_status, 'trial'::public.organization_status]))))) AND
    ((selected_unit_id IS NULL) OR private.can_access_unit(selected_organization_id, selected_unit_id))))));

REVOKE ALL ON FUNCTION "private"."guard_member_identity"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."stamp_member_history"() FROM PUBLIC;

REVOKE ALL ON TABLE "public"."audit_logs" FROM "authenticated";

GRANT INSERT, SELECT ON TABLE "public"."audit_logs" TO "authenticated";

REVOKE ALL ON TABLE "public"."emergency_contacts" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."emergency_contacts" TO "authenticated";

REVOKE ALL ON TABLE "public"."pastoral_notes" FROM "authenticated";

GRANT INSERT, SELECT ON TABLE "public"."pastoral_notes" TO "authenticated";

REVOKE ALL ON TABLE "public"."people" FROM "authenticated";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."people" TO "authenticated";

REVOKE ALL ON TABLE "public"."person_addresses" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."person_addresses" TO "authenticated";

REVOKE ALL ON TABLE "public"."person_consents" FROM "authenticated";

GRANT INSERT, SELECT ON TABLE "public"."person_consents" TO "authenticated";

REVOKE ALL ON TABLE "public"."user_access_preferences" FROM "authenticated";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."user_access_preferences" TO "authenticated";



REVOKE ALL ON FUNCTION private.guard_member_identity(), private.stamp_member_history() FROM anon, authenticated;

