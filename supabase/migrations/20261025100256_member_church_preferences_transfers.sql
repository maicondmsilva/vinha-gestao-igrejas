set local lock_timeout='5s';
-- Content preference is not an authorization or membership source.
create table private.member_church_preferences(
 organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),unit_id uuid not null,
 primary key(organization_id,user_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index member_church_preferences_user on private.member_church_preferences(user_id);
create index member_church_preferences_unit on private.member_church_preferences(unit_id,organization_id);
create table private.member_church_transfers(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id),person_id uuid not null references public.people(id),source_unit uuid not null,target_unit uuid not null,
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),reason text not null default '',
 created_at timestamptz not null default clock_timestamp(),reviewed_at timestamptz,reviewed_by uuid references auth.users(id),
 check(source_unit<>target_unit),foreign key(source_unit,organization_id) references public.organization_units(id,organization_id),foreign key(target_unit,organization_id) references public.organization_units(id,organization_id)
);
create unique index member_church_transfer_pending on private.member_church_transfers(organization_id,user_id) where status='pending';
create index member_church_transfer_user on private.member_church_transfers(user_id);
create index member_church_transfer_person on private.member_church_transfers(person_id);
create index member_church_transfer_source on private.member_church_transfers(source_unit,organization_id);
create index member_church_transfer_target on private.member_church_transfers(target_unit,organization_id);
create index member_church_transfer_reviewer on private.member_church_transfers(reviewed_by);
create table private.member_publications(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 kind text not null check(kind in('notice','event','video','service')),title text not null check(length(title) between 2 and 160),body text not null check(length(body)<=4000),
 url text not null default '' check(url='' or url ~ '^https://[^[:space:]]+$'),published boolean not null default false,created_at timestamptz not null default clock_timestamp(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index member_publications_scope on private.member_publications(organization_id,unit_id,published,created_at);
alter table private.member_church_preferences enable row level security;
alter table private.member_church_transfers enable row level security;
alter table private.member_publications enable row level security;
revoke all on private.member_church_preferences,private.member_church_transfers,private.member_publications from public,anon,authenticated,service_role;

create function private.member_church(p_org uuid,p_action text,p_unit uuid default null,p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;person public.people;t private.member_church_transfers;selected uuid;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in('active','trial') for update;
 if not found then raise exception 'member_app_denied' using errcode='42501';end if;
 select * into m from public.organization_memberships where organization_id=p_org and user_id=auth.uid() for update;
 if m.status in('suspended','revoked') then raise exception 'member_app_denied' using errcode='42501';end if;
 if (select count(*) from public.people where organization_id=p_org and auth_user_id=auth.uid() and status<>'rejected')>1 then raise exception 'member_identity_ambiguous' using errcode='40001';end if;
 select * into person from public.people where organization_id=p_org and auth_user_id=auth.uid() and status<>'rejected' for update;
 if p_action='select' then
  perform 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active' for share;
  if not found then raise exception 'member_unit_denied' using errcode='42501';end if;
  insert into private.member_church_preferences values(p_org,auth.uid(),p_unit) on conflict(organization_id,user_id) do update set unit_id=excluded.unit_id;
 elsif p_action='request' then
  if m.status is distinct from 'active' or person.id is null or person.status in('inactive','deceased','rejected') then raise exception 'member_transfer_identity' using errcode='42501';end if;
  perform 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active' for share;
  if not found or p_unit is not distinct from person.unit_id then raise exception 'member_unit_denied' using errcode='42501';end if;
  if exists(select 1 from private.member_profile_requests where organization_id=p_org and user_id=auth.uid() and status='pending') then raise exception 'member_request_pending' using errcode='40001';end if;
  select * into t from private.member_church_transfers where organization_id=p_org and user_id=auth.uid() and status='pending' for update;
  if t.id is not null and t.target_unit<>p_unit then raise exception 'member_request_pending' using errcode='40001';end if;
  if t.id is null then
   if (select count(*) from private.member_church_transfers where user_id=auth.uid() and created_at>clock_timestamp()-interval '1 day')>=20 then raise exception 'member_daily_limit' using errcode='54000';end if;
   insert into private.member_church_transfers(organization_id,user_id,person_id,source_unit,target_unit) values(p_org,auth.uid(),person.id,person.unit_id,p_unit) returning * into t;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.church.requested','member_church_transfer',t.id);
  end if;
 elsif p_action='cancel' then
  update private.member_church_transfers set status='cancelled',reviewed_at=clock_timestamp(),reviewed_by=auth.uid() where id=p_id and organization_id=p_org and user_id=auth.uid() and status='pending' returning * into t;
  if not found then raise exception 'member_request_changed' using errcode='40001';end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.church.cancelled','member_church_transfer',t.id);
 elsif p_action is distinct from 'state' then raise exception 'invalid_member_action' using errcode='22023';end if;
 select pref.unit_id into selected from private.member_church_preferences pref join public.organization_units u on u.id=pref.unit_id and u.organization_id=pref.organization_id and u.status='active' where pref.organization_id=p_org and pref.user_id=auth.uid();
 return jsonb_build_object('ok',true,'selectedUnit',coalesce(selected,person.unit_id,m.default_unit_id),'officialUnit',person.unit_id,'canRequest',m.status='active' and person.id is not null,
 'transfers',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(select id,source_unit,target_unit,status,reason,created_at from private.member_church_transfers where organization_id=p_org and user_id=auth.uid() order by created_at desc limit 20)x),'[]'));
end $$;
revoke all on function private.member_church(uuid,text,uuid,uuid) from public,anon,service_role;
grant execute on function private.member_church(uuid,text,uuid,uuid) to authenticated;
create function public.member_church(p_org uuid,p_action text,p_unit uuid default null,p_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.member_church(p_org,p_action,p_unit,p_id)$$;
revoke all on function public.member_church(uuid,text,uuid,uuid) from public,anon,service_role;
grant execute on function public.member_church(uuid,text,uuid,uuid) to authenticated;

create function private.member_church_admin(p_org uuid,p_action text,p_id uuid default null,p_unit uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare t private.member_church_transfers;person public.people;m public.organization_memberships;v_id uuid;decision text;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in('active','trial') for update;
 if not found or not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'member_review_denied' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select req.id,req.source_unit,req.target_unit,req.created_at,p.full_name,s.name source_name,d.name target_name from private.member_church_transfers req join public.people p on p.id=req.person_id join public.organization_units s on s.id=req.source_unit join public.organization_units d on d.id=req.target_unit where req.organization_id=p_org and req.status='pending' and private.can_access_unit(p_org,req.source_unit,array['manage','admin']::public.unit_access_level[]) and private.can_access_unit(p_org,req.target_unit,array['manage','admin']::public.unit_access_level[]) order by req.created_at limit 100)x),'[]'),
   'publications',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,unit_id,kind,title,body,url,published from private.member_publications where organization_id=p_org and private.can_access_unit(p_org,unit_id,array['manage','admin']::public.unit_access_level[]) order by created_at desc limit 100)x),'[]'));
 elsif p_action='review' then
  if p_data-array['decision','reason']<>'{}' or p_data->>'decision' not in('approved','rejected') or coalesce(length(trim(p_data->>'reason')),0) not between 5 and 1000 then raise exception 'invalid_member_review' using errcode='22023';end if;
  decision:=p_data->>'decision';
  select * into t from private.member_church_transfers where id=p_id and organization_id=p_org for update;
  if not found or t.status<>'pending' then raise exception 'member_request_changed' using errcode='40001';end if;
  if t.user_id=auth.uid() or not private.can_access_unit(p_org,t.source_unit,array['manage','admin']::public.unit_access_level[]) or not private.can_access_unit(p_org,t.target_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'member_review_denied' using errcode='42501';end if;
  if decision='approved' then
   select * into m from public.organization_memberships where organization_id=p_org and user_id=t.user_id for update;
   select * into person from public.people where id=t.person_id and organization_id=p_org for update;
   if m.status is distinct from 'active' or person.auth_user_id is distinct from t.user_id or person.unit_id is distinct from t.source_unit or person.status in('inactive','deceased','rejected') then raise exception 'member_transfer_identity' using errcode='40001';end if;
   -- Administrative grants require a separate access review; never migrate them implicitly.
   if m.role<>'member' or exists(select 1 from public.membership_unit_access where membership_id=m.id and access_level<>'read') then raise exception 'member_transfer_access_review' using errcode='40001';end if;
   perform 1 from public.organization_units where id=t.target_unit and organization_id=p_org and status='active' for share;
   if not found or exists(select 1 from private.member_profile_requests where organization_id=p_org and user_id=t.user_id and status='pending') then raise exception 'member_request_changed' using errcode='40001';end if;
   perform 1 from auth.users where id=t.user_id and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=clock_timestamp()) for share;
   if not found then raise exception 'member_review_denied' using errcode='42501';end if;
   update public.people set unit_id=t.target_unit where id=person.id;
   -- Keep roles and explicit grants untouched. Default unit is only a navigation preference.
   update public.organization_memberships set default_unit_id=t.target_unit where id=m.id;
  end if;
  update private.member_church_transfers set status=decision,reason=trim(p_data->>'reason'),reviewed_by=auth.uid(),reviewed_at=clock_timestamp() where id=t.id;
  v_id:=t.id;
 elsif p_action='publish' then
  if p_data-array['kind','title','body','url']<>'{}' or jsonb_typeof(p_data)<>'object' or coalesce(p_data->>'kind','') not in('notice','event','video','service') or coalesce(length(trim(p_data->>'title')),0) not between 2 and 160 or coalesce(length(p_data->>'body'),0)>4000 or coalesce(length(p_data->>'url'),0)>2000 or coalesce(p_data->>'url','')<>'' and p_data->>'url' !~ '^https://[^[:space:]]+$' then raise exception 'invalid_member_publication' using errcode='22023';end if;
  perform 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active' for share;
  if not found or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'member_unit_denied' using errcode='42501';end if;
  insert into private.member_publications(organization_id,unit_id,kind,title,body,url,published) values(p_org,p_unit,p_data->>'kind',trim(p_data->>'title'),coalesce(p_data->>'body',''),coalesce(p_data->>'url',''),true) returning id into v_id;
 elsif p_action='unpublish' then
  update private.member_publications set published=false where id=p_id and organization_id=p_org and private.can_access_unit(p_org,unit_id,array['manage','admin']::public.unit_access_level[]) returning id into v_id;
  if not found then raise exception 'member_review_denied' using errcode='42501';end if;
 else raise exception 'invalid_member_action' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.church.'||p_action,'member_church',v_id,jsonb_build_object('decision',decision));
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
revoke all on function private.member_church_admin(uuid,text,uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function private.member_church_admin(uuid,text,uuid,uuid,jsonb) to authenticated;
create function public.member_church_admin(p_org uuid,p_action text,p_id uuid default null,p_unit uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_church_admin(p_org,p_action,p_id,p_unit,p_data)$$;
revoke all on function public.member_church_admin(uuid,text,uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.member_church_admin(uuid,text,uuid,uuid,jsonb) to authenticated;

create function member_app_api.feed(p_org uuid,p_unit uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 return jsonb_build_object('unitId',p_unit,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(select id,kind,title,body,url,created_at from private.member_publications where organization_id=p_org and unit_id=p_unit and published order by created_at desc limit 100)x),'[]'));
end $$;
revoke all on function member_app_api.feed(uuid,uuid) from public,service_role;
grant execute on function member_app_api.feed(uuid,uuid) to anon,authenticated;
create function public.member_public_feed(p_org uuid,p_unit uuid) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.feed(p_org,p_unit)$$;
revoke all on function public.member_public_feed(uuid,uuid) from public,service_role;
grant execute on function public.member_public_feed(uuid,uuid) to anon,authenticated;
