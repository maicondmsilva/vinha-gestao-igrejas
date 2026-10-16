-- Generated from the tested isolated database; least-privilege grants reviewed.
SET LOCAL check_function_bodies = on;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE "public"."organization_membership_events" (
  "id"              uuid                     NOT NULL DEFAULT extensions.gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "membership_id"   uuid                     NOT NULL,
  "subject_user_id" uuid                     NOT NULL,
  "actor_user_id"   uuid,
  "operation"       text                     NOT NULL,
  "before_state"    jsonb,
  "after_state"     jsonb,
  "execution_role"  text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "organization_membership_events_operation_check" CHECK ((operation = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text]))),
  CONSTRAINT "organization_membership_events_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."organization_membership_events"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."organization_membership_events" FROM "anon";

CREATE OR REPLACE FUNCTION private.audit_membership_governance()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare before_value jsonb; after_value jsonb; org uuid; target uuid; subject uuid;
begin
 if tg_op<>'INSERT' then before_value:=jsonb_build_object('role',old.role,'status',old.status,'defaultUnitId',old.default_unit_id); end if;
 if tg_op<>'DELETE' then after_value:=jsonb_build_object('role',new.role,'status',new.status,'defaultUnitId',new.default_unit_id); end if;
 if tg_op='UPDATE' and before_value=after_value then return new; end if;
 if tg_op='DELETE' then org:=old.organization_id;target:=old.id;subject:=old.user_id;
 else org:=new.organization_id;target:=new.id;subject:=new.user_id;end if;
 -- A trusted physical ministry purge cascades both memberships and their events.
 if tg_op='DELETE' and not exists(select 1 from public.organizations where id=org) then return old; end if;
 insert into public.organization_membership_events(organization_id,membership_id,subject_user_id,actor_user_id,operation,before_state,after_state,execution_role)
 values(org,target,subject,auth.uid(),tg_op,before_value,after_value,current_setting('role',true));
 if tg_op='DELETE' then return old; end if;return new;
end $function$;

CREATE OR REPLACE FUNCTION private.check_membership_governance (
  p_org       uuid,
  p_id        uuid,
  p_user      uuid,
  p_role      public.membership_role,
  p_status    public.membership_status,
  p_operation text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare actor public.membership_role; previous public.organization_memberships;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if p_operation not in ('INSERT','UPDATE','DELETE') or p_operation is null then raise exception 'invalid_operation' using errcode='22023'; end if;
 if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[])
  and not (p_operation='INSERT' and p_user=auth.uid() and private.is_organization_bootstrap_creator(p_org)) then
  raise exception 'membership_management_denied' using errcode='42501';
 end if;
 -- Serialize governance per ministry. No customer payload or authorization claim determines this lock.
 perform 1 from public.organizations where id=p_org and status in ('active','trial') for update;
 if not found then raise exception 'organization_access_denied' using errcode='42501'; end if;
 -- Lock the actor and active owners as well. At REPEATABLE READ, a changed row causes
 -- serialization failure rather than allowing an authorization decision from an old snapshot.
 perform 1 from public.organization_memberships where organization_id=p_org
  and (user_id=auth.uid() or (role='owner' and status='active')) order by id for update;
 select role into actor from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active';
 if p_operation='INSERT' and actor is null and p_user=auth.uid() and p_role='owner' and p_status='active'
  and private.is_organization_bootstrap_creator(p_org) and not private.current_user_has_memberships()
  and not private.organization_has_memberships(p_org) then return; end if;
 if actor is null or actor not in ('owner','admin','pastor') then raise exception 'membership_management_denied' using errcode='42501'; end if;
 if p_operation<>'INSERT' then
  select * into previous from public.organization_memberships where id=p_id and organization_id=p_org for update;
  if not found then raise exception 'membership_not_found' using errcode='P0002'; end if;
  -- Non-owner managers can maintain their own default unit, not change their role/status.
  if p_operation='UPDATE' and previous.user_id=auth.uid() and p_role=previous.role and p_status=previous.status then return; end if;
 end if;
 if actor='admin' and (previous.role in ('owner','admin') or p_role in ('owner','admin')) then
  raise exception 'membership_role_grant_denied' using errcode='42501';
 elsif actor='pastor' and (previous.role in ('owner','admin','pastor') or p_role in ('owner','admin','pastor')) then
  raise exception 'membership_role_grant_denied' using errcode='42501';
 end if;
 if previous.role='owner' and previous.status='active'
  and (p_operation='DELETE' or p_role<>'owner' or p_status<>'active')
  and not exists(select 1 from public.organization_memberships where organization_id=p_org and id<>p_id and role='owner' and status='active') then
  raise exception 'last_active_organization_owner' using errcode='42501';
 end if;
end $function$;

CREATE OR REPLACE FUNCTION private.guard_membership_governance()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
 if current_user='authenticated' then
  if tg_op='DELETE' then
   perform private.check_membership_governance(old.organization_id,old.id,old.user_id,null,null,tg_op);
  else
   perform private.check_membership_governance(new.organization_id,new.id,new.user_id,new.role,new.status,tg_op);
  end if;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $function$;

ALTER TABLE "public"."organization_membership_events"
  ADD CONSTRAINT "organization_membership_events_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE INDEX organization_membership_events_org_time ON public.organization_membership_events USING btree (organization_id, created_at DESC);

CREATE TRIGGER membership_governance_audit
  AFTER INSERT OR DELETE OR UPDATE ON public.organization_memberships
  FOR EACH ROW
  EXECUTE FUNCTION private.audit_membership_governance();

CREATE TRIGGER membership_governance_guard
  BEFORE INSERT OR DELETE OR UPDATE ON public.organization_memberships
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_membership_governance();

CREATE POLICY "membership_events_read_managers" ON "public"."organization_membership_events"
  FOR SELECT
  TO "authenticated"
  USING ((private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'admin'::public.membership_role]) AND (EXISTS ( SELECT 1
   FROM public.organizations o
  WHERE ((o.id = organization_membership_events.organization_id) AND (o.status = ANY (ARRAY['active'::public.organization_status, 'trial'::public.organization_status])))))));

REVOKE ALL ON FUNCTION "private"."audit_membership_governance"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."check_membership_governance"(uuid, uuid, uuid, public.membership_role, public.membership_status, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."check_membership_governance"(uuid, uuid, uuid, public.membership_role, public.membership_status, text) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."guard_membership_governance"() FROM PUBLIC;

REVOKE ALL ON TABLE "public"."organization_membership_events" FROM "authenticated";

GRANT SELECT ON TABLE "public"."organization_membership_events" TO "authenticated";

REVOKE ALL ON TABLE public.organization_membership_events FROM service_role;
GRANT SELECT ON TABLE public.organization_membership_events TO service_role;



REVOKE ALL ON FUNCTION private.guard_membership_governance(),private.audit_membership_governance() FROM anon,authenticated;
REVOKE ALL ON FUNCTION private.check_membership_governance(uuid,uuid,uuid,public.membership_role,public.membership_status,text) FROM anon;
