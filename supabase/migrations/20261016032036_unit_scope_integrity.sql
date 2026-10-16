SET local check_function_bodies = off;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DROP POLICY "units_select_member" ON "public"."organization_units";

DROP POLICY "people_insert_scope" ON "public"."people";

DROP POLICY "people_update_scope" ON "public"."people";

ALTER TABLE "public"."membership_unit_access"
  ADD COLUMN "organization_id" uuid;

-- Populate existing grants before requiring the composite organization key.
UPDATE public.membership_unit_access a SET organization_id=m.organization_id
FROM public.organization_memberships m WHERE m.id=a.membership_id;
ALTER TABLE public.membership_unit_access ALTER COLUMN organization_id SET NOT NULL;

CREATE OR REPLACE FUNCTION private.can_access_unit (
  target_organization_id uuid,
  target_unit_id         uuid,
  required_levels        public.unit_access_level[] DEFAULT ARRAY['read'::public.unit_access_level,
  'manage'::public.unit_access_level,
  'admin'::public.unit_access_level]
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
 select (select auth.uid()) is not null
 and exists(select 1 from public.organizations o where o.id=target_organization_id and o.status in ('active','trial'))
 and exists(select 1 from public.organization_units u where u.id=target_unit_id and u.organization_id=target_organization_id and u.status='active')
 and (
  private.has_organization_role(target_organization_id,array['owner','pastor','admin']::public.membership_role[])
  or exists(
   with recursive ancestors as (
    select u.id,u.parent_unit_id from public.organization_units u
     where u.id=target_unit_id and u.organization_id=target_organization_id and u.status='active'
    union
    select p.id,p.parent_unit_id from public.organization_units p join ancestors c on c.parent_unit_id=p.id
     where p.organization_id=target_organization_id and p.status='active'
   )
   select 1 from public.organization_memberships m
   join public.membership_unit_access a on a.membership_id=m.id and a.organization_id=m.organization_id
   join ancestors scope on scope.id=a.unit_id
   where m.organization_id=target_organization_id and m.user_id=(select auth.uid()) and m.status='active'
    and a.access_level=any(required_levels) and (a.unit_id=target_unit_id or a.include_children)
  )
 );
$function$;

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
  where p.id=target_person_id and o.status in ('active','trial') and (
   private.has_organization_role(p.organization_id,array['owner','pastor','admin']::public.membership_role[])
   or (p.unit_id is not null and private.can_access_unit(p.organization_id,p.unit_id,array['manage','admin']::public.unit_access_level[]))
  ));
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
   or private.has_organization_role(p.organization_id,array['owner','pastor','admin']::public.membership_role[])
   or (p.unit_id is not null and private.can_access_unit(p.organization_id,p.unit_id))
  ));
$function$;

CREATE OR REPLACE FUNCTION private.fill_unit_access_organization()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare organization uuid;
begin
 select m.organization_id into organization from public.organization_memberships m where m.id=new.membership_id;
 if organization is null then raise exception 'membership_not_accessible' using errcode='23503'; end if;
 if new.organization_id is not null and new.organization_id<>organization then
  raise exception 'grant_organization_mismatch' using errcode='23503';
 end if;
 new.organization_id:=organization;
 return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_unit_hierarchy()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
 if tg_op='UPDATE' and new.organization_id<>old.organization_id then
  raise exception 'unit_organization_is_immutable' using errcode='23514';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(17291015,pg_catalog.hashtext(new.organization_id::text));
 if new.parent_unit_id is not null and (
  new.parent_unit_id=new.id or exists(
   with recursive ancestors as (
    select u.id,u.parent_unit_id from public.organization_units u
     where u.id=new.parent_unit_id and u.organization_id=new.organization_id
    union
    select p.id,p.parent_unit_id from public.organization_units p join ancestors c on c.parent_unit_id=p.id
     where p.organization_id=new.organization_id
   ) select 1 from ancestors where id=new.id
  )
 ) then raise exception 'unit_hierarchy_cycle' using errcode='23514'; end if;
 return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.is_person_self (
  target_person_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
 select exists(select 1 from public.people p join public.organizations o on o.id=p.organization_id
  where p.id=target_person_id and p.auth_user_id=(select auth.uid()) and p.status<>'rejected'
   and o.status in ('active','trial') and private.is_organization_member(p.organization_id));
$function$;

CREATE OR REPLACE FUNCTION public.access_context()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
 select jsonb_build_object(
  'email',auth.jwt()->>'email',
  'preference',coalesce((
   select jsonb_build_object('selected_organization_id',p.selected_organization_id,'selected_unit_id',p.selected_unit_id,'theme',p.theme)
   from public.user_access_preferences p where p.user_id=(select auth.uid())
  ),'{}'::jsonb),
  'memberships',coalesce((
   select jsonb_agg(jsonb_build_object(
    'membership_id',m.id,'organization_id',o.id,'organization_name',o.name,'organization_slug',o.slug,
    'primary_color',o.primary_color,'role',m.role,'status',m.status,'default_unit_id',m.default_unit_id,
    'units',coalesce((
     select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'type',u.unit_type,'parent_unit_id',u.parent_unit_id)
      order by (u.unit_type='headquarters') desc,u.name)
     from public.organization_units u where u.organization_id=m.organization_id and u.status='active'
      and private.can_access_unit(m.organization_id,u.id)
    ),'[]'::jsonb)
   ) order by o.name)
   from public.organization_memberships m join public.organizations o on o.id=m.organization_id
   where m.user_id=(select auth.uid()) and m.status='active' and o.status in ('active','trial')
  ),'[]'::jsonb)
 ) where (select auth.uid()) is not null;
$function$;

CREATE OR REPLACE FUNCTION public.set_access_context (
  organization_id uuid,
  unit_id         uuid DEFAULT NULL::uuid,
  selected_theme  text DEFAULT 'system'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare current_user_id uuid:=auth.uid();
begin
 if current_user_id is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if selected_theme is null or selected_theme not in ('light','dark','system') then raise exception 'invalid_theme' using errcode='22023'; end if;
 if not exists(
  select 1 from public.organization_memberships m join public.organizations o on o.id=m.organization_id
  where m.organization_id=set_access_context.organization_id and m.user_id=current_user_id
   and m.status='active' and o.status in ('active','trial')
 ) then raise exception 'organization_access_denied' using errcode='42501'; end if;
 if unit_id is not null and not private.can_access_unit(organization_id,unit_id) then
  raise exception 'unit_access_denied' using errcode='42501';
 end if;
 insert into public.user_access_preferences(user_id,selected_organization_id,selected_unit_id,theme,updated_at)
 values(current_user_id,organization_id,unit_id,selected_theme,now())
 on conflict(user_id) do update set selected_organization_id=excluded.selected_organization_id,
  selected_unit_id=excluded.selected_unit_id,theme=excluded.theme,updated_at=excluded.updated_at;
end;
$function$;

ALTER TABLE "public"."membership_unit_access"
  ADD CONSTRAINT "unit_access_unit_same_organization" FOREIGN KEY (unit_id, organization_id) REFERENCES public.organization_units(id, organization_id) ON DELETE CASCADE;

ALTER TABLE "public"."organization_memberships"
  ADD CONSTRAINT "memberships_id_organization_unique" UNIQUE (id, organization_id);

ALTER TABLE "public"."membership_unit_access"
  ADD CONSTRAINT "unit_access_membership_same_organization" FOREIGN KEY (membership_id, organization_id) REFERENCES public.organization_memberships(id, organization_id)
    ON DELETE CASCADE;

CREATE INDEX unit_access_organization_idx ON public.membership_unit_access USING btree (organization_id);

CREATE TRIGGER unit_access_organization_guard
  BEFORE INSERT OR UPDATE ON public.membership_unit_access
  FOR EACH ROW
  EXECUTE FUNCTION private.fill_unit_access_organization();

CREATE TRIGGER unit_hierarchy_guard
  BEFORE INSERT OR UPDATE OF parent_unit_id, organization_id ON public.organization_units
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_unit_hierarchy();

CREATE POLICY "units_select_member" ON "public"."organization_units"
  FOR SELECT
  TO "authenticated"
  USING (
    (private.has_organization_role(organization_id, ARRAY['owner','pastor','admin']::public.membership_role[])
     AND EXISTS(SELECT 1 FROM public.organizations o WHERE o.id=organization_units.organization_id AND o.status IN ('active','trial')))
    OR private.can_access_unit(organization_id, id)
  );

CREATE POLICY "people_insert_scope" ON "public"."people"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((EXISTS ( SELECT 1
   FROM public.organizations o
  WHERE ((o.id = people.organization_id) AND (o.status = ANY (ARRAY['active'::public.organization_status, 'trial'::public.organization_status]))))) AND
    (private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'pastor'::public.membership_role, 'admin'::public.membership_role]) OR
    private.can_access_unit(organization_id, unit_id, ARRAY['manage'::public.unit_access_level, 'admin'::public.unit_access_level]))));

CREATE POLICY "people_update_scope" ON "public"."people"
  FOR UPDATE
  TO "authenticated"
  USING (private.can_manage_person(id))
  WITH CHECK (((EXISTS ( SELECT 1
   FROM public.organizations o
  WHERE ((o.id = people.organization_id) AND (o.status = ANY (ARRAY['active'::public.organization_status, 'trial'::public.organization_status]))))) AND
    (private.has_organization_role(organization_id, ARRAY['owner'::public.membership_role, 'pastor'::public.membership_role, 'admin'::public.membership_role]) OR
    private.can_access_unit(organization_id, unit_id, ARRAY['manage'::public.unit_access_level, 'admin'::public.unit_access_level]))));

REVOKE ALL ON FUNCTION "private"."fill_unit_access_organization"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."guard_unit_hierarchy"() FROM PUBLIC;

REVOKE ALL ON FUNCTION private.fill_unit_access_organization() FROM anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_unit_hierarchy() FROM anon, authenticated;
