set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

create table public.staff_invitations(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null,
 email text not null check(email=lower(trim(email)) and length(email) between 3 and 254),
 full_name text not null check(char_length(full_name) between 2 and 160),
 role public.membership_role not null check(role<>'owner'),
 token uuid not null unique default extensions.gen_random_uuid(),
 status text not null default 'pending' check(status in ('pending','accepted','revoked')),
 created_by uuid not null references auth.users(id),
 accepted_by uuid references auth.users(id),
 accepted_membership_id uuid,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '7 days',
 accepted_at timestamptz,
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create unique index staff_invite_pending_email on public.staff_invitations(organization_id,email) where status='pending';
create index staff_invite_creator on public.staff_invitations(created_by);
create index staff_invite_accepted_by on public.staff_invitations(accepted_by);
alter table public.staff_invitations enable row level security;
revoke all on public.staff_invitations from public,anon,authenticated;
grant select on public.staff_invitations to authenticated;
create policy staff_invite_manager_read on public.staff_invitations for select to authenticated
using(private.has_organization_role(organization_id,array['owner','admin','pastor']::public.membership_role[]));

create function private.staff_role_allowed(p_organization uuid,p_role public.membership_role)
returns boolean language sql stable security invoker set search_path='' as $$
 select p_role<>'owner' and (
 private.has_organization_role(p_organization,array['owner']::public.membership_role[])
 or (p_role not in ('owner','admin') and private.has_organization_role(p_organization,array['admin']::public.membership_role[]))
 or (p_role not in ('owner','admin','pastor') and private.has_organization_role(p_organization,array['pastor']::public.membership_role[])));
$$;
revoke all on function private.staff_role_allowed(uuid,public.membership_role) from public,anon;
grant execute on function private.staff_role_allowed(uuid,public.membership_role) to authenticated;

create function public.staff_directory(p_organization uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'staff_access_denied' using errcode='42501';end if;
 return jsonb_build_object('users',coalesce((select jsonb_agg(jsonb_build_object(
 'id',m.id,'name',coalesce(p.full_name,a.email,'Usuário'),'email',a.email,'role',m.role,'status',m.status,'created_at',m.created_at,
 'unit_access',coalesce((select jsonb_agg(jsonb_build_object('unit_id',g.unit_id,'role',g.access_level,'include_children',g.include_children,'unit_name',u.name)) from public.membership_unit_access g join public.organization_units u on u.id=g.unit_id where g.membership_id=m.id and g.organization_id=p_organization),'[]')) order by m.created_at)
 from public.organization_memberships m join auth.users a on a.id=m.user_id left join public.profiles p on p.id=m.user_id where m.organization_id=p_organization),'[]'));
end $$;
revoke all on function public.staff_directory(uuid) from public,anon,service_role;
grant execute on function public.staff_directory(uuid) to authenticated;

create function public.create_staff_invitation(p_organization uuid,p_unit uuid,p_email text,p_name text,p_role public.membership_role) returns jsonb
language plpgsql security definer set search_path='' as $$
declare invited public.staff_invitations;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization and status in ('active','trial') for update;
 if not found or not private.staff_role_allowed(p_organization,p_role) then raise exception 'staff_access_denied' using errcode='42501';end if;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() and status='active' for share;
 if not found or not private.staff_role_allowed(p_organization,p_role) then raise exception 'staff_access_denied' using errcode='42501';end if;
 if p_email is null or lower(trim(p_email)) !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' or length(p_email)>254 or p_name is null or char_length(trim(p_name)) not between 2 and 160 then raise exception 'invalid_staff_invite' using errcode='22023';end if;
 if not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_organization and status='active') then raise exception 'staff_unit_unavailable' using errcode='42501';end if;
 insert into public.staff_invitations(organization_id,unit_id,email,full_name,role,created_by)
 values(p_organization,p_unit,lower(trim(p_email)),trim(p_name),p_role,auth.uid()) returning * into invited;
 return jsonb_build_object('id',invited.id,'token',invited.token,'expiresAt',invited.expires_at,'emailQueued',false);
end $$;
revoke all on function public.create_staff_invitation(uuid,uuid,text,text,public.membership_role) from public,anon,service_role;
grant execute on function public.create_staff_invitation(uuid,uuid,text,text,public.membership_role) to authenticated;

create function public.revoke_staff_invitation(p_organization uuid,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare invited public.staff_invitations;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization and status in ('active','trial') for update;
 if not found then raise exception 'staff_access_denied' using errcode='42501';end if;
 select * into invited from public.staff_invitations where id=p_id and organization_id=p_organization for update;
 if not found or invited.status<>'pending' or not private.staff_role_allowed(p_organization,invited.role) then raise exception 'staff_invite_unavailable' using errcode='42501';end if;
 update public.staff_invitations set status='revoked' where id=invited.id;
end $$;
revoke all on function public.revoke_staff_invitation(uuid,uuid) from public,anon,service_role;
grant execute on function public.revoke_staff_invitation(uuid,uuid) to authenticated;

create function public.accept_staff_invitation(p_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare account_email text;invited public.staff_invitations;emitter public.membership_role;target public.organization_memberships;oid uuid;
begin
 account_email:=private.require_confirmed_self_service_email();
 select organization_id into oid from public.staff_invitations where token=p_token;
 perform 1 from public.organizations where id=oid and status in ('active','trial') for update;
 if not found then raise exception 'staff_invite_unavailable' using errcode='42501';end if;
 select * into invited from public.staff_invitations where token=p_token for update;
 if invited.email<>account_email or invited.id is null then raise exception 'staff_invite_unavailable' using errcode='42501';end if;
 if invited.status='accepted' then
  if invited.accepted_by=auth.uid() and exists(select 1 from public.organization_memberships where id=invited.accepted_membership_id and organization_id=oid and user_id=auth.uid() and status='active') then
   return jsonb_build_object('ok',true,'alreadyAccepted',true,'slug',(select slug from public.organizations where id=oid));
  end if;
  raise exception 'staff_invite_unavailable' using errcode='42501';
 end if;
 if invited.status<>'pending' or invited.expires_at<=clock_timestamp() then raise exception 'staff_invite_unavailable' using errcode='42501';end if;
 perform 1 from auth.users where id=invited.created_by and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise exception 'staff_inviter_unavailable' using errcode='42501';end if;
 select role into emitter from public.organization_memberships where organization_id=oid and user_id=invited.created_by and status='active' for share;
 if emitter is null or invited.role='owner' or not (emitter='owner' or emitter='admin' and invited.role not in ('owner','admin') or emitter='pastor' and invited.role not in ('owner','admin','pastor')) then raise exception 'staff_inviter_unavailable' using errcode='42501';end if;
 if not exists(select 1 from public.organization_units where id=invited.unit_id and organization_id=oid and status='active') then raise exception 'staff_unit_unavailable' using errcode='42501';end if;
 select * into target from public.organization_memberships where organization_id=oid and user_id=auth.uid() for update;
 if found then
  if target.status<>'active' then raise exception 'staff_membership_unavailable' using errcode='42501';end if;
  -- Existing accounts are never promoted or moved to another default unit by invite.
 else
  insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
  values(oid,auth.uid(),invited.role,'active',invited.unit_id) returning * into target;
  if invited.role not in ('admin','pastor') then
   insert into public.membership_unit_access(organization_id,membership_id,unit_id,access_level,include_children)
   values(oid,target.id,invited.unit_id,case when invited.role in ('secretary','leader') then 'manage'::public.unit_access_level else 'read'::public.unit_access_level end,false);
  end if;
 end if;
 update public.staff_invitations set status='accepted',accepted_by=auth.uid(),accepted_membership_id=target.id,accepted_at=clock_timestamp() where id=invited.id;
 return jsonb_build_object('ok',true,'alreadyAccepted',false,'slug',(select slug from public.organizations where id=oid));
end $$;
revoke all on function public.accept_staff_invitation(uuid) from public,anon,service_role;
grant execute on function public.accept_staff_invitation(uuid) to authenticated;

create function public.replace_staff_unit_access(p_organization uuid,p_membership uuid,p_entries jsonb) returns integer
language plpgsql security invoker set search_path='' as $$
declare target public.organization_memberships;entry jsonb;unit uuid;level public.unit_access_level;total integer:=0;
begin
 if not private.has_organization_role(p_organization,array['owner','admin']::public.membership_role[]) then raise exception 'staff_access_denied' using errcode='42501';end if;
 select * into target from public.organization_memberships where id=p_membership and organization_id=p_organization for update;
 if not found then raise exception 'staff_access_denied' using errcode='42501';end if;
 perform private.check_membership_governance(p_organization,target.id,target.user_id,target.role,target.status,'UPDATE');
 if p_entries is null or jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries)>100 then raise exception 'invalid_staff_access' using errcode='22023';end if;
 delete from public.membership_unit_access where membership_id=p_membership and organization_id=p_organization;
 for entry in select value from jsonb_array_elements(p_entries) loop
  if jsonb_typeof(entry)<>'object' or coalesce(entry->>'level','') not in ('read','manage','admin') or jsonb_typeof(entry->'includeChildren')<>'boolean' then raise exception 'invalid_staff_access' using errcode='22023';end if;
  unit:=(entry->>'unitId')::uuid;level:=(entry->>'level')::public.unit_access_level;
  if not exists(select 1 from public.organization_units where id=unit and organization_id=p_organization and status='active') then raise exception 'invalid_staff_access' using errcode='22023';end if;
  insert into public.membership_unit_access(organization_id,membership_id,unit_id,access_level,include_children) values(p_organization,p_membership,unit,level,(entry->>'includeChildren')::boolean);total:=total+1;
 end loop;
 return total;
end $$;
revoke all on function public.replace_staff_unit_access(uuid,uuid,jsonb) from public,anon;
grant execute on function public.replace_staff_unit_access(uuid,uuid,jsonb) to authenticated;
