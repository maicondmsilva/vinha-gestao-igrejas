-- S1: teams are local service teams, not tenant organizations. Legacy schedule
-- endpoints stay contained; this foundation grants no financial/Kids access.
create table private.scale_teams(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 100),description text not null default '' check(length(description)<=1000),
 active boolean not null default true,reply_hours integer not null default 48 check(reply_hours between 1 and 720),reminder_hours integer not null default 24 check(reminder_hours between 1 and 168),
 version integer not null default 1,updated_at timestamptz not null default now(),
 unique(id,organization_id,unit_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create unique index scale_team_name on private.scale_teams(organization_id,unit_id,lower(btrim(name)));
create table private.scale_roles(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,team_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 80),required_count integer not null default 1 check(required_count between 1 and 100),active boolean not null default true,version integer not null default 1,
 unique(id,team_id,organization_id,unit_id),foreign key(team_id,organization_id,unit_id) references private.scale_teams(id,organization_id,unit_id)
);
create unique index scale_role_name on private.scale_roles(team_id,lower(btrim(name)));
create table private.scale_members(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,team_id uuid not null,person_id uuid not null,role_id uuid,
 active boolean not null default true,version integer not null default 1,
 unique(team_id,person_id),unique(id,team_id,organization_id,unit_id),
 foreign key(team_id,organization_id,unit_id) references private.scale_teams(id,organization_id,unit_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id),
 foreign key(role_id,team_id,organization_id,unit_id) references private.scale_roles(id,team_id,organization_id,unit_id)
);
create index scale_members_person on private.scale_members(person_id,organization_id);
create index scale_members_role on private.scale_members(role_id,team_id,organization_id,unit_id);
create table private.scale_grants(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,team_id uuid not null,member_id uuid not null,
 membership_id uuid not null references public.organization_memberships(id),
 capabilities text[] not null check(cardinality(capabilities) between 1 and 4 and capabilities<@array['read','manage','assign','publish']),
 active boolean not null default true,version integer not null default 1,
 unique(team_id,membership_id),foreign key(member_id,team_id,organization_id,unit_id) references private.scale_members(id,team_id,organization_id,unit_id)
);
create index scale_grants_membership on private.scale_grants(membership_id,team_id);
create index scale_grants_member on private.scale_grants(member_id,team_id,organization_id,unit_id);
create table private.scale_history(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null,unit_id uuid not null,team_id uuid not null,
 actor uuid not null references auth.users(id),action text not null,before_data jsonb,after_data jsonb,created_at timestamptz not null default now(),
 foreign key(team_id,organization_id,unit_id) references private.scale_teams(id,organization_id,unit_id)
);
create index scale_history_team on private.scale_history(team_id,created_at desc,id);
create index scale_history_actor on private.scale_history(actor);
create table private.scale_requests(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,actor uuid not null references auth.users(id),fingerprint text not null,result jsonb not null,created_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index scale_requests_actor on private.scale_requests(actor);
create index scale_requests_unit on private.scale_requests(organization_id,unit_id);
do $$declare t text;begin
 foreach t in array array['scale_teams','scale_roles','scale_members','scale_grants','scale_history','scale_requests'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('create policy %I on private.%I as restrictive for all using(false) with check(false)',t||'_deny',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;
create function private.scale_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'scale_history_immutable' using errcode='42501';end$$;
revoke all on function private.scale_immutable() from public,anon,authenticated,service_role;
create trigger scale_history_immutable before update or delete on private.scale_history for each row execute function private.scale_immutable();
create trigger scale_requests_immutable before update or delete on private.scale_requests for each row execute function private.scale_immutable();

create function private.scale_admin(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]);
$$;
create function private.scale_allowed(p_org uuid,p_unit uuid,p_team uuid,p_cap text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.can_access_unit(p_org,p_unit) and private.target_unit_module_enabled(p_org,p_unit,'scales') and private.target_unit_module_enabled(p_org,p_unit,'people')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'))
 and (private.scale_admin(p_org,p_unit) or exists(
 select 1 from private.scale_grants g join public.organization_memberships om on om.id=g.membership_id and om.organization_id=g.organization_id
 join private.scale_members tm on tm.id=g.member_id and tm.team_id=g.team_id and tm.active
 join public.people person on person.id=tm.person_id and person.organization_id=p_org and person.unit_id=p_unit and person.auth_user_id=om.user_id and person.status='active'
 join private.scale_teams t on t.id=g.team_id and t.active
 where g.organization_id=p_org and g.unit_id=p_unit and (p_team is null or g.team_id=p_team) and g.active and om.user_id=auth.uid() and om.status='active'
 and (p_cap='read' or p_cap=any(g.capabilities))));
$$;
revoke all on function private.scale_admin(uuid,uuid),private.scale_allowed(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

create function private.scale_foundation(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare team uuid:=nullif(p_data->>'team','')::uuid;rid uuid:=nullif(p_data->>'request','')::uuid;eid uuid:=nullif(p_data->>'id','')::uuid;
 v integer:=coalesce((p_data->>'version')::integer,0);old jsonb;new_data jsonb;result jsonb;fingerprint text;prior private.scale_requests;
 tm private.scale_members;membership uuid;person uuid;role_id uuid;cap text;total integer;page integer:=coalesce((p_data->>'page')::integer,1);search text:=btrim(coalesce(p_data->>'search',''));items jsonb;admin boolean;
begin
 perform private.require_confirmed_self_service_email();
 if jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>12000 then raise exception 'invalid_scale_input' using errcode='22023';end if;
 -- Shared row lock order serializes permission changes with all writes.
 if p_action in('team','role','member','grant') then perform 1 from public.organizations where id=p_org for update;
 else perform 1 from public.organizations where id=p_org for share;end if;
 if not private.scale_allowed(p_org,p_unit,team,'read') then raise exception 'scale_access_denied' using errcode='42501';end if;
 admin:=private.scale_admin(p_org,p_unit);
 if page not between 1 and 10000 or length(search)>100 then raise exception 'invalid_scale_input' using errcode='22023';end if;
 if team is not null and not exists(select 1 from private.scale_teams where id=team and organization_id=p_org and unit_id=p_unit) then raise exception 'scale_access_denied' using errcode='42501';end if;
 if p_action='list' then
  select count(*) into total from private.scale_teams t where organization_id=p_org and unit_id=p_unit and private.scale_allowed(p_org,p_unit,t.id,'read') and (search='' or strpos(lower(t.name),lower(search))>0);
  select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('canManage',private.scale_allowed(p_org,p_unit,t.id,'manage'),'canAssign',private.scale_allowed(p_org,p_unit,t.id,'assign'),'canPublish',private.scale_allowed(p_org,p_unit,t.id,'publish'),'members',(select count(*) from private.scale_members m where m.team_id=t.id and m.active)) order by t.name,t.id),'[]') into items from(select * from private.scale_teams t where organization_id=p_org and unit_id=p_unit and private.scale_allowed(p_org,p_unit,t.id,'read') and(search='' or strpos(lower(t.name),lower(search))>0) order by name,id limit 20 offset (page-1)*20)t;
  return jsonb_build_object('teams',items,'total',total,'page',page,'canAdmin',admin,'unit',p_unit);
 end if;
 if p_action='detail' and team is not null then
  return jsonb_build_object('team',(select to_jsonb(t) from private.scale_teams t where id=team),
   'roles',coalesce((select jsonb_agg(to_jsonb(x) order by x.name,x.id) from private.scale_roles x where team_id=team),'[]'),
   'membersTotal',(select count(*) from private.scale_members where team_id=team),'members',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('name',p.full_name,'hasAccount',p.auth_user_id is not null,'personActive',p.status='active' and p.unit_id=p_unit,'roleName',r.name) order by p.full_name,m.id) from (select m.* from private.scale_members m join public.people p on p.id=m.person_id where m.team_id=team order by p.full_name,m.id limit 30 offset (page-1)*30) m join public.people p on p.id=m.person_id left join private.scale_roles r on r.id=m.role_id where m.team_id=team),'[]'),
   'grants',case when admin then coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('name',p.full_name,'personActive',m.active and p.status='active' and p.unit_id=p_unit,'accountActive',om.status='active') order by p.full_name) from private.scale_grants g join private.scale_members m on m.id=g.member_id join public.people p on p.id=m.person_id join public.organization_memberships om on om.id=g.membership_id where g.team_id=team),'[]') else '[]'::jsonb end,
   'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id) from(select h.id,h.action,h.created_at,coalesce(nullif(p.full_name,''),'Usuário da plataforma') actor_name from private.scale_history h left join public.profiles p on p.id=h.actor where h.team_id=team order by h.created_at desc,h.id limit 50)h),'[]'),
   'canAdmin',admin,'canManage',private.scale_allowed(p_org,p_unit,team,'manage'));
 end if;
 if p_action='people' and team is not null and private.scale_allowed(p_org,p_unit,team,'manage') then
  if length(search)<2 then return jsonb_build_object('people','[]'::jsonb);end if;
  return jsonb_build_object('people',coalesce((select jsonb_agg(to_jsonb(p)) from(select id,full_name,auth_user_id is not null as "hasAccount" from public.people where organization_id=p_org and unit_id=p_unit and status='active' and strpos(lower(full_name),lower(search))>0 order by full_name,id limit 20)p),'[]'));
 end if;
 if p_action is null or p_action not in('team','role','member','grant') or eid is null or rid is null or v<0 then raise exception 'invalid_scale_input' using errcode='22023';end if;
 cap:=case when p_action='grant' or (p_action='team' and team is null) then 'admin' else 'manage' end;
 if (cap='admin' and not admin) or(cap<>'admin' and (team is null or not private.scale_allowed(p_org,p_unit,team,cap))) then raise exception 'scale_access_denied' using errcode='42501';end if;
 fingerprint:=md5(jsonb_build_object('org',p_org,'unit',p_unit,'action',p_action,'data',p_data)::text);
 select * into prior from private.scale_requests where id=rid;
 if found then
  if prior.organization_id<>p_org or prior.unit_id<>p_unit or prior.actor<>auth.uid() or prior.fingerprint<>fingerprint then raise exception 'scale_request_conflict' using errcode='40001';end if;
  return prior.result;
 end if;
 if p_action='team' then
  if team is not null and team<>eid then raise exception 'invalid_scale_input' using errcode='22023';end if;
  select to_jsonb(x) into old from private.scale_teams x where id=eid;
 elsif p_action='role' then select to_jsonb(x) into old from private.scale_roles x where id=eid;
 elsif p_action='member' then select to_jsonb(x) into old from private.scale_members x where id=eid;
 else select to_jsonb(x) into old from private.scale_grants x where id=eid;end if;
 if old is not null and (old->>'organization_id'<>p_org::text or old->>'unit_id'<>p_unit::text or (p_action<>'team' and old->>'team_id'<>team::text)) then raise exception 'scale_access_denied' using errcode='42501';end if;
 if coalesce((old->>'version')::integer,0)<>v then raise exception 'scale_version_conflict' using errcode='40001';end if;
 if p_action<>'team' and not exists(select 1 from private.scale_teams where id=team and active) then raise exception 'scale_team_inactive' using errcode='22023';end if;
 if old is null and p_action='role' and (select count(*) from private.scale_roles where team_id=team)>=100 then raise exception 'scale_role_limit' using errcode='22023';end if;
 if p_action='team' then
  insert into private.scale_teams(id,organization_id,unit_id,name,description,active,reply_hours,reminder_hours) values(eid,p_org,p_unit,btrim(p_data->>'name'),coalesce(p_data->>'description',''),coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'replyHours')::integer,48),coalesce((p_data->>'reminderHours')::integer,24))
  on conflict(id) do update set name=excluded.name,description=excluded.description,active=excluded.active,reply_hours=excluded.reply_hours,reminder_hours=excluded.reminder_hours,version=private.scale_teams.version+1,updated_at=now() returning to_jsonb(scale_teams.*) into new_data;
  team:=eid;
 elsif p_action='role' then
  insert into private.scale_roles(id,organization_id,unit_id,team_id,name,required_count,active) values(eid,p_org,p_unit,team,btrim(p_data->>'name'),coalesce((p_data->>'requiredCount')::integer,1),coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set name=excluded.name,required_count=excluded.required_count,active=excluded.active,version=private.scale_roles.version+1 returning to_jsonb(scale_roles.*) into new_data;
 elsif p_action='member' then
  person:=(p_data->>'person')::uuid;role_id:=nullif(p_data->>'role','')::uuid;
  if old is not null and old->>'person_id'<>person::text then raise exception 'scale_identity_immutable' using errcode='22023';end if;
  if not exists(select 1 from public.people where id=person and organization_id=p_org and unit_id=p_unit and status='active') and (old is null or coalesce((p_data->>'active')::boolean,true)) then raise exception 'scale_person_invalid' using errcode='22023';end if;
  if coalesce((p_data->>'active')::boolean,true) and role_id is not null and not exists(select 1 from private.scale_roles where id=role_id and team_id=team and active) then raise exception 'scale_role_invalid' using errcode='22023';end if;
  insert into private.scale_members(id,organization_id,unit_id,team_id,person_id,role_id,active) values(eid,p_org,p_unit,team,person,role_id,coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set role_id=excluded.role_id,active=excluded.active,version=private.scale_members.version+1 returning to_jsonb(scale_members.*) into new_data;
 else
  select * into tm from private.scale_members where id=(p_data->>'member')::uuid and team_id=team;
  select om.id into membership from public.organization_memberships om join public.people p on p.auth_user_id=om.user_id and p.id=tm.person_id and p.organization_id=p_org and p.unit_id=p_unit and p.status='active' where om.organization_id=p_org and om.status='active' and tm.active;
  if membership is null and (old is null or coalesce((p_data->>'active')::boolean,true)) then raise exception 'scale_account_required' using errcode='22023';end if;
  membership:=coalesce(membership,(old->>'membership_id')::uuid);
  if old is not null and (old->>'member_id'<>tm.id::text or old->>'membership_id'<>membership::text) then raise exception 'scale_identity_immutable' using errcode='22023';end if;
  if jsonb_typeof(p_data->'capabilities')<>'array' then raise exception 'invalid_scale_input' using errcode='22023';end if;
  insert into private.scale_grants(id,organization_id,unit_id,team_id,member_id,membership_id,capabilities,active) values(eid,p_org,p_unit,team,tm.id,membership,array(select jsonb_array_elements_text(p_data->'capabilities')),coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set capabilities=excluded.capabilities,active=excluded.active,version=private.scale_grants.version+1 returning to_jsonb(scale_grants.*) into new_data;
 end if;
 insert into private.scale_history(organization_id,unit_id,team_id,actor,action,before_data,after_data) values(p_org,p_unit,team,auth.uid(),p_action,old,new_data);
 result:=jsonb_build_object('ok',true,'id',eid,'team',team,'version',(new_data->>'version')::integer);
 insert into private.scale_requests(id,organization_id,unit_id,actor,fingerprint,result) values(rid,p_org,p_unit,auth.uid(),fingerprint,result);
 return result;
end $$;
revoke all on function private.scale_foundation(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.scale_foundation(uuid,uuid,text,jsonb) to authenticated;
create function public.scale_foundation(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.scale_foundation(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.scale_foundation(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.scale_foundation(uuid,uuid,text,jsonb) to authenticated;
