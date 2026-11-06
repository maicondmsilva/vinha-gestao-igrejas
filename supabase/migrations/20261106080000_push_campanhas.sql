begin;
set local lock_timeout='5s';
-- Etapa 2: campanhas de push. Uma campanha tem título e texto reais, link para a tela certa, público
-- segmentado, agendamento e recorrência. Cada execução gera uma mensagem por aparelho; o envio roda a cada
-- minuto, em lotes, pelo servidor. Quem envia segue a mesma regra das publicações (private.publisher_unit).

create table private.push_campaigns(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 owner_unit uuid not null,
 title text not null check(length(btrim(title)) between 2 and 65),
 body text not null check(length(btrim(body)) between 2 and 240),
 link jsonb not null default '{"screen":"inbox"}' check(jsonb_typeof(link)='object' and octet_length(link::text)<=600),
 audience jsonb not null default '{}' check(jsonb_typeof(audience)='object' and octet_length(audience::text)<=8000),
 targets uuid[] not null check(cardinality(targets) between 1 and 200),
 source text not null default 'manual' check(source in('manual','live','birthday')),
 source_key text check(source_key is null or length(source_key) between 1 and 200),
 status text not null default 'draft' check(status in('draft','scheduled','sending','sent','cancelled')),
 send_at timestamptz,
 recurrence text not null default 'none' check(recurrence in('none','daily','weekly','monthly')),
 recurrence_until timestamptz,
 next_run_at timestamptz,
 runs integer not null default 0 check(runs>=0),
 request_id uuid,
 version integer not null default 1 check(version>0),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 check(status<>'scheduled' or next_run_at is not null),
 check(recurrence='none' or recurrence_until is null or recurrence_until>send_at),
 unique(organization_id,source,source_key),
 unique(created_by,request_id),
 foreign key(owner_unit,organization_id) references public.organization_units(id,organization_id)
);
create index push_campaigns_due on private.push_campaigns(next_run_at) where status='scheduled';
create index push_campaigns_org on private.push_campaigns(organization_id,created_at desc);
create index push_campaigns_creator on private.push_campaigns(created_by);
create index push_campaigns_unit on private.push_campaigns(owner_unit,organization_id);

create table private.push_runs(
 id uuid primary key default extensions.gen_random_uuid(),
 campaign_id uuid not null references private.push_campaigns(id) on delete cascade,
 scheduled_for timestamptz not null,
 recipients integer not null default 0,
 created_at timestamptz not null default clock_timestamp(),
 unique(campaign_id,scheduled_for)
);

create table private.push_messages(
 id uuid primary key default extensions.gen_random_uuid(),
 run_id uuid not null references private.push_runs(id) on delete cascade,
 device_id uuid not null references private.member_push_devices(id),
 user_id uuid not null references auth.users(id),
 state text not null default 'queued' check(state in('queued','sending','submitted','delivered','failed','uncertain','cancelled')),
 ticket text check(ticket is null or length(ticket)<200),
 error text check(error is null or length(error)<=80),
 attempts integer not null default 0 check(attempts between 0 and 5),
 opened_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(run_id,device_id)
);
create index push_messages_queue on private.push_messages(state,updated_at);
create index push_messages_device on private.push_messages(device_id);
create index push_messages_user on private.push_messages(user_id);

alter table private.push_campaigns enable row level security;
alter table private.push_runs enable row level security;
alter table private.push_messages enable row level security;
revoke all on private.push_campaigns,private.push_runs,private.push_messages from public,anon,authenticated,service_role;

-- Audience: keys and types are closed so a malformed filter never widens the public.
create function private.push_audience_check(p jsonb) returns void language plpgsql immutable set search_path='' as $$
declare k text;
begin
 if jsonb_typeof(p) is distinct from 'object' then raise exception 'invalid_push_audience' using errcode='22023';end if;
 for k in select jsonb_object_keys(p) loop
  if k not in('roles','cells','groups','ageMin','ageMax','gender','journey','tags','baptized','event','birthdayToday') then raise exception 'invalid_push_audience' using errcode='22023';end if;
 end loop;
 if p ? 'roles' and (jsonb_typeof(p->'roles')<>'array' or jsonb_array_length(p->'roles') not between 1 and 8
  or exists(select 1 from jsonb_array_elements_text(p->'roles') r where r not in('owner','pastor','admin','secretary','finance','leader','member','viewer'))) then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if exists(select 1 from unnest(array['cells','groups']) key where p ? key and (jsonb_typeof(p->key)<>'array' or jsonb_array_length(p->key) not between 1 and 100
  or exists(select 1 from jsonb_array_elements_text(p->key) v where v !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if exists(select 1 from unnest(array['journey','tags']) key where p ? key and (jsonb_typeof(p->key)<>'array' or jsonb_array_length(p->key) not between 1 and 30
  or exists(select 1 from jsonb_array_elements(p->key) v where jsonb_typeof(v)<>'string' or length(v#>>'{}') not between 1 and 80))) then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if exists(select 1 from unnest(array['ageMin','ageMax']) key where p ? key and (jsonb_typeof(p->key)<>'number' or (p->>key)::numeric not between 0 and 120 or (p->>key)::numeric<>trunc((p->>key)::numeric))) then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if p ? 'ageMin' and p ? 'ageMax' and (p->>'ageMin')::int>(p->>'ageMax')::int then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if p ? 'gender' and (jsonb_typeof(p->'gender')<>'string' or length(p->>'gender') not between 1 and 30) then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if exists(select 1 from unnest(array['baptized','birthdayToday']) key where p ? key and jsonb_typeof(p->key)<>'boolean') then raise exception 'invalid_push_audience' using errcode='22023';end if;
 if p ? 'event' and (jsonb_typeof(p->'event')<>'string' or p->>'event' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'invalid_push_audience' using errcode='22023';end if;
end $$;
revoke all on function private.push_audience_check(jsonb) from public,anon,authenticated,service_role;

-- Devices that would receive a campaign right now. Person filters need a linked, living church record.
create function private.push_audience(p_org uuid,p_targets uuid[],p_audience jsonb) returns table(device_id uuid,user_id uuid) language sql stable security definer set search_path='' as $$
 select d.id,d.user_id from private.member_push_devices d
 join private.member_push_apps a on a.organization_id=d.organization_id and a.enabled
 join public.organization_memberships m on m.user_id=d.user_id and m.organization_id=d.organization_id and m.status='active'
 join public.organizations o on o.id=d.organization_id and o.status in('active','trial')
 join public.organization_units unit on unit.id=d.unit_id and unit.organization_id=d.organization_id and unit.status='active'
 join auth.users u on u.id=d.user_id and u.deleted_at is null and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<now())
 left join lateral(select p.* from public.people p where p.organization_id=d.organization_id and p.auth_user_id=d.user_id order by (p.status='active') desc,p.updated_at desc limit 1) p on true
 where d.organization_id=p_org and d.enabled and d.unit_id=any(p_targets) and d.updated_at>now()-interval '60 days'
  and exists(select 1 from auth.sessions s where s.id=d.session_id and s.user_id=u.id and (s.not_after is null or s.not_after>now()))
  and coalesce(p.status,'active')<>'deceased'
  and (not p_audience ?| array['cells','groups','ageMin','ageMax','gender','journey','tags','baptized','birthdayToday'] or p.status in('active','pending'))
  and (not p_audience ? 'roles' or m.role::text in(select jsonb_array_elements_text(p_audience->'roles')))
  and (not p_audience ? 'cells' or exists(select 1 from public.church_cell_participants c where c.person_id=p.id and c.organization_id=p_org and c.status='active' and c.cell_id::text in(select jsonb_array_elements_text(p_audience->'cells'))))
  and (not p_audience ? 'groups' or exists(select 1 from private.community_participation g where g.user_id=d.user_id and g.organization_id=p_org and g.status='approved' and g.group_id::text in(select jsonb_array_elements_text(p_audience->'groups'))))
  and (not p_audience ? 'ageMin' or p.birth_date<=(current_date-make_interval(years=>(p_audience->>'ageMin')::int)))
  and (not p_audience ? 'ageMax' or p.birth_date>(current_date-make_interval(years=>(p_audience->>'ageMax')::int+1)))
  and (not p_audience ? 'gender' or p.gender=p_audience->>'gender')
  and (not p_audience ? 'journey' or p.journey_status in(select jsonb_array_elements_text(p_audience->'journey')))
  and (not p_audience ? 'tags' or p.tags && array(select jsonb_array_elements_text(p_audience->'tags')))
  and (not p_audience ? 'baptized' or coalesce(p.baptized,false)=(p_audience->>'baptized')::boolean)
  and (not coalesce((p_audience->>'birthdayToday')::boolean,false) or to_char(p.birth_date,'MM-DD')=to_char((now() at time zone 'America/Sao_Paulo')::date,'MM-DD'))
  and (not p_audience ? 'event' or exists(select 1 from private.church_app_registrations r where r.event_id=(p_audience->>'event')::uuid and r.organization_id=p_org and r.user_id=d.user_id and r.status='confirmed')
   or exists(select 1 from private.event_ticket_orders t where t.event_id=(p_audience->>'event')::uuid and t.organization_id=p_org and t.user_id=d.user_id and t.state in('confirmed','reserved')));
$$;
revoke all on function private.push_audience(uuid,uuid[],jsonb) from public,anon,authenticated,service_role;

create function private.push_link_check(p jsonb) returns void language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(p) is distinct from 'object' or p-array['screen','id']<>'{}'::jsonb
  or p->>'screen' not in('inbox','agenda','event','notice','media','live','giving','services')
  or (p ? 'id' and coalesce(p->>'id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (p->>'screen' in('event','notice','media','live') and not p ? 'id') then raise exception 'invalid_push_link' using errcode='22023';end if;
end $$;
revoke all on function private.push_link_check(jsonb) from public,anon,authenticated,service_role;

create function private.push_next(p_from timestamptz,p_rule text) returns timestamptz language sql immutable set search_path='' as $$
 select case p_rule when 'daily' then p_from+interval '1 day' when 'weekly' then p_from+interval '7 days' when 'monthly' then p_from+interval '1 month' end;
$$;
revoke all on function private.push_next(timestamptz,text) from public,anon,authenticated,service_role;

create function private.push_campaign_json(c private.push_campaigns) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'unit',c.owner_unit,'title',c.title,'body',c.body,'link',c.link,'audience',c.audience,'targets',to_jsonb(c.targets),
  'source',c.source,'status',c.status,'sendAt',c.send_at,'recurrence',c.recurrence,'recurrenceUntil',c.recurrence_until,'nextRunAt',c.next_run_at,
  'runs',c.runs,'version',c.version,'createdAt',c.created_at,'updatedAt',c.updated_at,
  'author',(select coalesce(nullif(u.raw_user_meta_data->>'full_name',''),'Equipe') from auth.users u where u.id=c.created_by),
  'stats',(select jsonb_build_object('recipients',count(*),'delivered',count(*) filter(where m.state in('submitted','delivered')),
   'failed',count(*) filter(where m.state in('failed','uncertain','cancelled')),'pending',count(*) filter(where m.state in('queued','sending')),
   'opened',count(*) filter(where m.opened_at is not null))
   from private.push_runs r join private.push_messages m on m.run_id=r.id where r.campaign_id=c.id));
$$;
revoke all on function private.push_campaign_json(private.push_campaigns) from public,anon,authenticated,service_role;

-- Panel API. Every target church must be one the sender may publish to; drafts and schedules stay editable.
create function private.push_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare c private.push_campaigns;dest uuid[];aud jsonb;lnk jsonb;at timestamptz;rule text;until_at timestamptz;mode text;page_no int;page_size int;total int;
begin
 if auth.uid() is null then raise exception 'push_denied' using errcode='42501';end if;
 if not private.publisher_unit(p_org,p_unit) then raise exception 'push_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>12000 then raise exception 'invalid_push' using errcode='22023';end if;
 if p_action='list' then
  if p_data-array['page','size','status']<>'{}'::jsonb then raise exception 'invalid_push' using errcode='22023';end if;
  page_no:=greatest(1,least(coalesce((p_data->>'page')::int,1),500));page_size:=greatest(5,least(coalesce((p_data->>'size')::int,20),50));
  select count(*) into total from private.push_campaigns x where x.organization_id=p_org and private.publisher_unit(p_org,x.owner_unit)
   and (coalesce(p_data->>'status','')='' or x.status=p_data->>'status');
  return jsonb_build_object('total',total,'page',page_no,'size',page_size,'items',coalesce((select jsonb_agg(private.push_campaign_json(x) order by x.created_at desc)
   from(select * from private.push_campaigns x where x.organization_id=p_org and private.publisher_unit(p_org,x.owner_unit)
   and (coalesce(p_data->>'status','')='' or x.status=p_data->>'status') order by x.created_at desc offset (page_no-1)*page_size limit page_size)x),'[]'),
   'units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name) order by u.name) from public.organization_units u where u.organization_id=p_org and private.publisher_unit(p_org,u.id)),'[]'));
 end if;
 if p_action='options' then
  -- Choices for the audience builder, limited to churches this sender may publish to.
  select coalesce(array_agg(u.id),'{}') into dest from public.organization_units u where u.organization_id=p_org and private.publisher_unit(p_org,u.id);
  return jsonb_build_object(
   'units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name) order by u.name) from public.organization_units u where u.id=any(dest)),'[]'),
   'cells',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'unit',x.unit_id) order by x.name) from(select id,name,unit_id from public.church_cells where organization_id=p_org and unit_id=any(dest) and status='active' order by name limit 300)x),'[]'),
   'groups',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'kind',x.kind,'unit',x.unit_id) order by x.name) from(select id,name,kind,unit_id from private.community_groups where organization_id=p_org and unit_id=any(dest) and active order by name limit 300)x),'[]'),
   'events',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'title',x.title,'startsAt',x.starts_at) order by x.starts_at) from(select id,title,starts_at from private.church_app_events where organization_id=p_org and unit_id=any(dest) and status='published' and ends_at>now()-interval '30 days' order by starts_at limit 100)x),'[]'),
   'journey',coalesce((select jsonb_agg(v order by v) from(select distinct journey_status v from public.people where organization_id=p_org and unit_id=any(dest) and journey_status is not null and length(journey_status) between 1 and 80 limit 50)x),'[]'),
   'tags',coalesce((select jsonb_agg(v order by v) from(select distinct t v from public.people,unnest(tags) t where organization_id=p_org and unit_id=any(dest) and length(t) between 1 and 80 limit 100)x),'[]'),
   'genders',coalesce((select jsonb_agg(v order by v) from(select distinct gender v from public.people where organization_id=p_org and unit_id=any(dest) and gender is not null and length(gender) between 1 and 30 limit 10)x),'[]'));
 end if;
 if p_action='detail' then
  select * into c from private.push_campaigns where id=p_id and organization_id=p_org;
  if not found or not private.publisher_unit(p_org,c.owner_unit) then raise exception 'push_not_found' using errcode='42501';end if;
  return private.push_campaign_json(c);
 end if;
 if p_action in('preview','create','edit') then
  if p_data-array['title','body','link','audience','targets','mode','sendAt','recurrence','recurrenceUntil','request']<>'{}'::jsonb then raise exception 'invalid_push' using errcode='22023';end if;
  aud:=coalesce(p_data->'audience','{}');perform private.push_audience_check(aud);
  if jsonb_typeof(p_data->'targets')<>'array' or jsonb_array_length(p_data->'targets') not between 1 and 200
   or exists(select 1 from jsonb_array_elements_text(p_data->'targets') t where t !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'invalid_push' using errcode='22023';end if;
  select array_agg(distinct t::uuid order by t::uuid) into dest from jsonb_array_elements_text(p_data->'targets') t;
  if exists(select 1 from unnest(dest) t where not private.publisher_unit(p_org,t)) then raise exception 'push_target_denied' using errcode='42501';end if;
  if aud ? 'event' and not exists(select 1 from private.church_app_events e where e.id=(aud->>'event')::uuid and e.organization_id=p_org) then raise exception 'invalid_push' using errcode='22023';end if;
  if p_action='preview' then
   return jsonb_build_object('devices',(select count(*) from private.push_audience(p_org,dest,aud)),'people',(select count(distinct user_id) from private.push_audience(p_org,dest,aud)));
  end if;
  lnk:=coalesce(p_data->'link','{"screen":"inbox"}');perform private.push_link_check(lnk);
  mode:=coalesce(p_data->>'mode','draft');rule:=coalesce(p_data->>'recurrence','none');
  if mode not in('draft','now','schedule') or rule not in('none','daily','weekly','monthly') then raise exception 'invalid_push' using errcode='22023';end if;
  at:=case mode when 'now' then clock_timestamp() when 'schedule' then (p_data->>'sendAt')::timestamptz else nullif(p_data->>'sendAt','')::timestamptz end;
  if mode='schedule' and (at is null or at<clock_timestamp()-interval '1 minute' or at>clock_timestamp()+interval '366 days') then raise exception 'invalid_push_schedule' using errcode='22023';end if;
  until_at:=nullif(p_data->>'recurrenceUntil','')::timestamptz;
  if rule='none' then until_at:=null;end if;
  if until_at is not null and (at is null or until_at<=at or until_at>at+interval '366 days') then raise exception 'invalid_push_schedule' using errcode='22023';end if;
  if p_action='create' then
   if coalesce(p_data->>'request','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'invalid_push' using errcode='22023';end if;
   select * into c from private.push_campaigns where created_by=auth.uid() and request_id=(p_data->>'request')::uuid;
   if found then return jsonb_build_object('ok',true,'repeated',true,'campaign',private.push_campaign_json(c));end if;
   insert into private.push_campaigns(organization_id,owner_unit,title,body,link,audience,targets,status,send_at,recurrence,recurrence_until,next_run_at,request_id,created_by)
    values(p_org,p_unit,btrim(p_data->>'title'),btrim(p_data->>'body'),lnk,aud,dest,case when mode='draft' then 'draft' else 'scheduled' end,at,rule,until_at,
     case when mode='draft' then null else at end,(p_data->>'request')::uuid,auth.uid()) returning * into c;
  else
   select * into c from private.push_campaigns where id=p_id and organization_id=p_org for update;
   if not found or not private.publisher_unit(p_org,c.owner_unit) then raise exception 'push_not_found' using errcode='42501';end if;
   if c.version<>p_version then raise exception 'push_conflict' using errcode='40001';end if;
   if c.status not in('draft','scheduled') or c.runs>0 then raise exception 'push_locked' using errcode='40001';end if;
   update private.push_campaigns set title=btrim(p_data->>'title'),body=btrim(p_data->>'body'),link=lnk,audience=aud,targets=dest,
    status=case when mode='draft' then 'draft' else 'scheduled' end,send_at=at,recurrence=rule,recurrence_until=until_at,
    next_run_at=case when mode='draft' then null else at end,version=version+1,updated_at=clock_timestamp() where id=c.id returning * into c;
  end if;
  return jsonb_build_object('ok',true,'campaign',private.push_campaign_json(c));
 end if;
 if p_action='cancel' then
  select * into c from private.push_campaigns where id=p_id and organization_id=p_org for update;
  if not found or not private.publisher_unit(p_org,c.owner_unit) then raise exception 'push_not_found' using errcode='42501';end if;
  if c.version<>p_version then raise exception 'push_conflict' using errcode='40001';end if;
  if c.status in('sent','cancelled') then raise exception 'push_locked' using errcode='40001';end if;
  update private.push_messages m set state='cancelled',updated_at=clock_timestamp() from private.push_runs r where r.id=m.run_id and r.campaign_id=c.id and m.state='queued';
  update private.push_campaigns set status='cancelled',next_run_at=null,version=version+1,updated_at=clock_timestamp() where id=c.id returning * into c;
  return jsonb_build_object('ok',true,'campaign',private.push_campaign_json(c));
 end if;
 raise exception 'invalid_push' using errcode='22023';
end $$;
revoke all on function private.push_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,authenticated,service_role;
create function public.push_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.push_admin(p_org,p_unit,p_action,p_id,p_version,p_data)$$;
revoke all on function public.push_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon;
grant execute on function public.push_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;

-- Server worker: materialize due runs, hand out batches, record provider results.
create function private.push_engine(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare c private.push_campaigns;run_id uuid;n int;made int:=0;items jsonb;x jsonb;lim int;dest uuid[];oldsub text:=current_setting('request.jwt.claim.sub',true);
begin
 if p_action='materialize' then
  for c in select * from private.push_campaigns where status='scheduled' and next_run_at<=clock_timestamp() order by next_run_at limit 20 for update skip locked loop
   -- The sender's permission is checked again at send time; churches they lost access to are dropped.
   run_id:=null;
   perform set_config('request.jwt.claim.sub',coalesce(c.created_by::text,''),true);
   if c.source='manual' then
    select coalesce(array_agg(t),'{}') into dest from unnest(c.targets) t where private.publisher_unit(c.organization_id,t);
   else dest:=c.targets;end if;
   perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);
   if cardinality(dest)=0 then
    update private.push_campaigns set status='cancelled',next_run_at=null,updated_at=clock_timestamp() where id=c.id;continue;
   end if;
   insert into private.push_runs(campaign_id,scheduled_for) values(c.id,c.next_run_at) on conflict do nothing returning id into run_id;
   if run_id is not null then
    insert into private.push_messages(run_id,device_id,user_id) select run_id,a.device_id,a.user_id from private.push_audience(c.organization_id,dest,c.audience) a on conflict do nothing;
    get diagnostics n=row_count;update private.push_runs set recipients=n where id=run_id;made:=made+1;
   end if;
   update private.push_campaigns set runs=runs+1,updated_at=clock_timestamp(),
    next_run_at=case when recurrence='none' then null when recurrence_until is not null and private.push_next(next_run_at,recurrence)>recurrence_until then null
     else greatest(private.push_next(next_run_at,recurrence),clock_timestamp()) end,
    status=case when recurrence='none' or (recurrence_until is not null and private.push_next(next_run_at,recurrence)>recurrence_until) then 'sending' else 'scheduled' end
   where id=c.id;
  end loop;
  -- A one-off or finished campaign is "sent" once nothing of it is still waiting.
  update private.push_campaigns p set status='sent',updated_at=clock_timestamp() where p.status='sending'
   and not exists(select 1 from private.push_runs r join private.push_messages m on m.run_id=r.id where r.campaign_id=p.id and m.state in('queued','sending'));
  return jsonb_build_object('runs',made);
 elsif p_action='claim' then
  lim:=greatest(1,least(coalesce((p_data->>'limit')::int,100),500));
  update private.push_messages set state='uncertain',updated_at=clock_timestamp() where state='sending' and updated_at<clock_timestamp()-interval '10 minutes';
  with picked as(
   select m.id from private.push_messages m join private.member_push_devices d on d.id=m.device_id
   where m.state='queued' and d.enabled order by m.created_at limit lim for update of m skip locked),
  upd as(update private.push_messages m set state='sending',attempts=m.attempts+1,updated_at=clock_timestamp() from picked where m.id=picked.id returning m.*)
  select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'token',d.token,'project',a.project_id,'title',c.title,'body',c.body,
    'data',c.link||jsonb_build_object('campaign',c.id,'message',u.id)) order by a.project_id),'[]') into items
  from upd u join private.member_push_devices d on d.id=u.device_id join private.push_runs r on r.id=u.run_id
  join private.push_campaigns c on c.id=r.campaign_id join private.member_push_apps a on a.organization_id=d.organization_id;
  -- Messages whose device lost its app registration are closed instead of looping.
  update private.push_messages m set state='cancelled',updated_at=clock_timestamp() from private.member_push_devices d
   where d.id=m.device_id and m.state='queued' and not d.enabled;
  return jsonb_build_object('items',items);
 elsif p_action='settle' then
  if jsonb_typeof(p_data->'items')<>'array' or jsonb_array_length(p_data->'items')>500 then raise exception 'invalid_push_engine' using errcode='22023';end if;
  for x in select * from jsonb_array_elements(p_data->'items') loop
   if x->>'state' not in('submitted','delivered','failed','uncertain','queued') or coalesce(x->>'id','') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_push_engine' using errcode='22023';end if;
   update private.push_messages set state=case when x->>'state'='queued' and attempts>=5 then 'failed' else x->>'state' end,
    ticket=coalesce(left(x->>'ticket',199),ticket),error=left(x->>'error',80),updated_at=clock_timestamp()
    where id=(x->>'id')::uuid and state in('sending','submitted');
   if x->>'error'='DeviceNotRegistered' then
    update private.member_push_devices d set enabled=false,updated_at=clock_timestamp() from private.push_messages m where m.id=(x->>'id')::uuid and d.id=m.device_id;
   end if;
  end loop;
  return jsonb_build_object('ok',true);
 elsif p_action='receipts' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'ticket',m.ticket)) from(select id,ticket from private.push_messages
   where state='submitted' and ticket is not null and updated_at<clock_timestamp()-interval '15 minutes' and updated_at>clock_timestamp()-interval '1 day' order by updated_at limit 1000)m),'[]'));
 end if;
 raise exception 'invalid_push_engine' using errcode='22023';
end $$;
revoke all on function private.push_engine(text,jsonb) from public,anon,authenticated,service_role;
create function public.push_engine(p_action text,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.push_engine(p_action,p_data)$$;
revoke all on function public.push_engine(text,jsonb) from public,anon,authenticated;
grant execute on function public.push_engine(text,jsonb) to service_role;

-- The member's app reports that a notification was opened (metric only; never a permission).
create function public.push_opened(p_message uuid) returns jsonb language sql security definer set search_path='' as $$
 with u as(update private.push_messages set opened_at=clock_timestamp() where id=p_message and user_id=auth.uid() and opened_at is null returning id)
 select jsonb_build_object('ok',true);
$$;
revoke all on function public.push_opened(uuid) from public,anon;
grant execute on function public.push_opened(uuid) to authenticated;

-- Every minute the database asks the app server to process the queue. The shared secret lives in Vault;
-- without it (local, CI, before configuration) the tick does nothing.
create extension if not exists pg_net with schema extensions;
create function private.push_tick() returns void language plpgsql security definer set search_path='' as $$
declare secret text;
begin
 select decrypted_secret into secret from vault.decrypted_secrets where name='vinha_cron_secret';
 if secret is null or length(secret)<32 then return;end if;
 perform net.http_post(url:='https://app.vinhaigrejas.com.br/api/push/run',
  headers:=jsonb_build_object('Authorization','Bearer '||secret,'Content-Type','application/json'),
  body:='{}'::jsonb,timeout_milliseconds:=55000);
end $$;
revoke all on function private.push_tick() from public,anon,authenticated,service_role;
select cron.schedule('vinha-push-every-minute','* * * * *','select private.push_tick();');
notify pgrst,'reload schema';
commit;
