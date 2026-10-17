set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- No existing approval is guessed, erased, or backfilled. Pending approvals
-- without an attributable current membership must be explicitly renewed.
alter table public.saas_hierarchy_requests
 add column parent_approved_by uuid,
 add column parent_approved_membership_id uuid,
 add column child_approved_by uuid,
 add column child_approved_membership_id uuid;

-- Central operators keep SELECT but must use the authorized, audited RPCs.
-- Table owners/trusted service paths remain available for migration/operations.
revoke insert,update,delete on public.saas_hierarchy_requests,public.saas_organization_links,public.saas_billing_responsibilities from public,anon,authenticated;

create table public.organization_hierarchy_events (
 id uuid primary key default extensions.gen_random_uuid(),
 request_id uuid, parent_organization_id uuid not null, child_organization_id uuid not null,
 actor_user_id uuid not null, actor_membership_id uuid,
 action text not null check(action in ('requested','approved_side','rejected','activated','billing_changed','unlinked')),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default clock_timestamp()
);
create index hierarchy_events_request_time on public.organization_hierarchy_events(request_id,created_at desc);
create index hierarchy_events_child_time on public.organization_hierarchy_events(child_organization_id,created_at desc);
alter table public.organization_hierarchy_events enable row level security;
revoke all on public.organization_hierarchy_events from public,anon,authenticated,service_role;
grant select on public.organization_hierarchy_events to authenticated,service_role;
create policy hierarchy_events_operator_read on public.organization_hierarchy_events for select to authenticated using (
 private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy hierarchy_events_participant_read on public.organization_hierarchy_events for select to authenticated using (
 private.has_organization_role(parent_organization_id,array['owner','admin','pastor']::public.membership_role[])
 or private.has_organization_role(child_organization_id,array['owner','admin','pastor']::public.membership_role[]));

create or replace function public.change_platform_hierarchy(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare parent_id uuid;child_id uuid;mode text;stamp bigint:=(extract(epoch from now())*1000)::bigint;request_id uuid;
begin
 perform private.require_platform_manager();
 perform private.require_confirmed_self_service_email();
 if p_action is null or p_action not in ('request','billing','unlink','link') then raise exception 'invalid_action' using errcode='22023';end if;
 if p_action='link' then raise exception 'use_hierarchy_request' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_hierarchy' using errcode='22023';end if;
 begin
  parent_id:=nullif(p_data->>'parentChurchId','')::uuid;child_id:=nullif(p_data->>'childChurchId','')::uuid;
 exception when invalid_text_representation then raise exception 'invalid_hierarchy' using errcode='22023';end;
 mode:=coalesce(p_data->>'billingMode','individual');
 if child_id is null or mode not in ('individual','centralized') then raise exception 'invalid_hierarchy' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtext('organization-hierarchy'));
 if p_action='request' then
  if parent_id is null or parent_id=child_id then raise exception 'invalid_hierarchy' using errcode='22023';end if;
 else
  select parent_church_id into parent_id from public.saas_organization_links where child_church_id=child_id and status='active' for update;
  if parent_id is null then raise exception 'link_not_found' using errcode='P0002';end if;
 end if;
 perform 1 from public.organizations where id in (parent_id,child_id) order by id for update;
 if p_action<>'unlink' and (select count(*) from public.organizations where id in (parent_id,child_id) and status in ('active','trial'))<>2 then
  raise exception 'hierarchy_organization_unavailable' using errcode='42501';end if;
 -- Recheck the real operator row under a lock after waiting for other writers.
 perform 1 from public.platform_operators where user_id=auth.uid() and active and role in ('owner','admin') for share;
 if not found or not private.has_aal2() then raise exception 'platform_manager_required' using errcode='42501';end if;
 if p_action='request' then
  if exists(select 1 from public.saas_organization_links where child_church_id=child_id and status='active') then raise exception 'child_already_linked';end if;
  if exists(select 1 from public.saas_hierarchy_requests where child_church_id=child_id and status='pending') then raise exception 'hierarchy_pending_request' using errcode='23505';end if;
  if exists(with recursive descendants(id) as (select child_church_id from public.saas_organization_links where parent_church_id=child_id and status='active' union select l.child_church_id from public.saas_organization_links l join descendants d on l.parent_church_id=d.id where l.status='active') select 1 from descendants where id=parent_id) then raise exception 'hierarchy_cycle';end if;
  insert into public.saas_hierarchy_requests(parent_church_id,child_church_id,billing_mode,requested_by,created_at)
   values(parent_id,child_id,mode,auth.uid(),stamp) returning id into request_id;
  insert into public.organization_hierarchy_events(request_id,parent_organization_id,child_organization_id,actor_user_id,action,metadata)
   values(request_id,parent_id,child_id,auth.uid(),'requested',jsonb_build_object('billingMode',mode));
  return jsonb_build_object('ok',true,'id',request_id,'status','pending');
 end if;
 if p_action='unlink' then
  update public.saas_organization_links set status='inactive',unlinked_at=stamp where child_church_id=child_id and status='active';mode:='individual';
 end if;
 insert into public.saas_billing_responsibilities(church_id,payer_church_id,billing_mode,updated_at)
  values(child_id,case when mode='centralized' then parent_id else child_id end,mode,stamp)
  on conflict(church_id) do update set payer_church_id=excluded.payer_church_id,billing_mode=excluded.billing_mode,updated_at=excluded.updated_at;
 insert into public.organization_hierarchy_events(parent_organization_id,child_organization_id,actor_user_id,action,metadata)
  values(parent_id,child_id,auth.uid(),case when p_action='unlink' then 'unlinked' else 'billing_changed' end,jsonb_build_object('billingMode',mode,'payerOrganizationId',case when mode='centralized' then parent_id else child_id end));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.change_platform_hierarchy(text,jsonb) from public,anon,service_role;
grant execute on function public.change_platform_hierarchy(text,jsonb) to authenticated;

create or replace function public.approve_organization_hierarchy(p_request uuid,p_organization uuid,p_decision text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.saas_hierarchy_requests;stamp bigint:=(extract(epoch from now())*1000)::bigint;actor_membership uuid;parent_valid boolean;child_valid boolean;renewal boolean:=false;
begin
 if auth.uid() is null or p_organization is null or not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then
  raise exception 'organization_access_denied' using errcode='42501';end if;
 perform private.require_confirmed_self_service_email();
 if p_request is null then raise exception 'invalid_request' using errcode='22023';end if;
 if p_decision is null or p_decision not in ('approve','reject') then raise exception 'invalid_decision' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtext('organization-hierarchy'));
 select * into r from public.saas_hierarchy_requests where id=p_request for update;
 if r.id is null or p_organization not in (r.parent_church_id,r.child_church_id) then raise exception 'request_not_found' using errcode='42501';end if;
 if r.status<>'pending' then return jsonb_build_object('ok',true,'status',r.status);end if;
 perform 1 from public.organizations where id in (r.parent_church_id,r.child_church_id) order by id for update;
 if (select count(*) from public.organizations where id in (r.parent_church_id,r.child_church_id) and status in ('active','trial'))<>2 then
  raise exception 'hierarchy_organization_unavailable' using errcode='42501';end if;
 perform 1 from auth.users where id in (r.parent_approved_by,r.child_approved_by,auth.uid()) order by id for share;
 -- Lock each original approving membership as well as the responding actor.
 -- A replacement membership for the same account cannot resurrect old consent.
 perform 1 from public.organization_memberships where id in (r.parent_approved_membership_id,r.child_approved_membership_id)
  or (organization_id=p_organization and user_id=auth.uid()) order by id for share;
 select id into actor_membership from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() and status='active' and role in ('owner','admin','pastor');
 if actor_membership is null then raise exception 'organization_access_denied' using errcode='42501';end if;
 if p_decision='reject' then
  update public.saas_hierarchy_requests set status='rejected' where id=r.id;
  insert into public.organization_hierarchy_events(request_id,parent_organization_id,child_organization_id,actor_user_id,actor_membership_id,action)
   values(r.id,r.parent_church_id,r.child_church_id,auth.uid(),actor_membership,'rejected');
  return jsonb_build_object('ok',true,'status','rejected');end if;
 if p_organization=r.parent_church_id then
  r.parent_approved_at:=stamp;r.parent_approved_by:=auth.uid();r.parent_approved_membership_id:=actor_membership;
 else r.child_approved_at:=stamp;r.child_approved_by:=auth.uid();r.child_approved_membership_id:=actor_membership;end if;
 parent_valid:=exists(select 1 from public.organization_memberships m join auth.users a on a.id=m.user_id where m.id=r.parent_approved_membership_id and m.organization_id=r.parent_church_id and m.user_id=r.parent_approved_by and m.status='active' and m.role in ('owner','admin','pastor') and a.email_confirmed_at is not null and nullif(trim(a.email),'') is not null and a.deleted_at is null and not coalesce(a.is_anonymous,false) and (a.banned_until is null or a.banned_until<=clock_timestamp()));
 child_valid:=exists(select 1 from public.organization_memberships m join auth.users a on a.id=m.user_id where m.id=r.child_approved_membership_id and m.organization_id=r.child_church_id and m.user_id=r.child_approved_by and m.status='active' and m.role in ('owner','admin','pastor') and a.email_confirmed_at is not null and nullif(trim(a.email),'') is not null and a.deleted_at is null and not coalesce(a.is_anonymous,false) and (a.banned_until is null or a.banned_until<=clock_timestamp()));
 if r.parent_approved_at is not null and r.child_approved_at is not null then
  if (r.parent_approved_by is null or r.parent_approved_membership_id is null or r.child_approved_by is null or r.child_approved_membership_id is null) then
   -- Explicit renewal flow: preserve legacy timestamps, record this side, and
   -- wait. This does not invent an approver or silently activate legacy consent.
   renewal:=true;
  elsif not parent_valid or not child_valid then raise exception 'hierarchy_previous_approval_unavailable' using errcode='42501';end if;
 end if;
 update public.saas_hierarchy_requests set parent_approved_at=r.parent_approved_at,parent_approved_by=r.parent_approved_by,parent_approved_membership_id=r.parent_approved_membership_id,
  child_approved_at=r.child_approved_at,child_approved_by=r.child_approved_by,child_approved_membership_id=r.child_approved_membership_id where id=r.id;
 insert into public.organization_hierarchy_events(request_id,parent_organization_id,child_organization_id,actor_user_id,actor_membership_id,action,metadata)
  values(r.id,r.parent_church_id,r.child_church_id,auth.uid(),actor_membership,'approved_side',jsonb_build_object('organizationId',p_organization,'renewalRequired',renewal));
 if r.parent_approved_at is not null and r.child_approved_at is not null and parent_valid and child_valid and not renewal then
  if exists(select 1 from public.saas_organization_links where child_church_id=r.child_church_id and status='active') then raise exception 'child_already_linked';end if;
  if exists(with recursive descendants(id) as (select child_church_id from public.saas_organization_links where parent_church_id=r.child_church_id and status='active' union select l.child_church_id from public.saas_organization_links l join descendants d on l.parent_church_id=d.id where l.status='active') select 1 from descendants where id=r.parent_church_id) then raise exception 'hierarchy_cycle';end if;
  insert into public.saas_organization_links(parent_church_id,child_church_id,linked_at,created_by) values(r.parent_church_id,r.child_church_id,stamp,auth.uid());
  insert into public.saas_billing_responsibilities(church_id,payer_church_id,billing_mode,updated_at)
   values(r.child_church_id,case when r.billing_mode='centralized' then r.parent_church_id else r.child_church_id end,r.billing_mode,stamp)
   on conflict(church_id) do update set payer_church_id=excluded.payer_church_id,billing_mode=excluded.billing_mode,updated_at=excluded.updated_at;
  update public.saas_hierarchy_requests set status='approved' where id=r.id;r.status:='approved';
  insert into public.organization_hierarchy_events(request_id,parent_organization_id,child_organization_id,actor_user_id,actor_membership_id,action,metadata)
   values(r.id,r.parent_church_id,r.child_church_id,auth.uid(),actor_membership,'activated',jsonb_build_object('parentApprover',r.parent_approved_by,'childApprover',r.child_approved_by,'billingMode',r.billing_mode));
 end if;
 return jsonb_build_object('ok',true,'status',r.status,'renewalRequired',renewal);
end $$;
revoke all on function public.approve_organization_hierarchy(uuid,uuid,text) from public,anon,service_role;
grant execute on function public.approve_organization_hierarchy(uuid,uuid,text) to authenticated;

create or replace function public.organization_hierarchy_requests(p_organization uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'organization_access_denied' using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(q)) from (
  select r.*,p.name parent_name,c.name child_name,
   r.status='pending' and r.parent_approved_at is not null and not exists(select 1 from public.organization_memberships m join auth.users a on a.id=m.user_id where m.id=r.parent_approved_membership_id and m.user_id=r.parent_approved_by and m.organization_id=r.parent_church_id and m.status='active' and m.role in ('owner','admin','pastor') and a.email_confirmed_at is not null and a.deleted_at is null and not coalesce(a.is_anonymous,false) and (a.banned_until is null or a.banned_until<=clock_timestamp())) parent_approval_requires_renewal,
   r.status='pending' and r.child_approved_at is not null and not exists(select 1 from public.organization_memberships m join auth.users a on a.id=m.user_id where m.id=r.child_approved_membership_id and m.user_id=r.child_approved_by and m.organization_id=r.child_church_id and m.status='active' and m.role in ('owner','admin','pastor') and a.email_confirmed_at is not null and a.deleted_at is null and not coalesce(a.is_anonymous,false) and (a.banned_until is null or a.banned_until<=clock_timestamp())) child_approval_requires_renewal
  from public.saas_hierarchy_requests r join public.organizations p on p.id=r.parent_church_id join public.organizations c on c.id=r.child_church_id
  where p_organization in (r.parent_church_id,r.child_church_id) order by r.created_at desc
 ) q),'[]');
end $$;
revoke all on function public.organization_hierarchy_requests(uuid) from public,anon,service_role;
grant execute on function public.organization_hierarchy_requests(uuid) to authenticated;

-- Link metadata only: no implicit cross-tenant people/finance/Kids permissions.
create function public.organization_hierarchy_overview(p_organization uuid,p_child uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'organization_access_denied' using errcode='42501';end if;
 select jsonb_build_object('church',jsonb_build_object('id',c.id,'name',c.name,'slug',c.slug,'registrationCode',c.registration_code,'appName',c.app_name,'primaryColor',c.primary_color,'accentColor',c.accent_color),
  'link',jsonb_build_object('id',l.id,'parentOrganizationId',l.parent_church_id,'childOrganizationId',l.child_church_id,'status',l.status),
  'generatedAt',(extract(epoch from now())*1000)::bigint)
 into result from public.saas_organization_links l join public.organizations p on p.id=l.parent_church_id join public.organizations c on c.id=l.child_church_id
 where l.parent_church_id=p_organization and l.child_church_id=p_child and l.status='active' and p.status in ('active','trial') and c.status in ('active','trial');
 if result is null then raise exception 'hierarchy_link_unavailable' using errcode='42501';end if;
 return result;
end $$;
revoke all on function public.organization_hierarchy_overview(uuid,uuid) from public,anon,service_role;
grant execute on function public.organization_hierarchy_overview(uuid,uuid) to authenticated;
