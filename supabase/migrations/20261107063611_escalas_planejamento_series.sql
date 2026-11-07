-- S2: local planning only. No invitations, replies or notifications are fabricated.
create table private.scale_services(
 id uuid primary key, organization_id uuid not null, unit_id uuid not null, series_id uuid not null,
 title text not null check(length(btrim(title)) between 2 and 160), event_id uuid,
 location text not null default '' check(length(location)<=300), notes text not null default '' check(length(notes)<=2000), coordinator_id uuid,
 arrival_at timestamptz not null, starts_at timestamptz not null, ends_at timestamptz not null,
 timezone text not null, status text not null default 'draft' check(status in('draft','cancelled')),
 version integer not null default 1, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(id,organization_id,unit_id), check(arrival_at<=starts_at and ends_at>starts_at and ends_at-arrival_at<=interval '7 days'),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(event_id,organization_id,unit_id) references private.church_app_events(id,organization_id,unit_id),
 foreign key(coordinator_id,organization_id) references public.people(id,organization_id)
);
create index scale_services_period on private.scale_services(organization_id,unit_id,starts_at,id);
create index scale_services_series on private.scale_services(series_id,starts_at,id);
create index scale_services_event on private.scale_services(event_id,organization_id,unit_id);
create index scale_services_coordinator on private.scale_services(coordinator_id,organization_id);
create index scale_services_creator on private.scale_services(created_by);
create table private.scale_positions(
 service_id uuid not null, organization_id uuid not null, unit_id uuid not null, team_id uuid not null, role_id uuid not null,
 ordinal integer not null check(ordinal between 1 and 100), member_id uuid,
 primary key(service_id,role_id,ordinal),
 foreign key(service_id,organization_id,unit_id) references private.scale_services(id,organization_id,unit_id),
 foreign key(role_id,team_id,organization_id,unit_id) references private.scale_roles(id,team_id,organization_id,unit_id),
 foreign key(member_id,team_id,organization_id,unit_id) references private.scale_members(id,team_id,organization_id,unit_id)
);
create index scale_positions_team on private.scale_positions(team_id,service_id);
create index scale_positions_role on private.scale_positions(role_id,team_id,organization_id,unit_id);
create index scale_positions_member on private.scale_positions(member_id,team_id,organization_id,unit_id);
create table private.scale_service_history(
 id uuid primary key default extensions.gen_random_uuid(), service_id uuid not null, organization_id uuid not null, unit_id uuid not null,
 actor uuid not null references auth.users(id), action text not null, before_data jsonb, after_data jsonb not null, created_at timestamptz not null default now(),
 foreign key(service_id,organization_id,unit_id) references private.scale_services(id,organization_id,unit_id)
);
create index scale_service_history_lookup on private.scale_service_history(service_id,created_at desc);
create index scale_service_history_actor on private.scale_service_history(actor);
create table private.scale_planning_requests(
 id uuid primary key, organization_id uuid not null, unit_id uuid not null, actor uuid not null references auth.users(id),
 fingerprint text not null, result jsonb not null, created_at timestamptz not null default now()
);
create index scale_planning_requests_actor on private.scale_planning_requests(actor);
do $$declare t text;begin foreach t in array array['scale_services','scale_positions','scale_service_history','scale_planning_requests'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('create policy deny_client on private.%I as restrictive for all to anon,authenticated,service_role using(false) with check(false)',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;end$$;
create trigger scale_service_history_immutable before update or delete on private.scale_service_history for each row execute function private.scale_immutable();
create trigger scale_planning_requests_immutable before update or delete on private.scale_planning_requests for each row execute function private.scale_immutable();

-- A shared service is readable only when EVERY team is readable. A team leader
-- cannot use a common occurrence to discover another team's roster/history.
create function private.scale_service_allowed(o uuid,u uuid,s uuid,cap text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.scale_allowed(o,u,null,cap) and exists(select 1 from private.scale_services where id=s and organization_id=o and unit_id=u)
 and not exists(select 1 from private.scale_positions where service_id=s and not private.scale_allowed(o,u,team_id,cap));
$$;
revoke all on function private.scale_service_allowed(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

create function private.scale_planning(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare sid uuid:=nullif(p_data->>'id','')::uuid;team uuid:=nullif(p_data->>'team','')::uuid;
 search text:=btrim(coalesce(p_data->>'search',''));page integer:=coalesce((p_data->>'page')::integer,1);
 zone text:=private.unit_timezone(p_unit);items jsonb;total integer;row private.scale_services;target private.scale_services;
 rid uuid;prior private.scale_planning_requests;fingerprint text;result jsonb;before_data jsonb;after_data jsonb;
 ids uuid[];versions jsonb;dates jsonb:='[]';scope text:=coalesce(p_data->>'scope','current');
 title text;loc text;notes text;event uuid;coordinator uuid;start_local timestamp;end_local timestamp;arrival_local timestamp;
 next_start timestamp;next_end timestamp;next_arrival timestamp;delta interval;step interval;rule text;n integer;i integer;tid uuid;roster jsonb;pos jsonb;ordinal integer;member uuid;role_id uuid;can_assign boolean;
 first_day date;last_day date;state text:=coalesce(p_data->>'status','all');op text:=case when p_action='preview' then coalesce(p_data->>'operation','save') else p_action end;
begin
 perform private.require_confirmed_self_service_email();
 if p_action is null or p_action not in('list','choices','detail','preview','save','cancel','duplicate') or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>100000 then raise exception 'scale_input' using errcode='22023';end if;
 if p_action in('save','cancel','duplicate') then perform 1 from public.organizations where id=p_org for update;else perform 1 from public.organizations where id=p_org for share;end if;
 if not private.scale_allowed(p_org,p_unit,null,'read') then raise exception 'scale_access_denied' using errcode='42501';end if;
 if page not between 1 and 10000 or length(search)>100 then raise exception 'scale_input' using errcode='22023';end if;
 if p_action='choices' then
  if not private.scale_allowed(p_org,p_unit,team,'read') then raise exception 'scale_access_denied' using errcode='42501';end if;
  if team is not null then
   if not exists(select 1 from private.scale_teams where id=team and organization_id=p_org and unit_id=p_unit and active) then raise exception 'scale_team_inactive' using errcode='22023';end if;
   return jsonb_build_object('roles',coalesce((select jsonb_agg(to_jsonb(r) order by name,id) from(select id,name,required_count from private.scale_roles where team_id=team and active)r),'[]'),
    'members',coalesce((select jsonb_agg(to_jsonb(m)) from(select m.id,p.full_name name,m.role_id from private.scale_members m join public.people p on p.id=m.person_id and p.organization_id=p_org and p.unit_id=p_unit and p.status='active' where m.team_id=team and m.active and (search='' or strpos(lower(p.full_name),lower(search))>0) order by p.full_name,m.id limit 20 offset (page-1)*20)m),'[]'),
    'membersTotal',(select count(*) from private.scale_members m join public.people p on p.id=m.person_id and p.organization_id=p_org and p.unit_id=p_unit and p.status='active' where m.team_id=team and m.active and (search='' or strpos(lower(p.full_name),lower(search))>0)), 'canAssign',private.scale_allowed(p_org,p_unit,team,'assign'));
  end if;
  return jsonb_build_object('timezone',zone,'canPlan',private.scale_allowed(p_org,p_unit,null,'manage'),
   'teams',coalesce((select jsonb_agg(to_jsonb(t)) from(select id,name,private.scale_allowed(p_org,p_unit,id,'manage') "canManage" from private.scale_teams where organization_id=p_org and unit_id=p_unit and active and private.scale_allowed(p_org,p_unit,id,'read') order by name,id limit 20 offset (page-1)*20)t),'[]'),
   'teamsTotal',(select count(*) from private.scale_teams where organization_id=p_org and unit_id=p_unit and active and private.scale_allowed(p_org,p_unit,id,'read')),
   'events',coalesce((select jsonb_agg(to_jsonb(e)) from(select e.id,e.title,e.starts_at,e.ends_at,e.location from private.church_app_events e where e.organization_id=p_org and e.unit_id=p_unit and e.status<>'cancelled' and private.scale_allowed(p_org,p_unit,null,'manage') and (search<>'' and strpos(lower(e.title),lower(search))>0) order by e.starts_at desc,e.id limit 20)e),'[]'),
   'people',coalesce((select jsonb_agg(to_jsonb(p)) from(select id,full_name from public.people where organization_id=p_org and unit_id=p_unit and status='active' and private.scale_allowed(p_org,p_unit,null,'manage') and length(search)>=2 and strpos(lower(full_name),lower(search))>0 order by full_name,id limit 20)p),'[]'));
 end if;
 if p_action='list' then
  first_day:=(p_data->>'from')::date;last_day:=(p_data->>'to')::date;
  if first_day is null or last_day is null or last_day<first_day or last_day-first_day>366 or state not in('all','draft','cancelled') then raise exception 'scale_period' using errcode='22023';end if;
  select count(*) into total from private.scale_services s where organization_id=p_org and unit_id=p_unit and starts_at>=first_day::timestamp at time zone zone and starts_at<(last_day+1)::timestamp at time zone zone and (state='all' or status=state) and (search='' or strpos(lower(s.title),lower(search))>0) and (team is null or exists(select 1 from private.scale_positions where service_id=s.id and team_id=team)) and private.scale_service_allowed(p_org,p_unit,s.id,'read');
  select coalesce(jsonb_agg(to_jsonb(x) order by starts_at,id),'[]') into items from(select s.*,
   (select count(*) from private.scale_positions where service_id=s.id) vacancies,
   (select count(*) from private.scale_positions where service_id=s.id and member_id is not null) assigned,
   private.scale_service_allowed(p_org,p_unit,s.id,'manage') "canManage"
   from private.scale_services s where organization_id=p_org and unit_id=p_unit and starts_at>=first_day::timestamp at time zone zone and starts_at<(last_day+1)::timestamp at time zone zone and (state='all' or status=state) and (search='' or strpos(lower(s.title),lower(search))>0) and (team is null or exists(select 1 from private.scale_positions where service_id=s.id and team_id=team)) and private.scale_service_allowed(p_org,p_unit,s.id,'read') order by starts_at,id limit 50 offset (page-1)*50)x;
  return jsonb_build_object('items',items,'total',total,'timezone',zone,'canPlan',private.scale_allowed(p_org,p_unit,null,'manage'));
 end if;
 if sid is not null then
  select * into row from private.scale_services where id=sid and organization_id=p_org and unit_id=p_unit;
  if not found or not private.scale_service_allowed(p_org,p_unit,sid,'read') then raise exception 'scale_access_denied' using errcode='42501';end if;
 end if;
 if p_action='detail' then
  if sid is null then raise exception 'scale_input' using errcode='22023';end if;
  return jsonb_build_object('service',to_jsonb(row),'canManage',private.scale_service_allowed(p_org,p_unit,sid,'manage'),
   'eventTitle',(select e.title from private.church_app_events e where id=row.event_id),
   'coordinatorName',(select full_name from public.people where id=row.coordinator_id),
   'positions',coalesce((select jsonb_agg(to_jsonb(x) order by "teamName","roleName",ordinal) from(select q.*,t.name "teamName",r.name "roleName",p.full_name "memberName" from private.scale_positions q join private.scale_teams t on t.id=q.team_id join private.scale_roles r on r.id=q.role_id left join private.scale_members m on m.id=q.member_id left join public.people p on p.id=m.person_id where service_id=sid)x),'[]'),
   'history',coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc,id) from(select h.id,h.action,h.created_at,coalesce(nullif(p.full_name,''),'Usuário da plataforma') actor_name from private.scale_service_history h left join public.profiles p on p.id=h.actor where service_id=sid order by created_at desc,id limit 50)x),'[]'));
 end if;
 if not private.scale_allowed(p_org,p_unit,null,'manage') then raise exception 'scale_access_denied' using errcode='42501';end if;
 if scope not in('current','following','all') or op not in('save','cancel','duplicate') then raise exception 'scale_input' using errcode='22023';end if;
 if sid is null then ids:='{}';versions:='[]';
 else
  select array_agg(id order by starts_at,id),jsonb_agg(jsonb_build_object('id',id,'version',version) order by starts_at,id) into ids,versions from private.scale_services where id=sid or (series_id=row.series_id and op<>'duplicate' and (scope='all' or(scope='following' and starts_at>=row.starts_at)));
  if exists(select 1 from unnest(ids)x where not private.scale_service_allowed(p_org,p_unit,x,'manage')) then raise exception 'scale_access_denied' using errcode='42501';end if;
 end if;
 if op='cancel' then
  if sid is null then raise exception 'scale_input' using errcode='22023';end if;
  select jsonb_agg(jsonb_build_object('startsLocal',starts_at at time zone timezone,'arrivalLocal',arrival_at at time zone timezone,'endsLocal',ends_at at time zone timezone) order by starts_at,id) into dates from private.scale_services where id=any(ids);
 else
  title:=btrim(p_data->>'title');loc:=coalesce(p_data->>'location','');notes:=coalesce(p_data->>'notes','');event:=nullif(p_data->>'event','')::uuid;coordinator:=nullif(p_data->>'coordinator','')::uuid;
  start_local:=(p_data->>'startsLocal')::timestamp;end_local:=(p_data->>'endsLocal')::timestamp;arrival_local:=(p_data->>'arrivalLocal')::timestamp;
  if title is null or length(title) not between 2 and 160 or length(loc)>300 or length(notes)>2000 or start_local is null or end_local is null or arrival_local is null or arrival_local>start_local or end_local<=start_local or end_local-arrival_local>interval '7 days' or start_local>now()+interval '2 years' then raise exception 'scale_dates' using errcode='22023';end if;
  if event is not null and not exists(select 1 from private.church_app_events where id=event and organization_id=p_org and unit_id=p_unit and status<>'cancelled') then raise exception 'scale_event_invalid' using errcode='22023';end if;
  if coordinator is not null and not exists(select 1 from public.people where id=coordinator and organization_id=p_org and unit_id=p_unit and status='active') then raise exception 'scale_person_invalid' using errcode='22023';end if;
  roster:=p_data->'positions';
  if jsonb_typeof(roster) is distinct from 'array' or jsonb_array_length(roster) not between 1 and 500 then raise exception 'scale_positions' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(roster)p group by p->>'role',p->>'ordinal' having count(*)>1) then raise exception 'scale_positions' using errcode='22023';end if;
  for pos in select * from jsonb_array_elements(roster) loop
   tid:=(pos->>'team')::uuid;role_id:=(pos->>'role')::uuid;ordinal:=(pos->>'ordinal')::integer;member:=nullif(pos->>'member','')::uuid;
   if tid is null or role_id is null or ordinal is null or ordinal not between 1 and 100 or not exists(select 1 from private.scale_roles r join private.scale_teams t on t.id=r.team_id where r.id=role_id and r.team_id=tid and r.organization_id=p_org and r.unit_id=p_unit and r.active and t.active) then raise exception 'scale_role_invalid' using errcode='22023';end if;
   if not private.scale_allowed(p_org,p_unit,tid,'manage') then raise exception 'scale_access_denied' using errcode='42501';end if;
   if member is not null and not exists(select 1 from private.scale_members m join public.people p on p.id=m.person_id and p.unit_id=p_unit and p.status='active' where m.id=member and m.team_id=tid and m.organization_id=p_org and m.unit_id=p_unit and m.active) then raise exception 'scale_person_invalid' using errcode='22023';end if;
   if member is not null and not private.scale_allowed(p_org,p_unit,tid,'assign') then
    if sid is null or op='duplicate' or exists(select 1 from unnest(ids)x where not exists(select 1 from private.scale_positions q where q.service_id=x and q.role_id=role_id and q.team_id=tid and q.ordinal=ordinal and q.member_id=member)) then raise exception 'scale_access_denied' using errcode='42501';end if;
   end if;
  end loop;
  if exists(select 1 from private.scale_positions q where q.service_id=any(ids) and q.member_id is not null and not private.scale_allowed(p_org,p_unit,q.team_id,'assign') and not exists(select 1 from jsonb_array_elements(roster)p where (p->>'team')::uuid=q.team_id and (p->>'role')::uuid=q.role_id and (p->>'ordinal')::integer=q.ordinal and nullif(p->>'member','')::uuid=q.member_id)) then raise exception 'scale_access_denied' using errcode='42501';end if;
  -- A person may occupy a slot once. Coexisting roles require stage 3 qualification rules.
  if exists(select 1 from jsonb_array_elements(roster)p join private.scale_members m on m.id=nullif(p->>'member','')::uuid group by m.person_id having count(*)>1) then raise exception 'scale_person_duplicate' using errcode='22023';end if;
  if sid is null or op='duplicate' then
   rule:=coalesce(p_data->>'repeat','none');n:=coalesce((p_data->>'count')::integer,1);
   if rule not in('none','daily','weekly','monthly') or n not between 1 and 120 or (rule='none' and n<>1) then raise exception 'scale_recurrence' using errcode='22023';end if;
   step:=case rule when 'daily' then interval '1 day' when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' else interval '0' end;
   for i in 0..n-1 loop
    next_start:=start_local+step*i;
    if next_start>now()+interval '2 years' then raise exception 'scale_recurrence' using errcode='22023';end if;
    dates:=dates||jsonb_build_array(jsonb_build_object('startsLocal',next_start,'arrivalLocal',next_start+(arrival_local-start_local),'endsLocal',next_start+(end_local-start_local)));
   end loop;
  else
   delta:=start_local-(row.starts_at at time zone row.timezone);
   for target in select * from private.scale_services where id=any(ids) order by starts_at,id loop
    next_start:=(target.starts_at at time zone target.timezone)+delta;
    if next_start>now()+interval '2 years' then raise exception 'scale_recurrence' using errcode='22023';end if;
    dates:=dates||jsonb_build_array(jsonb_build_object('id',target.id,'startsLocal',next_start,'arrivalLocal',next_start+(arrival_local-start_local),'endsLocal',next_start+(end_local-start_local)));
   end loop;
  end if;
 end if;
 if p_action='preview' then return jsonb_build_object('versions',versions,'dates',dates,'affected',coalesce(cardinality(ids),0),'token',md5(versions::text),'cancelled',(select count(*) from private.scale_services where id=any(ids) and status<>'draft'));end if;
 rid:=(p_data->>'request')::uuid;
 if rid is null then raise exception 'scale_input' using errcode='22023';end if;
 fingerprint:=md5(jsonb_build_object('org',p_org,'unit',p_unit,'action',p_action,'data',p_data)::text);
 select * into prior from private.scale_planning_requests where id=rid;
 if found then
  if prior.organization_id<>p_org or prior.unit_id<>p_unit or prior.actor<>auth.uid() or prior.fingerprint<>fingerprint then raise exception 'scale_version_conflict' using errcode='40001';end if;
  return prior.result;
 end if;
 if p_data->>'token' is distinct from md5(versions::text) then raise exception 'scale_version_conflict' using errcode='40001';end if;
 if p_action<>'duplicate' and exists(select 1 from private.scale_services where id=any(ids) and status<>'draft') then raise exception 'scale_locked' using errcode='22023';end if;
 if p_action='cancel' then
  foreach tid in array ids loop
   select to_jsonb(s) into before_data from private.scale_services s where id=tid;
   update private.scale_services set status='cancelled',version=version+1 where id=tid returning to_jsonb(scale_services.*) into after_data;
   insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,before_data,after_data) values(tid,p_org,p_unit,auth.uid(),'cancel',before_data,after_data);
  end loop;
  result:=jsonb_build_object('id',sid,'count',cardinality(ids));
 else
  -- New drafts/duplicates have fresh identities; prior invitations can never be copied.
  if sid is null or p_action='duplicate' then tid:=extensions.gen_random_uuid();else tid:=row.series_id;end if;
  result:=jsonb_build_object('count',jsonb_array_length(dates));
  for pos in select * from jsonb_array_elements(dates) loop
   if pos ? 'id' then sid:=(pos->>'id')::uuid;else sid:=extensions.gen_random_uuid();end if;
   select to_jsonb(s)||jsonb_build_object('positions',(select jsonb_agg(to_jsonb(q)) from private.scale_positions q where service_id=sid)) into before_data from private.scale_services s where id=sid;
   insert into private.scale_services(id,organization_id,unit_id,series_id,title,event_id,location,notes,coordinator_id,arrival_at,starts_at,ends_at,timezone,created_by)
   values(sid,p_org,p_unit,tid,title,event,loc,notes,coordinator,(pos->>'arrivalLocal')::timestamp at time zone zone,(pos->>'startsLocal')::timestamp at time zone zone,(pos->>'endsLocal')::timestamp at time zone zone,zone,auth.uid())
   on conflict(id) do update set title=excluded.title,event_id=excluded.event_id,location=excluded.location,notes=excluded.notes,coordinator_id=excluded.coordinator_id,arrival_at=excluded.arrival_at,starts_at=excluded.starts_at,ends_at=excluded.ends_at,timezone=excluded.timezone,version=scale_services.version+1;
   delete from private.scale_positions where service_id=sid;
   insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id)
   select sid,p_org,p_unit,(p->>'team')::uuid,(p->>'role')::uuid,(p->>'ordinal')::integer,nullif(p->>'member','')::uuid from jsonb_array_elements(roster)p;
   select to_jsonb(s)||jsonb_build_object('positions',roster) into after_data from private.scale_services s where id=sid;
   insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,before_data,after_data) values(sid,p_org,p_unit,auth.uid(),case when before_data is not null then 'edit' when p_action='duplicate' then 'duplicate' else 'create' end,before_data,after_data);
   if not result ? 'id' then result:=result||jsonb_build_object('id',sid);end if;
  end loop;
 end if;
 insert into private.scale_planning_requests(id,organization_id,unit_id,actor,fingerprint,result) values(rid,p_org,p_unit,auth.uid(),fingerprint,result);
 return result;
end$$;
revoke all on function private.scale_planning(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.scale_planning(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.scale_planning(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.scale_planning(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.scale_planning(uuid,uuid,text,jsonb),public.scale_planning(uuid,uuid,text,jsonb) to authenticated;
