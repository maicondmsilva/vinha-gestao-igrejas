-- S3: invitations are internal records, never proof of external delivery.
alter table private.scale_services drop constraint scale_services_status_check;
alter table private.scale_services add constraint scale_services_status_check check(status in('draft','published','closed','cancelled'));
alter table private.scale_roles add column parallel_allowed boolean not null default false;
alter table private.scale_teams add column travel_minutes integer not null default 0 check(travel_minutes between 0 and 240);
create table private.scale_qualifications(
 organization_id uuid not null,unit_id uuid not null,team_id uuid not null,member_id uuid not null,role_id uuid not null,active boolean not null default true,
 primary key(member_id,role_id),
 foreign key(member_id,team_id,organization_id,unit_id) references private.scale_members(id,team_id,organization_id,unit_id),
 foreign key(role_id,team_id,organization_id,unit_id) references private.scale_roles(id,team_id,organization_id,unit_id)
);
create index scale_qualifications_role on private.scale_qualifications(role_id,team_id,organization_id,unit_id);
create table private.scale_availability(
 id uuid primary key,organization_id uuid not null,person_id uuid not null,kind text not null check(kind in('weekly','unavailable')),
 weekday integer check(weekday between 0 and 6),start_minute integer check(start_minute between 0 and 1439),end_minute integer check(end_minute between 1 and 1440),
 starts_at timestamptz,ends_at timestamptz,reason text not null default '' check(length(reason)<=500),active boolean not null default true,version integer not null default 1,
 foreign key(person_id,organization_id) references public.people(id,organization_id),
 check((kind='weekly' and weekday is not null and start_minute is not null and end_minute>start_minute and starts_at is null and ends_at is null) or(kind='unavailable' and starts_at is not null and ends_at>starts_at and weekday is null and start_minute is null and end_minute is null))
);
create index scale_availability_person on private.scale_availability(person_id,organization_id,active);
create table private.scale_invites(
 id uuid primary key default extensions.gen_random_uuid(),service_id uuid not null,organization_id uuid not null,unit_id uuid not null,team_id uuid not null,role_id uuid not null,ordinal integer not null,
 member_id uuid not null,person_id uuid not null,response text not null default 'pending' check(response in('pending','accepted','declined')),
 active boolean not null default true,ended_reason text not null default '',presence text not null default 'unset' check(presence in('unset','present','absent')),
 invited_at timestamptz not null default now(),deadline timestamptz not null,replied_at timestamptz,replied_by uuid references auth.users(id),reply_reason text not null default '',
 presence_by uuid references auth.users(id),presence_at timestamptz,presence_reason text not null default '',version integer not null default 1,snapshot jsonb not null default '{}',
 foreign key(service_id,organization_id,unit_id) references private.scale_services(id,organization_id,unit_id),
 foreign key(role_id,team_id,organization_id,unit_id) references private.scale_roles(id,team_id,organization_id,unit_id),
 foreign key(member_id,team_id,organization_id,unit_id) references private.scale_members(id,team_id,organization_id,unit_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create unique index scale_invite_slot on private.scale_invites(service_id,role_id,ordinal) where active;
create index scale_invites_person on private.scale_invites(person_id,organization_id,unit_id,invited_at desc);
create index scale_invites_role on private.scale_invites(role_id,team_id,organization_id,unit_id);
create index scale_invites_member on private.scale_invites(member_id,team_id,organization_id,unit_id);
create index scale_invites_reply_actor on private.scale_invites(replied_by);
create index scale_invites_presence_actor on private.scale_invites(presence_by);
create function private.scale_invite_snapshot() returns trigger language plpgsql set search_path='' as $$begin
 select jsonb_build_object('title',title,'arrival',arrival_at,'starts',starts_at,'ends',ends_at) into new.snapshot from private.scale_services where id=new.service_id and organization_id=new.organization_id and unit_id=new.unit_id;
 return new;end$$;
revoke all on function private.scale_invite_snapshot() from public,anon,authenticated,service_role;
create trigger scale_invite_snapshot before insert on private.scale_invites for each row execute function private.scale_invite_snapshot();
create table private.scale_replacements(
 id uuid primary key,invite_id uuid not null references private.scale_invites(id),organization_id uuid not null,unit_id uuid not null,team_id uuid not null,
 suggested_member uuid,suggested_role uuid,note text not null default '' check(length(note)<=500),state text not null default 'pending' check(state in('pending','approved','rejected','cancelled')),
 decision text not null default '' check(length(decision)<=1000),decided_by uuid references auth.users(id),created_at timestamptz not null default now(),version integer not null default 1,
 foreign key(suggested_member,team_id,organization_id,unit_id) references private.scale_members(id,team_id,organization_id,unit_id)
);
create unique index scale_replacement_pending on private.scale_replacements(invite_id) where state='pending';
create index scale_replacements_team on private.scale_replacements(organization_id,unit_id,team_id,state);
create index scale_replacements_suggestion on private.scale_replacements(suggested_member,team_id,organization_id,unit_id);
create index scale_replacements_actor on private.scale_replacements(decided_by);
create table private.scale_person_history(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null,person_id uuid not null,actor uuid not null references auth.users(id),action text not null,data jsonb not null,created_at timestamptz not null default now(),
 foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create index scale_person_history_person on private.scale_person_history(person_id,organization_id,created_at desc);
create index scale_person_history_actor on private.scale_person_history(actor);
create trigger scale_person_history_immutable before update or delete on private.scale_person_history for each row execute function private.scale_immutable();
do $$declare t text;begin foreach t in array array['scale_qualifications','scale_availability','scale_invites','scale_replacements','scale_person_history'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('create policy deny_client on private.%I as restrictive for all to anon,authenticated,service_role using(false) with check(false)',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end$$;

create function private.scale_qualified(o uuid,u uuid,m uuid,r uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.scale_members sm join public.people p on p.id=sm.person_id and p.organization_id=o and p.unit_id=u and p.status='active'
 join private.scale_roles sr on sr.id=r and sr.team_id=sm.team_id and sr.active join private.scale_teams t on t.id=sm.team_id and t.active
 where sm.id=m and sm.organization_id=o and sm.unit_id=u and sm.active and (sm.role_id=r or exists(select 1 from private.scale_qualifications q where q.member_id=m and q.role_id=r and q.active)));
$$;
revoke all on function private.scale_qualified(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;

-- Contains only conflict categories. Private personal reasons never leave this helper.
create function private.scale_conflicts(sid uuid,rid uuid,mid uuid,slot integer) returns text[] language plpgsql stable security definer set search_path='' as $$
declare s private.scale_services;m private.scale_members;r private.scale_roles;reasons text[]:='{}';a timestamp;b timestamp;d date;lo integer;hi integer;travel integer;
begin
 if mid is null then return '{}';end if;
 select * into s from private.scale_services where id=sid;select * into m from private.scale_members where id=mid;select * into r from private.scale_roles where id=rid;
 if s.id is null or not private.scale_qualified(s.organization_id,s.unit_id,mid,rid) then return array['qualification'];end if;
 select travel_minutes into travel from private.scale_teams where id=m.team_id;
 if exists(select 1 from private.scale_availability where person_id=m.person_id and active and kind='unavailable' and starts_at<s.ends_at and ends_at>s.arrival_at) then reasons:=array_append(reasons,'unavailable');end if;
 a:=s.arrival_at at time zone s.timezone;b:=s.ends_at at time zone s.timezone;
 if exists(select 1 from private.scale_availability where person_id=m.person_id and active and kind='weekly') then
  for d in select generate_series(a::date,(b-interval '1 microsecond')::date,interval '1 day')::date loop
   lo:=case when d=a::date then extract(hour from a)::integer*60+extract(minute from a)::integer else 0 end;
   hi:=case when d=b::date then extract(hour from b)::integer*60+extract(minute from b)::integer else 1440 end;
   if not exists(select 1 from private.scale_availability where person_id=m.person_id and active and kind='weekly' and weekday=extract(dow from d) and start_minute<=lo and end_minute>=hi) then reasons:=array_append(reasons,'availability');exit;end if;
  end loop;
 end if;
 if exists(select 1 from private.scale_positions q join private.scale_members mm on mm.id=q.member_id where q.service_id=sid and q.role_id=rid and q.ordinal<>slot and mm.person_id=m.person_id) then reasons:=array_append(reasons,'duplicate');end if;
 if exists(select 1 from private.scale_positions q join private.scale_services x on x.id=q.service_id join private.scale_members other_m on other_m.id=q.member_id join private.scale_roles other_r on other_r.id=q.role_id join private.scale_teams other_t on other_t.id=q.team_id
 where other_m.person_id=m.person_id and x.organization_id=s.organization_id and x.status in('draft','published') and not(q.service_id=sid and q.role_id=rid and q.ordinal=slot)
 and (x.status='draft' or exists(select 1 from private.scale_invites i where i.service_id=x.id and i.role_id=q.role_id and i.ordinal=q.ordinal and i.active and i.response in('pending','accepted')))
 and ((x.id=sid and not(r.parallel_allowed and other_r.parallel_allowed)) or(x.id<>sid and x.arrival_at<s.ends_at+make_interval(mins=>greatest(travel,other_t.travel_minutes)) and x.ends_at+make_interval(mins=>greatest(travel,other_t.travel_minutes))>s.arrival_at))) then reasons:=array_append(reasons,'overlap');end if;
 return reasons;
end$$;
revoke all on function private.scale_conflicts(uuid,uuid,uuid,integer) from public,anon,authenticated,service_role;

-- Extend S2 queries, keeping its draft-only mutation guard. Published services
-- must go through an explicit revision before changing times or positions.
do $$declare def text;old text;new text;begin
 def:=replace(pg_get_functiondef('private.scale_planning(uuid,uuid,text,jsonb)'::regprocedure),E'\r\n',E'\n');
 old:='state not in(''all'',''draft'',''cancelled'')';new:='state not in(''all'',''draft'',''published'',''closed'',''cancelled'')';
 if strpos(def,old)=0 then raise exception 'S2 status guard not found';end if;def:=replace(def,old,new);
 old:='if exists(select 1 from jsonb_array_elements(roster)p join private.scale_members m on m.id=nullif(p->>''member'','''')::uuid group by m.person_id having count(*)>1) then';
 new:='if exists(select 1 from jsonb_array_elements(roster)p join private.scale_members m on m.id=nullif(p->>''member'','''')::uuid join private.scale_roles role on role.id=(p->>''role'')::uuid group by m.person_id having count(*)>1 and (count(distinct role.id)<count(*) or not bool_and(role.parallel_allowed))) then';
 if strpos(def,old)=0 then raise exception 'S2 coexistence guard not found';end if;execute replace(def,old,new);
end$$;

create function private.scale_operations(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare sid uuid:=nullif(p_data->>'service','')::uuid;team uuid:=nullif(p_data->>'team','')::uuid;eid uuid:=nullif(p_data->>'id','')::uuid;
 s private.scale_services;i private.scale_invites;case_row private.scale_replacements;member private.scale_members;role_row private.scale_roles;t private.scale_teams;
 targets uuid[];versions jsonb;token text;scope text:=coalesce(p_data->>'scope','current');reason text:=btrim(coalesce(p_data->>'reason',''));items jsonb;result jsonb;before_data jsonb;
 req uuid;fingerprint text;prior private.scale_planning_requests;conflicts text[];candidate uuid:=nullif(p_data->>'member','')::uuid;selected_role uuid:=nullif(p_data->>'role','')::uuid;
 pos record;next_invite uuid;new_response text:=p_data->>'response';new_presence text:=p_data->>'presence';page integer:=coalesce((p_data->>'page')::integer,1);search text:=btrim(coalesce(p_data->>'search',''));
begin
 perform private.require_confirmed_self_service_email();
 if p_action is null or p_action not in('view','pending','settings','suggest','qualify','policy','publish','revise','cancel','close','reply','replace','fill','presence','decision') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>16000 or page not between 1 and 10000 or length(search)>100 or length(reason)>1000 then raise exception 'scale_input' using errcode='22023';end if;
 if p_action in('view','pending','settings','suggest') then perform 1 from public.organizations where id=p_org for share;else perform 1 from public.organizations where id=p_org for update;end if;
 if not private.scale_allowed(p_org,p_unit,team,'read') then raise exception 'scale_access_denied' using errcode='42501';end if;
 if p_action='pending' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select i.id,i.service_id,i.response,i.deadline,i.version,s.title,s.starts_at,p.full_name name,t.name team,r.name role,
   (select count(*) from private.scale_replacements c where c.invite_id=i.id and c.state='pending') replacements
   from private.scale_invites i join private.scale_services s on s.id=i.service_id join public.people p on p.id=i.person_id join private.scale_teams t on t.id=i.team_id join private.scale_roles r on r.id=i.role_id
   where i.organization_id=p_org and i.unit_id=p_unit and i.active and s.status='published' and (i.response='pending' or exists(select 1 from private.scale_replacements c where c.invite_id=i.id and c.state='pending')) and (team is null or i.team_id=team) and private.scale_service_allowed(p_org,p_unit,s.id,'read') order by i.deadline,i.id limit 30 offset (page-1)*30)x),'[]'),
   'total',(select count(*) from private.scale_invites i join private.scale_services s on s.id=i.service_id where i.organization_id=p_org and i.unit_id=p_unit and i.active and s.status='published' and (i.response='pending' or exists(select 1 from private.scale_replacements c where c.invite_id=i.id and c.state='pending')) and (team is null or i.team_id=team) and private.scale_service_allowed(p_org,p_unit,s.id,'read')));
 end if;
 if p_action='settings' then
  if team is null or not private.scale_allowed(p_org,p_unit,team,'manage') or not exists(select 1 from private.scale_teams where id=team and organization_id=p_org and unit_id=p_unit) then raise exception 'scale_access_denied' using errcode='42501';end if;
  return jsonb_build_object('team',(select jsonb_build_object('id',id,'name',name,'travel',travel_minutes,'version',version) from private.scale_teams where id=team),
   'roles',coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,parallel_allowed,version from private.scale_roles where team_id=team and active order by name,id)r),'[]'),
   'members',coalesce((select jsonb_agg(to_jsonb(x)) from(select m.id,m.version,p.full_name name,m.role_id,coalesce((select jsonb_agg(role_id) from private.scale_qualifications q where q.member_id=m.id and active),'[]') qualifications from private.scale_members m join public.people p on p.id=m.person_id where m.team_id=team and m.active and p.unit_id=p_unit and p.status='active' and (search='' or strpos(lower(p.full_name),lower(search))>0) order by p.full_name,m.id limit 20 offset (page-1)*20)x),'[]'),
   'total',(select count(*) from private.scale_members m join public.people p on p.id=m.person_id where m.team_id=team and m.active and p.unit_id=p_unit and p.status='active' and (search='' or strpos(lower(p.full_name),lower(search))>0)));
 end if;
 if p_action in('qualify','policy') then
  if team is null or not private.scale_allowed(p_org,p_unit,team,'manage') or not exists(select 1 from private.scale_teams where id=team and organization_id=p_org and unit_id=p_unit and active) then raise exception 'scale_access_denied' using errcode='42501';end if;
 else
  if p_action in('reply','replace','presence') then select * into i from private.scale_invites where id=eid and organization_id=p_org and unit_id=p_unit;sid:=i.service_id;
  elsif p_action='decision' then select * into case_row from private.scale_replacements where id=eid and organization_id=p_org and unit_id=p_unit;select * into i from private.scale_invites where id=case_row.invite_id;sid:=i.service_id;end if;
  select * into s from private.scale_services where id=sid and organization_id=p_org and unit_id=p_unit;
  if not found or not private.scale_service_allowed(p_org,p_unit,sid,'read') then raise exception 'scale_access_denied' using errcode='42501';end if;
  if scope not in('current','following','all') then raise exception 'scale_input' using errcode='22023';end if;
  select array_agg(id order by starts_at,id),jsonb_agg(jsonb_build_object('id',id,'version',version) order by starts_at,id) into targets,versions from private.scale_services where id=sid or(series_id=s.series_id and (scope='all' or(scope='following' and starts_at>=s.starts_at)));
  if exists(select 1 from unnest(targets)x where not private.scale_service_allowed(p_org,p_unit,x,'read')) then raise exception 'scale_access_denied' using errcode='42501';end if;token:=md5(versions::text);
  if p_action='view' then
   return jsonb_build_object('service',to_jsonb(s),'token',token,'affected',cardinality(targets),'confirmed',(select count(*) from private.scale_invites where service_id=any(targets) and active and response='accepted'),
    'canPublish',not exists(select 1 from unnest(targets)x where not private.scale_service_allowed(p_org,p_unit,x,'publish')),
    'slots',coalesce((select jsonb_agg(to_jsonb(x) order by "teamName","roleName",ordinal) from(select q.*,t.name "teamName",r.name "roleName",p.full_name name,private.scale_conflicts(sid,q.role_id,q.member_id,q.ordinal) conflicts,private.scale_allowed(p_org,p_unit,q.team_id,'assign') "canAssign",private.scale_allowed(p_org,p_unit,q.team_id,'publish') "canPublish",p.auth_user_id is not null "hasAccount" from private.scale_positions q join private.scale_teams t on t.id=q.team_id join private.scale_roles r on r.id=q.role_id left join private.scale_members m on m.id=q.member_id left join public.people p on p.id=m.person_id where service_id=sid)x),'[]'),
    'invites',coalesce((select jsonb_agg(to_jsonb(x) order by invited_at desc,id) from(select i.*,p.full_name name,r.name role,t.name team from private.scale_invites i join public.people p on p.id=i.person_id join private.scale_roles r on r.id=i.role_id join private.scale_teams t on t.id=i.team_id where service_id=sid order by invited_at desc,id limit 500)x),'[]'),
    'requests',coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc,id) from(select c.*,p.full_name suggested_name from private.scale_replacements c join private.scale_invites i on i.id=c.invite_id left join private.scale_members m on m.id=c.suggested_member left join public.people p on p.id=m.person_id where i.service_id=sid order by c.created_at desc,c.id limit 100)x),'[]'));
  end if;
  if p_action='suggest' then
   select * into role_row from private.scale_roles where id=selected_role and organization_id=p_org and unit_id=p_unit;
   if role_row.id is null or not private.scale_allowed(p_org,p_unit,role_row.team_id,'assign') then raise exception 'scale_access_denied' using errcode='42501';end if;
   return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select m.id,p.full_name name,
    private.scale_conflicts(sid,selected_role,m.id,coalesce((p_data->>'ordinal')::integer,1)) conflicts,
    (select count(*) from private.scale_invites i join private.scale_services ss on ss.id=i.service_id where i.person_id=p.id and i.active and i.response<>'declined' and ss.status<>'cancelled' and ss.starts_at between s.starts_at-interval '30 days' and s.starts_at) recent
    from private.scale_members m join public.people p on p.id=m.person_id where m.team_id=role_row.team_id and private.scale_qualified(p_org,p_unit,m.id,selected_role) and (search='' or strpos(lower(p.full_name),lower(search))>0) order by cardinality(private.scale_conflicts(sid,selected_role,m.id,coalesce((p_data->>'ordinal')::integer,1))),recent,p.full_name,m.id limit 20 offset (page-1)*20)x),'[]'));
  end if;
  if p_action in('publish','revise','cancel','close') then
   if exists(select 1 from unnest(targets)x where not private.scale_service_allowed(p_org,p_unit,x,'publish')) then raise exception 'scale_access_denied' using errcode='42501';end if;
  elsif p_action='fill' then
   select * into role_row from private.scale_roles where id=selected_role and organization_id=p_org and unit_id=p_unit;
   if role_row.id is null or not private.scale_allowed(p_org,p_unit,role_row.team_id,'assign') or not private.scale_allowed(p_org,p_unit,role_row.team_id,'publish') then raise exception 'scale_access_denied' using errcode='42501';end if;
  elsif i.id is null or not private.scale_allowed(p_org,p_unit,i.team_id,'assign') then raise exception 'scale_access_denied' using errcode='42501';end if;
 end if;
 req:=(p_data->>'request')::uuid;if req is null then raise exception 'scale_input' using errcode='22023';end if;
 fingerprint:=md5(jsonb_build_object('rpc','operations','org',p_org,'unit',p_unit,'action',p_action,'data',p_data)::text);
 select * into prior from private.scale_planning_requests where id=req;
 if found then if prior.organization_id<>p_org or prior.unit_id<>p_unit or prior.actor<>auth.uid() or prior.fingerprint<>fingerprint then raise exception 'scale_changed' using errcode='40001';end if;return prior.result;end if;
 if p_action='qualify' then
  select * into member from private.scale_members where id=candidate and team_id=team;
  if member.id is null or not exists(select 1 from private.scale_roles where id=selected_role and team_id=team and active) then raise exception 'scale_role_invalid' using errcode='22023';end if;
  if member.version is distinct from (p_data->>'version')::integer then raise exception 'scale_changed' using errcode='40001';end if;
  if member.role_id=selected_role and not coalesce((p_data->>'active')::boolean,false) then raise exception 'scale_primary_role' using errcode='22023';end if;
  insert into private.scale_qualifications(organization_id,unit_id,team_id,member_id,role_id,active) values(p_org,p_unit,team,candidate,selected_role,coalesce((p_data->>'active')::boolean,true)) on conflict(member_id,role_id) do update set active=excluded.active;
  update private.scale_members set version=version+1 where id=candidate;
  insert into private.scale_history(organization_id,unit_id,team_id,actor,action,after_data) values(p_org,p_unit,team,auth.uid(),'qualification',p_data-'request');
 elsif p_action='policy' then
  if selected_role is not null then
   select * into role_row from private.scale_roles where id=selected_role and team_id=team;
   if role_row.id is null then raise exception 'scale_role_invalid' using errcode='22023';end if;
   if role_row.version is distinct from(p_data->>'version')::integer then raise exception 'scale_changed' using errcode='40001';end if;
   update private.scale_roles set parallel_allowed=coalesce((p_data->>'parallel')::boolean,false),version=version+1 where id=selected_role;
  else
   select * into t from private.scale_teams where id=team;
   if t.version is distinct from(p_data->>'version')::integer then raise exception 'scale_changed' using errcode='40001';end if;
   update private.scale_teams set travel_minutes=(p_data->>'travel')::integer,version=version+1 where id=team;
  end if;
  insert into private.scale_history(organization_id,unit_id,team_id,actor,action,after_data) values(p_org,p_unit,team,auth.uid(),'policy',p_data-'request');
 elsif p_action in('publish','revise','cancel','close') then
  if p_data->>'token' is distinct from token then raise exception 'scale_changed' using errcode='40001';end if;
  if p_action in('revise','cancel') and length(reason)<10 then raise exception 'scale_reason' using errcode='22023';end if;
  for s in select * from private.scale_services where id=any(targets) order by starts_at,id loop
   if (p_action='publish' and (s.status<>'draft' or s.arrival_at<=now())) or(p_action='revise' and s.status<>'published') or(p_action='cancel' and s.status not in('draft','published')) or(p_action='close' and (s.status<>'published' or s.ends_at>now())) then raise exception 'scale_state' using errcode='22023';end if;
   before_data:=to_jsonb(s);
   if p_action='publish' then
    for pos in select * from private.scale_positions where service_id=s.id and member_id is not null loop
     conflicts:=private.scale_conflicts(s.id,pos.role_id,pos.member_id,pos.ordinal);
     if not private.scale_qualified(p_org,p_unit,pos.member_id,pos.role_id) then raise exception 'scale_qualification' using errcode='22023';end if;
     if 'duplicate'=any(conflicts) then raise exception 'scale_person_duplicate' using errcode='22023';end if;
     if cardinality(conflicts)>0 and (not coalesce((p_data->>'override')::boolean,false) or length(reason)<10) then raise exception 'scale_conflict' using errcode='22023';end if;
     insert into private.scale_invites(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,deadline)
     select s.id,p_org,p_unit,pos.team_id,pos.role_id,pos.ordinal,m.id,m.person_id,least(s.arrival_at,now()+make_interval(hours=>t.reply_hours)) from private.scale_members m join private.scale_teams t on t.id=m.team_id where m.id=pos.member_id;
    end loop;
   elsif p_action in('revise','cancel') then
    update private.scale_invites set active=false,ended_reason=case p_action when 'revise' then 'revision' else 'cancelled' end,version=version+1 where service_id=s.id and active;
    update private.scale_replacements set state='cancelled',decision=reason,decided_by=auth.uid(),version=version+1 where invite_id in(select id from private.scale_invites where service_id=s.id) and state='pending';
   end if;
   update private.scale_services set status=case p_action when 'publish' then 'published' when 'revise' then 'draft' when 'cancel' then 'cancelled' else 'closed' end,version=version+1 where id=s.id;
   insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,before_data,after_data) values(s.id,p_org,p_unit,auth.uid(),p_action,before_data,jsonb_build_object('reason',reason,'override',coalesce((p_data->>'override')::boolean,false),'confirmedBefore',(select count(*) from private.scale_invites where service_id=s.id and response='accepted')));
  end loop;
 elsif p_action='fill' then
  if s.version is distinct from(p_data->>'version')::integer then raise exception 'scale_changed' using errcode='40001';end if;
  if s.status<>'published' or s.arrival_at<=now() or not exists(select 1 from private.scale_positions q where q.service_id=sid and q.role_id=selected_role and q.ordinal=(p_data->>'ordinal')::integer and q.member_id is null) then raise exception 'scale_state' using errcode='22023';end if;
  if not private.scale_qualified(p_org,p_unit,candidate,selected_role) then raise exception 'scale_qualification' using errcode='22023';end if;
  conflicts:=private.scale_conflicts(sid,selected_role,candidate,(p_data->>'ordinal')::integer);
  if 'duplicate'=any(conflicts) then raise exception 'scale_person_duplicate' using errcode='22023';end if;
     if cardinality(conflicts)>0 and(not coalesce((p_data->>'override')::boolean,false) or length(reason)<10) then raise exception 'scale_conflict' using errcode='22023';end if;
  update private.scale_positions q set member_id=candidate where q.service_id=sid and q.role_id=selected_role and q.ordinal=(p_data->>'ordinal')::integer;
  insert into private.scale_invites(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,deadline)
   select sid,p_org,p_unit,role_row.team_id,selected_role,(p_data->>'ordinal')::integer,m.id,m.person_id,least(s.arrival_at,now()+make_interval(hours=>t.reply_hours)) from private.scale_members m join private.scale_teams t on t.id=m.team_id where m.id=candidate;
  update private.scale_services set version=version+1 where id=sid;
  insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,after_data) values(sid,p_org,p_unit,auth.uid(),'fill',p_data-'request');
 elsif p_action in('reply','replace','presence','decision') then
  if not i.active or s.status not in('published','closed') then raise exception 'scale_state' using errcode='22023';end if;
  if (case when p_action='decision' then case_row.version else i.version end) is distinct from(p_data->>'version')::integer then raise exception 'scale_changed' using errcode='40001';end if;
  before_data:=to_jsonb(i);
  if p_action='reply' then
   if new_response is null or new_response not in('accepted','declined') or length(reason)<10 or s.status<>'published' or s.ends_at<=now() then raise exception 'scale_reason' using errcode='22023';end if;
   update private.scale_invites set response=new_response,replied_at=now(),replied_by=auth.uid(),reply_reason=reason,version=version+1 where id=i.id;
  elsif p_action='presence' then
   if new_presence is null or new_presence not in('present','absent','unset') or now()<s.arrival_at-interval '2 hours' or now()>s.ends_at+interval '7 days' or(i.presence<>'unset' and length(reason)<5) then raise exception 'scale_presence' using errcode='22023';end if;
   update private.scale_invites set presence=new_presence,presence_at=now(),presence_by=auth.uid(),presence_reason=reason,version=version+1 where id=i.id;
  elsif p_action='decision' and p_data->>'decision'='reject' then
   if case_row.state<>'pending' or length(reason)<5 then raise exception 'scale_reason' using errcode='22023';end if;
   update private.scale_replacements set state='rejected',decision=reason,decided_by=auth.uid(),version=version+1 where id=case_row.id;
  else
   if s.status<>'published' or s.arrival_at<=now() or candidate is null or(p_action='decision' and case_row.state<>'pending') then raise exception 'scale_state' using errcode='22023';end if;
   if not private.scale_allowed(p_org,p_unit,i.team_id,'publish') or length(reason)<10 then raise exception 'scale_reason' using errcode='22023';end if;
   if not private.scale_qualified(p_org,p_unit,candidate,i.role_id) or candidate=i.member_id then raise exception 'scale_qualification' using errcode='22023';end if;
   conflicts:=private.scale_conflicts(s.id,i.role_id,candidate,i.ordinal);
   if 'duplicate'=any(conflicts) then raise exception 'scale_person_duplicate' using errcode='22023';end if;
     if cardinality(conflicts)>0 and not coalesce((p_data->>'override')::boolean,false) then raise exception 'scale_conflict' using errcode='22023';end if;
   update private.scale_invites set active=false,ended_reason='replaced',version=version+1 where id=i.id;
   update private.scale_positions set member_id=candidate where service_id=s.id and role_id=i.role_id and ordinal=i.ordinal;
   insert into private.scale_invites(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,deadline)
    select s.id,p_org,p_unit,i.team_id,i.role_id,i.ordinal,m.id,m.person_id,least(s.arrival_at,now()+make_interval(hours=>t.reply_hours)) from private.scale_members m join private.scale_teams t on t.id=m.team_id where m.id=candidate returning id into next_invite;
   update private.scale_replacements set state=case when id=eid then 'approved' else 'cancelled' end,decision=reason,decided_by=auth.uid(),version=version+1 where invite_id=i.id and state='pending';
  end if;
  update private.scale_services set version=version+1 where id=s.id;
  insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,before_data,after_data) values(s.id,p_org,p_unit,auth.uid(),p_action,before_data,jsonb_build_object('invite',i.id,'response',new_response,'presence',new_presence,'reason',reason,'replacement',next_invite));
 end if;
 result:=jsonb_build_object('ok',true,'service',sid,'count',coalesce(cardinality(targets),1));
 insert into private.scale_planning_requests(id,organization_id,unit_id,actor,fingerprint,result) values(req,p_org,p_unit,auth.uid(),fingerprint,result);return result;
end$$;
revoke all on function private.scale_operations(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.scale_operations(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.scale_operations(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.scale_operations(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.scale_operations(uuid,uuid,text,jsonb),public.scale_operations(uuid,uuid,text,jsonb) to authenticated;

create function private.scale_volunteer(p_org uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare person uuid;unit uuid;zone text;eid uuid:=nullif(p_data->>'id','')::uuid;req uuid;fingerprint text;prior private.scale_planning_requests;result jsonb;
 i private.scale_invites;s private.scale_services;a private.scale_availability;c private.scale_replacements;candidate uuid:=nullif(p_data->>'suggestion','')::uuid;
 new_response text:=p_data->>'response';kind text:=p_data->>'kind';input_version integer:=(p_data->>'version')::integer;
 page integer:=coalesce((p_data->>'page')::integer,1);reason text:=coalesce(p_data->>'reason','');is_active boolean:=coalesce((p_data->>'active')::boolean,true);lo integer;hi integer;starts timestamptz;ends timestamptz;
begin
 if p_action is null or p_action not in('list','availability','reply','available.save','replacement.request','replacement.cancel','suggest') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>6000 or page not between 1 and 10000 or length(reason)>500 then raise exception 'scale_input' using errcode='22023';end if;
 -- Uses the OFFICIAL canonical member, never a followed/content church or client person ID.
 person:=private.community_identity(p_org,null,true);
 select unit_id into unit from public.people where id=person;
 if not private.target_unit_module_enabled(p_org,unit,'scales') or not private.target_unit_module_enabled(p_org,unit,'people') or not exists(select 1 from public.organization_units where id=unit and organization_id=p_org and status='active') then raise exception 'scale_access_denied' using errcode='42501';end if;
 zone:=private.unit_timezone(unit);
 if p_action='list' then
  return jsonb_build_object('unit',unit,'unitName',(select name from public.organization_units where id=unit),'timezone',zone,
   'items',coalesce((select jsonb_agg(to_jsonb(x)) from(select i.id,i.version,i.response,i.active,i.ended_reason,i.presence,i.deadline,i.replied_at,i.reply_reason<>'' "recordedByLeader",
    case when i.active then s.title else i.snapshot->>'title' end title,case when i.active then s.starts_at else(i.snapshot->>'starts')::timestamptz end starts_at,case when i.active then s.ends_at else(i.snapshot->>'ends')::timestamptz end ends_at,case when i.active then s.arrival_at else(i.snapshot->>'arrival')::timestamptz end arrival_at,s.status,r.name role,t.name team,
    case when i.active then s.location else '' end location,case when i.active then s.notes else '' end notes,
    i.active and s.status='published' and now()<least(i.deadline,s.arrival_at) and exists(select 1 from private.scale_members where id=i.member_id and active) "canReply",
    (select jsonb_build_object('id',id,'version',version,'state',state) from private.scale_replacements where invite_id=i.id and state='pending') replacement
    from private.scale_invites i join private.scale_services s on s.id=i.service_id join private.scale_roles r on r.id=i.role_id join private.scale_teams t on t.id=i.team_id
    where i.person_id=person and i.organization_id=p_org and i.unit_id=unit and s.status in('published','closed','cancelled','draft') and (i.active or i.invited_at>now()-interval '90 days') order by s.starts_at desc,i.id limit 20 offset (page-1)*20)x),'[]'),
   'total',(select count(*) from private.scale_invites i where i.person_id=person and i.organization_id=p_org and i.unit_id=unit and(i.active or i.invited_at>now()-interval '90 days')));
 end if;
 if p_action='availability' then
  return jsonb_build_object('timezone',zone,'items',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,kind,weekday,start_minute,end_minute,starts_at,ends_at,reason,active,version from private.scale_availability where organization_id=p_org and person_id=person order by active desc,kind,weekday,starts_at,id limit 30 offset (page-1)*30)x),'[]'),'total',(select count(*) from private.scale_availability where organization_id=p_org and person_id=person));
 end if;
 if p_action in('reply','replacement.request','suggest') then select * into i from private.scale_invites where id=eid and organization_id=p_org and unit_id=unit and person_id=person;
 elsif p_action='replacement.cancel' then select * into c from private.scale_replacements where id=eid and organization_id=p_org and unit_id=unit;select * into i from private.scale_invites where id=c.invite_id and person_id=person;end if;
 if p_action<>'available.save' and i.id is null then raise exception 'scale_access_denied' using errcode='42501';end if;
 if p_action<>'available.save' then select * into s from private.scale_services where id=i.service_id;end if;
 if p_action='suggest' then
  if not i.active or s.status<>'published' or now()>=s.arrival_at then raise exception 'scale_state' using errcode='22023';end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select m.id,p.full_name name from private.scale_members m join public.people p on p.id=m.person_id where m.team_id=i.team_id and m.person_id<>person and private.scale_qualified(p_org,unit,m.id,i.role_id) and length(btrim(coalesce(p_data->>'search','')))>=2 and strpos(lower(p.full_name),lower(p_data->>'search'))>0 order by p.full_name,m.id limit 20)x),'[]'));
 end if;
 req:=(p_data->>'request')::uuid;if req is null then raise exception 'scale_input' using errcode='22023';end if;
 fingerprint:=md5(jsonb_build_object('rpc','volunteer','org',p_org,'action',p_action,'data',p_data)::text);
 select * into prior from private.scale_planning_requests where id=req;
 if found then if prior.organization_id<>p_org or prior.actor<>auth.uid() or prior.fingerprint<>fingerprint then raise exception 'scale_changed' using errcode='40001';end if;return prior.result;end if;
 if p_action<>'available.save' and(not i.active or s.status<>'published' or now()>=s.arrival_at or not exists(select 1 from private.scale_members where id=i.member_id and active)) then raise exception 'scale_state' using errcode='22023';end if;
 if p_action='available.save' then
  if eid is null then raise exception 'scale_input' using errcode='22023';end if;
  select * into a from private.scale_availability where id=eid;
  if found and(a.organization_id<>p_org or a.person_id<>person) then raise exception 'scale_access_denied' using errcode='42501';end if;
  if coalesce(a.version,0) is distinct from input_version then raise exception 'scale_changed' using errcode='40001';end if;
  if not is_active and a.id is null then raise exception 'scale_input' using errcode='22023';end if;
  if a.id is not null and not is_active then update private.scale_availability set active=false,version=scale_availability.version+1 where id=eid;
  else
   if kind='weekly' then lo:=(p_data->>'startMinute')::integer;hi:=(p_data->>'endMinute')::integer;
   elsif kind='unavailable' then starts:=(p_data->>'startsLocal')::timestamp at time zone zone;ends:=(p_data->>'endsLocal')::timestamp at time zone zone;
   else raise exception 'scale_input' using errcode='22023';end if;
   insert into private.scale_availability(id,organization_id,person_id,kind,weekday,start_minute,end_minute,starts_at,ends_at,reason,active)
   values(eid,p_org,person,kind,case when kind='weekly' then(p_data->>'weekday')::integer end,lo,hi,starts,ends,reason,true)
   on conflict(id) do update set kind=excluded.kind,weekday=excluded.weekday,start_minute=excluded.start_minute,end_minute=excluded.end_minute,starts_at=excluded.starts_at,ends_at=excluded.ends_at,reason=excluded.reason,active=true,version=scale_availability.version+1;
  end if;
  insert into private.scale_person_history(organization_id,person_id,actor,action,data) values(p_org,person,auth.uid(),p_action,p_data-'request');
 else
  if (case when p_action='replacement.cancel' then c.version else i.version end) is distinct from input_version then raise exception 'scale_changed' using errcode='40001';end if;
  if p_action='reply' then
   if new_response is null or new_response not in('accepted','declined') or now()>=i.deadline then raise exception 'scale_deadline' using errcode='22023';end if;
   update private.scale_invites set response=new_response,replied_at=now(),replied_by=auth.uid(),reply_reason='',version=scale_invites.version+1 where id=i.id;
  elsif p_action='replacement.request' then
   if candidate is not null and (candidate=i.member_id or not private.scale_qualified(p_org,unit,candidate,i.role_id)) then raise exception 'scale_qualification' using errcode='22023';end if;
   insert into private.scale_replacements(id,invite_id,organization_id,unit_id,team_id,suggested_member,note) values(req,i.id,p_org,unit,i.team_id,candidate,reason);
   update private.scale_invites set version=scale_invites.version+1 where id=i.id;
  else
   if c.state<>'pending' then raise exception 'scale_state' using errcode='22023';end if;
   update private.scale_replacements set state='cancelled',version=scale_replacements.version+1 where id=c.id;
  end if;
  update private.scale_services set version=scale_services.version+1 where id=s.id;
  insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,before_data,after_data) values(s.id,p_org,unit,auth.uid(),p_action,to_jsonb(i),jsonb_build_object('invite',i.id,'response',new_response,'request',case when p_action='replacement.request' then req else c.id end));
 end if;
 result:=jsonb_build_object('ok',true);insert into private.scale_planning_requests(id,organization_id,unit_id,actor,fingerprint,result) values(req,p_org,unit,auth.uid(),fingerprint,result);return result;
end$$;
revoke all on function private.scale_volunteer(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.scale_volunteer(p_org uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.scale_volunteer(p_org,p_action,p_data)$$;
revoke all on function public.scale_volunteer(uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.scale_volunteer(uuid,text,jsonb),public.scale_volunteer(uuid,text,jsonb) to authenticated;


