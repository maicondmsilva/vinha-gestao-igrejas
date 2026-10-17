set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- Existing RPC contract and role matrix are retained. No backfill or link change.
create or replace function public.approve_organization_hierarchy(p_request uuid,p_organization uuid,p_decision text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.saas_hierarchy_requests; stamp bigint:=(extract(epoch from now())*1000)::bigint;
begin
 if auth.uid() is null or p_organization is null or not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then
  raise exception 'organization_access_denied' using errcode='42501';
 end if;
 if p_request is null then raise exception 'invalid_request' using errcode='22023'; end if;
 if p_decision is null or p_decision not in ('approve','reject') then raise exception 'invalid_decision' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtext('organization-hierarchy'));
 select * into r from public.saas_hierarchy_requests where id=p_request for update;
 if r.id is null or p_organization not in (r.parent_church_id,r.child_church_id) then
  raise exception 'request_not_found' using errcode='42501';
 end if;
 -- Terminal requests remain read-only/idempotent; no billing or linking is repeated.
 if r.status<>'pending' then return jsonb_build_object('ok',true,'status',r.status); end if;
 -- Match ministry-governance lock order: organization before actor membership.
 -- Row locks detect concurrent state changes rather than trusting an old snapshot.
 perform 1 from public.organizations where id in (r.parent_church_id,r.child_church_id) order by id for update;
 if (select count(*) from public.organizations where id in (r.parent_church_id,r.child_church_id) and status in ('active','trial'))<>2 then
  raise exception 'hierarchy_organization_unavailable' using errcode='42501';
 end if;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid()
  and status='active' and role in ('owner','admin','pastor') for share;
 if not found then raise exception 'organization_access_denied' using errcode='42501'; end if;
 if p_decision='reject' then
  update public.saas_hierarchy_requests set status='rejected' where id=r.id;
  return jsonb_build_object('ok',true,'status','rejected');
 end if;
 if p_organization=r.parent_church_id then r.parent_approved_at:=stamp; else r.child_approved_at:=stamp; end if;
 update public.saas_hierarchy_requests set parent_approved_at=r.parent_approved_at,child_approved_at=r.child_approved_at where id=r.id;
 if r.parent_approved_at is not null and r.child_approved_at is not null then
  if exists(select 1 from public.saas_organization_links where child_church_id=r.child_church_id and status='active') then raise exception 'child_already_linked'; end if;
  if exists(with recursive descendants(id) as (select child_church_id from public.saas_organization_links where parent_church_id=r.child_church_id and status='active' union select l.child_church_id from public.saas_organization_links l join descendants d on l.parent_church_id=d.id where l.status='active') select 1 from descendants where id=r.parent_church_id) then raise exception 'hierarchy_cycle'; end if;
  insert into public.saas_organization_links(parent_church_id,child_church_id,linked_at,created_by) values(r.parent_church_id,r.child_church_id,stamp,auth.uid());
  insert into public.saas_billing_responsibilities(church_id,payer_church_id,billing_mode,updated_at) values(r.child_church_id,case when r.billing_mode='centralized' then r.parent_church_id else r.child_church_id end,r.billing_mode,stamp) on conflict(church_id) do update set payer_church_id=excluded.payer_church_id,billing_mode=excluded.billing_mode,updated_at=excluded.updated_at;
  update public.saas_hierarchy_requests set status='approved' where id=r.id; r.status:='approved';
 end if;
 return jsonb_build_object('ok',true,'status',r.status);
end $$;
revoke all on function public.approve_organization_hierarchy(uuid,uuid,text) from public,anon;
grant execute on function public.approve_organization_hierarchy(uuid,uuid,text) to authenticated;
