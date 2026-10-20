-- Internal records are reachable only through scoped, validated RPCs.
create table private.cell_supervisor_grants (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,network_id uuid not null,
 person_id uuid not null,user_id uuid not null references auth.users(id) on delete restrict,
 capability text not null check(capability in('read','followup','report')),status text not null check(status in('active','revoked')),
 version integer not null default 1,created_by uuid not null references auth.users(id) on delete restrict,updated_at timestamptz not null default now(),
 foreign key(network_id,organization_id,unit_id) references public.church_cell_networks(id,organization_id,unit_id) on delete restrict,
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete restrict,
 unique(network_id,user_id)
);
create index cell_supervision_scope_idx on private.cell_supervisor_grants(organization_id,unit_id,user_id,status);
create index cell_supervision_network_idx on private.cell_supervisor_grants(network_id,organization_id,unit_id);
create index cell_supervision_person_idx on private.cell_supervisor_grants(person_id,organization_id);
create index cell_supervision_user_idx on private.cell_supervisor_grants(user_id);
create index cell_supervision_actor_idx on private.cell_supervisor_grants(created_by);
create table private.cell_referrals (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,cell_id uuid not null,person_id uuid,person_name text not null check(length(btrim(person_name)) between 2 and 200),
 status text not null check(status in('pending','accepted','rejected')),version integer not null default 1,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete restrict
);
create index cell_referrals_scope_idx on private.cell_referrals(organization_id,unit_id,id);
create index cell_referrals_cell_idx on private.cell_referrals(cell_id,organization_id,unit_id);
create index cell_referrals_person_idx on private.cell_referrals(person_id,organization_id);
create index cell_referrals_actor_idx on private.cell_referrals(created_by);
create unique index cell_referrals_pending_idx on private.cell_referrals(cell_id,person_id) where status='pending' and person_id is not null;
create table private.cell_study_materials (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,network_id uuid,
 title text not null check(length(btrim(title)) between 2 and 160),body text not null check(length(body)<=16000),url text not null default '' check(length(url)<=2000 and(url='' or url ~ '^https://[^[:space:]]+$')),
 status text not null check(status in('draft','published','archived')),version integer not null default 1,
 created_by uuid not null references auth.users(id) on delete restrict,updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id) on delete restrict,
 foreign key(network_id,organization_id,unit_id) references public.church_cell_networks(id,organization_id,unit_id) on delete restrict
);
create index cell_materials_scope_idx on private.cell_study_materials(organization_id,unit_id,id);
create index cell_materials_unit_idx on private.cell_study_materials(unit_id,organization_id);
create index cell_materials_network_idx on private.cell_study_materials(network_id,organization_id,unit_id);
create index cell_materials_actor_idx on private.cell_study_materials(created_by);
create table private.cell_report_notifications (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,unit_id uuid not null,cell_id uuid not null,meeting_id uuid not null,
 recipient_id uuid not null references auth.users(id) on delete restrict,created_by uuid references auth.users(id) on delete restrict,
 source text not null default 'manual' check(source in('manual','scheduled')),check((source='scheduled')=(created_by is null)),
 created_at timestamptz not null default now(),read_at timestamptz,
 foreign key(meeting_id,cell_id,organization_id,unit_id) references public.church_cell_meetings(id,cell_id,organization_id,unit_id) on delete restrict,
 unique(meeting_id,recipient_id)
);
create index cell_report_notices_scope_idx on private.cell_report_notifications(organization_id,unit_id,recipient_id,id);
create index cell_report_notices_meeting_idx on private.cell_report_notifications(meeting_id,cell_id,organization_id,unit_id);
create index cell_report_notices_recipient_idx on private.cell_report_notifications(recipient_id);
create index cell_report_notices_actor_idx on private.cell_report_notifications(created_by);
alter table private.cell_supervisor_grants enable row level security;
alter table private.cell_referrals enable row level security;
alter table private.cell_study_materials enable row level security;
alter table private.cell_report_notifications enable row level security;
revoke all on private.cell_supervisor_grants,private.cell_referrals,private.cell_study_materials,private.cell_report_notifications from public,anon,authenticated,service_role;
create policy internal_only on private.cell_supervisor_grants using(false);
create policy internal_only on private.cell_referrals using(false);
create policy internal_only on private.cell_study_materials using(false);
create policy internal_only on private.cell_report_notifications using(false);
create table private.cell_report_scan_checkpoint(id boolean primary key default true check(id),after_id uuid);
alter table private.cell_report_scan_checkpoint enable row level security;
create policy internal_only on private.cell_report_scan_checkpoint using(false);
revoke all on private.cell_report_scan_checkpoint from public,anon,authenticated,service_role;

create function private.cell_plus_unit_read(p_org uuid,p_unit uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_memberships m where m.organization_id=p_org and m.user_id=p_actor and m.status='active' and(m.role in('owner','admin','pastor') or exists(
 with recursive ancestors(id,parent_id,seen) as(select id,parent_unit_id,array[id] from public.organization_units where id=p_unit and organization_id=p_org
 union all select u.id,u.parent_unit_id,a.seen||u.id from ancestors a join public.organization_units u on u.id=a.parent_id and u.organization_id=p_org where not u.id=any(a.seen) and cardinality(a.seen)<32)
 select 1 from public.membership_unit_access g join ancestors a on a.id=g.unit_id where g.membership_id=m.id and(g.unit_id=p_unit or g.include_children))))
$$;
revoke all on function private.cell_plus_unit_read(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function private.cell_plus_active(p_org uuid,p_unit uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select p_actor is not null and exists(select 1 from public.organization_memberships where organization_id=p_org and user_id=p_actor and status='active')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'))
 and private.cell_plus_unit_read(p_org,p_unit,p_actor) and private.target_unit_module_enabled(p_org,p_unit,'cells') and private.target_unit_module_enabled(p_org,p_unit,'people')
$$;
revoke all on function private.cell_plus_active(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function private.cell_plus_network(p_org uuid,p_unit uuid,p_network uuid,p_actor uuid,p_capability text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_plus_active(p_org,p_unit,p_actor) and exists(
 with recursive ancestors(id,seen) as (
 select id,array[id] from public.church_cell_networks where id=p_network and organization_id=p_org and unit_id=p_unit and status='active'
 union all select e.parent_id,a.seen||e.parent_id from ancestors a join public.church_cell_network_parents e on e.network_id=a.id
 join public.church_cell_networks n on n.id=e.parent_id and n.organization_id=p_org and n.unit_id=p_unit and n.status='active'
 where not e.parent_id=any(a.seen) and cardinality(a.seen)<32)
 select 1 from ancestors a join private.cell_supervisor_grants g on g.network_id=a.id
 join public.people p on p.id=g.person_id and p.organization_id=g.organization_id and p.unit_id=g.unit_id and p.auth_user_id=g.user_id and p.status='active'
 where g.organization_id=p_org and g.unit_id=p_unit and g.user_id=p_actor and g.status='active'
 and(p_capability='read' or p_capability='followup' and g.capability in('followup','report') or p_capability='report' and g.capability='report'))
$$;
revoke all on function private.cell_plus_network(uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
create function private.cell_plus_cell(p_org uuid,p_unit uuid,p_cell uuid,p_actor uuid,p_capability text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.church_cells c left join public.church_cell_network_links l on l.cell_id=c.id
 where c.id=p_cell and c.organization_id=p_org and c.unit_id=p_unit and private.cell_plus_active(p_org,p_unit,p_actor)
 and(private.cell_flow_manager(p_org,p_unit,p_actor) or c.status='active' and private.cell_plus_network(p_org,p_unit,l.network_id,p_actor,p_capability)))
$$;
revoke all on function private.cell_plus_cell(uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

create function private.cell_plus_read(p_org uuid,p_unit uuid,p_kind text,p_network uuid,p_after uuid,p_from date,p_to date,p_cell uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid=auth.uid();manager boolean;governor boolean;items jsonb;next_id uuid;summary jsonb='{}';roster jsonb='[]';cells jsonb;networks jsonb;
begin
 if not private.cell_plus_active(p_org,p_unit,actor) or not private.can_access_unit(p_org,p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
 manager=private.cell_flow_manager(p_org,p_unit,actor);
 governor=manager and private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]);
 if not manager and not exists(select 1 from private.cell_supervisor_grants g where g.organization_id=p_org and g.unit_id=p_unit and private.cell_plus_network(p_org,p_unit,g.network_id,actor)) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_kind is null or p_kind not in('referrals','materials','reports','pending','supervisors','roster') or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'invalid_cell_plus' using errcode='22023';end if;
 if p_network is not null and not exists(select 1 from public.church_cell_networks n where n.id=p_network and n.organization_id=p_org and n.unit_id=p_unit and(manager or private.cell_plus_network(p_org,p_unit,n.id,actor))) then raise exception 'cell_access_denied' using errcode='42501';end if;
 -- Options and totals cover the complete authorized scope, not the current result page.
 with recursive branch(id,seen) as(select id,array[id] from public.church_cell_networks where id=p_network and organization_id=p_org and unit_id=p_unit
 union all select e.network_id,b.seen||e.network_id from branch b join public.church_cell_network_parents e on e.parent_id=b.id where cardinality(b.seen)<32 and not e.network_id=any(b.seen))
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'status',c.status) order by c.name,c.id),'[]') into cells from public.church_cells c
 left join public.church_cell_network_links l on l.cell_id=c.id
 where c.organization_id=p_org and c.unit_id=p_unit and private.cell_plus_cell(p_org,p_unit,c.id,actor)
 and(p_network is null or l.network_id in(select id from branch));
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'status',status) order by name,id),'[]') into networks from public.church_cell_networks n where organization_id=p_org and unit_id=p_unit and(manager or private.cell_plus_network(p_org,p_unit,n.id,actor));
 if jsonb_array_length(cells)>2000 or jsonb_array_length(networks)>2000 then raise exception 'cell_scope_too_large' using errcode='54000';end if;
 if p_kind='referrals' then
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from(select id,cell_id,person_id,person_name,status,version from private.cell_referrals where organization_id=p_org and unit_id=p_unit and cell_id in(select (x->>'id')::uuid from jsonb_array_elements(cells)x) and(p_after is null or id>p_after) order by id limit 101)r;
 elsif p_kind='materials' then
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from(select id,network_id,title,body,url,status,version from private.cell_study_materials m where organization_id=p_org and unit_id=p_unit and(manager or status='published' and(network_id is null or private.cell_plus_network(p_org,p_unit,network_id,actor))) and(p_network is null or network_id is null or network_id in(select (x->>'id')::uuid from jsonb_array_elements(networks)x where x->>'id'=p_network::text)) and(p_after is null or id>p_after) order by id limit 101)r;
 elsif p_kind='supervisors' then
 if not manager then raise exception 'cell_access_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from(select g.id,g.network_id,g.person_id,p.full_name as person_name,g.capability,g.status,g.version from private.cell_supervisor_grants g join public.people p on p.id=g.person_id where g.organization_id=p_org and g.unit_id=p_unit and(p_network is null or g.network_id=p_network) and(p_after is null or g.id>p_after) order by g.id limit 101)r;
 elsif p_kind='reports' then
 select jsonb_build_object('groups',jsonb_array_length(cells),'participants',(select count(distinct m.person_id) from public.church_cell_participants m where m.cell_id in(select (x->>'id')::uuid from jsonb_array_elements(cells)x) and m.status='active'),
 'meetings',count(distinct m.id),'expected',count(a.participant_id),'present',count(a.participant_id) filter(where a.present)) into summary
 from public.church_cell_meetings m left join public.church_cell_attendance a on a.meeting_id=m.id
 where m.organization_id=p_org and m.unit_id=p_unit and m.cell_id in(select (x->>'id')::uuid from jsonb_array_elements(cells)x) and m.status='completed' and m.meeting_date between p_from and p_to;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from(
 select c.id,c.name,(select count(*) from public.church_cell_meetings m where m.cell_id=c.id and m.status='completed' and m.meeting_date between p_from and p_to) as meetings,
 (select count(*) from public.church_cell_attendance a join public.church_cell_meetings m on m.id=a.meeting_id where m.cell_id=c.id and m.status='completed' and m.meeting_date between p_from and p_to) as expected,
 (select count(*) from public.church_cell_attendance a join public.church_cell_meetings m on m.id=a.meeting_id where m.cell_id=c.id and m.status='completed' and a.present and m.meeting_date between p_from and p_to) as present
 from public.church_cells c where c.id in(select (x->>'id')::uuid from jsonb_array_elements(cells)x) and(p_after is null or c.id>p_after) order by c.id limit 101)r;
 elsif p_kind='roster' then
 if p_cell is not null and(not private.cell_plus_cell(p_org,p_unit,p_cell,actor,'read') or not exists(select 1 from jsonb_array_elements(cells)x where x->>'id'=p_cell::text)) then raise exception 'cell_access_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from(select m.id,m.cell_id,m.topic,m.meeting_date,m.status,m.version from public.church_cell_meetings m where organization_id=p_org and unit_id=p_unit and cell_id=p_cell and meeting_date between p_from and p_to and(p_after is null or id>p_after) order by id limit 101)r;
 select coalesce(jsonb_agg(jsonb_build_object('meeting_id',a.meeting_id,'participant_id',a.participant_id,'name',p.full_name,'present',a.present) order by a.meeting_id,a.participant_id),'[]') into roster from public.church_cell_attendance a
 join public.church_cell_participants m on m.id=a.participant_id join public.people p on p.id=m.person_id
 where a.organization_id=p_org and a.unit_id=p_unit and a.cell_id=p_cell and a.meeting_id in(select (x->>'id')::uuid from jsonb_array_elements(items)x) and a.meeting_id<>(case when jsonb_array_length(items)=101 then (items->100->>'id')::uuid else '00000000-0000-0000-0000-000000000000'::uuid end);
 else
 select jsonb_build_object('pending',count(*),'unread',coalesce(sum((select count(*) from private.cell_report_notifications n where n.meeting_id=m.id and n.recipient_id=actor and n.read_at is null)),0)) into summary
 from public.church_cell_meetings m where m.organization_id=p_org and m.unit_id=p_unit and m.cell_id in(select (x->>'id')::uuid from jsonb_array_elements(cells)x) and exists(select 1 from public.church_cells c where c.id=m.cell_id and c.status='active') and m.status='scheduled' and m.meeting_date<(now() at time zone 'America/Sao_Paulo')::date;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from(select m.id,m.cell_id,c.name as cell_name,m.topic,m.meeting_date,m.version,
 private.cell_plus_cell(p_org,p_unit,c.id,actor,'followup') as can_notify,
 (select count(*) from private.cell_report_notifications n where n.meeting_id=m.id) as notifications,
 (select count(*) from private.cell_report_notifications n where n.meeting_id=m.id and n.recipient_id=actor and n.read_at is null) as unread
 from public.church_cell_meetings m join public.church_cells c on c.id=m.cell_id
 where m.organization_id=p_org and m.unit_id=p_unit and c.status='active' and m.cell_id in(select (x->>'id')::uuid from jsonb_array_elements(cells)x) and m.status='scheduled' and m.meeting_date<(now() at time zone 'America/Sao_Paulo')::date and(p_after is null or m.id>p_after) order by m.id limit 101)r;
 end if;
 if jsonb_array_length(items)>100 then next_id=(items->99->>'id')::uuid;items=items-100;end if;
 return jsonb_build_object('unitId',p_unit,'kind',p_kind,'networkId',p_network,'cellId',p_cell,'from',p_from,'to',p_to,'items',items,'nextCursor',next_id,'cells',cells,'networks',networks,'manager',manager,'governor',governor,'canReport',coalesce(private.cell_plus_cell(p_org,p_unit,p_cell,actor,'report'),false),'summary',summary,'roster',roster);
end $$;
revoke all on function private.cell_plus_read(uuid,uuid,text,uuid,uuid,date,date,uuid) from public,anon,service_role;
grant execute on function private.cell_plus_read(uuid,uuid,text,uuid,uuid,date,date,uuid) to authenticated;
create function public.cell_plus_read(p_org uuid,p_unit uuid,p_kind text,p_network uuid default null,p_after uuid default null,p_from date default current_date-30,p_to date default current_date,p_cell uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.cell_plus_read(p_org,p_unit,p_kind,p_network,p_after,p_from,p_to,p_cell)$$;
revoke all on function public.cell_plus_read(uuid,uuid,text,uuid,uuid,date,date,uuid) from public,anon,service_role;
grant execute on function public.cell_plus_read(uuid,uuid,text,uuid,uuid,date,date,uuid) to authenticated;

create function private.cell_plus_save(p_org uuid,p_unit uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid();manager boolean;v integer;chosen uuid;target_user uuid;canonical text;counted integer=0;recipient uuid;
 referral private.cell_referrals;material private.cell_study_materials;concession private.cell_supervisor_grants;meeting public.church_cell_meetings;
 ids uuid[];snapshot uuid[];prior uuid[];previous_status text;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for share;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=actor for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_org and m.user_id=actor for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_org and unit_id=p_unit for share;
 if not private.cell_plus_active(p_org,p_unit,actor) then raise exception 'cell_access_denied' using errcode='42501';end if;
 manager=private.cell_flow_manager(p_org,p_unit,actor);
 if p_kind is null or p_kind not in('referral','accept_referral','reject_referral','material','supervisor','notify','read','report') or p_id is null or p_version is null or p_version<0 or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>32768 then raise exception 'invalid_cell_plus' using errcode='22023';end if;
 -- Serialize authorization against hierarchy edits in every isolation level.
 insert into private.cell_hierarchy_guards(unit_id) values(p_unit) on conflict(unit_id) do update set version=private.cell_hierarchy_guards.version+1;
 perform 1 from public.church_cell_networks where organization_id=p_org and unit_id=p_unit order by id for share;
 perform 1 from private.cell_supervisor_grants where organization_id=p_org and unit_id=p_unit and user_id=actor order by id for share;
 perform 1 from public.people p join private.cell_supervisor_grants g on g.person_id=p.id where g.organization_id=p_org and g.unit_id=p_unit and g.user_id=actor order by p.id for share of p;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cell-plus:'||p_id::text,0));
 if p_kind='supervisor' then
  if not manager or not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if not(p_data?&array['network_id','person_id','capability','status']) or p_data-array['network_id','person_id','capability','status']<>'{}' or exists(select 1 from jsonb_each(p_data)e where jsonb_typeof(e.value)<>'string') or p_data->>'capability' not in('read','followup','report') or p_data->>'status' not in('active','revoked') then raise exception 'invalid_cell_plus' using errcode='22023';end if;
  select * into concession from private.cell_supervisor_grants where id=p_id for update;
  chosen=(p_data->>'person_id')::uuid;
  if concession.id is not null and(concession.organization_id<>p_org or concession.unit_id<>p_unit or concession.network_id<>(p_data->>'network_id')::uuid or concession.person_id<>chosen) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if p_data->>'status'='active' then
   select auth_user_id into target_user from public.people where id=chosen and organization_id=p_org and unit_id=p_unit and status='active' for share;
   perform 1 from public.organization_memberships where organization_id=p_org and user_id=target_user for share;
   perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_org and m.user_id=target_user for share of a;
   if target_user is null or not private.cell_plus_unit_read(p_org,p_unit,target_user) or not exists(select 1 from public.church_cell_networks where id=(p_data->>'network_id')::uuid and organization_id=p_org and unit_id=p_unit and status='active') then raise exception 'supervisor_account_unavailable' using errcode='22023';end if;
   if concession.id is not null and concession.user_id<>target_user then raise exception 'cell_access_denied' using errcode='42501';end if;
  else target_user=concession.user_id;end if;
  if coalesce(concession.version,0)<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if concession.id is null then
   if p_version<>0 or p_data->>'status'<>'active' then raise exception 'invalid_cell_plus' using errcode='22023';end if;
   insert into private.cell_supervisor_grants(id,organization_id,unit_id,network_id,person_id,user_id,capability,status,created_by) values(p_id,p_org,p_unit,(p_data->>'network_id')::uuid,chosen,target_user,p_data->>'capability','active',actor) returning version into v;
  else update private.cell_supervisor_grants set capability=p_data->>'capability',status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;end if;
 elsif p_kind='material' then
  if not manager then raise exception 'cell_access_denied' using errcode='42501';end if;
  if not(p_data?&array['network_id','title','body','url','status']) or p_data-array['network_id','title','body','url','status']<>'{}' or jsonb_typeof(p_data->'network_id') not in('null','string') or exists(select 1 from jsonb_each(p_data)e where e.key<>'network_id' and jsonb_typeof(e.value)<>'string') or p_data->>'status' not in('draft','published','archived') or (p_data->>'title') ~ '[[:cntrl:]]' then raise exception 'invalid_cell_plus' using errcode='22023';end if;
  chosen=(p_data->>'network_id')::uuid;
  if chosen is not null and not exists(select 1 from public.church_cell_networks where id=chosen and organization_id=p_org and unit_id=p_unit and status='active') then raise exception 'cell_access_denied' using errcode='42501';end if;
  select * into material from private.cell_study_materials where id=p_id for update;
  if material.id is not null and(material.organization_id<>p_org or material.unit_id<>p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if coalesce(material.version,0)<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if material.id is null then insert into private.cell_study_materials(id,organization_id,unit_id,network_id,title,body,url,status,created_by) values(p_id,p_org,p_unit,chosen,btrim(p_data->>'title'),p_data->>'body',p_data->>'url',p_data->>'status',actor) returning version into v;
  else update private.cell_study_materials set network_id=chosen,title=btrim(p_data->>'title'),body=p_data->>'body',url=p_data->>'url',status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;end if;
 elsif p_kind in('referral','accept_referral','reject_referral') then
  if not manager then raise exception 'cell_access_denied' using errcode='42501';end if;
  select * into referral from private.cell_referrals where id=p_id for update;
  if referral.id is not null and(referral.organization_id<>p_org or referral.unit_id<>p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if coalesce(referral.version,0)<>p_version or referral.id is not null and referral.status<>'pending' then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if p_kind='referral' then
   if not(p_data?&array['cell_id','person_id','person_name']) or p_data-array['cell_id','person_id','person_name']<>'{}' or jsonb_typeof(p_data->'cell_id')<>'string' or jsonb_typeof(p_data->'person_id') not in('string','null') or jsonb_typeof(p_data->'person_name')<>'string' or length(p_data->>'person_name')>200 or (p_data->>'person_name') ~ '[[:cntrl:]]' then raise exception 'invalid_cell_plus' using errcode='22023';end if;
   if referral.id is not null and referral.cell_id<>(p_data->>'cell_id')::uuid then raise exception 'cell_access_denied' using errcode='42501';end if;
   perform 1 from public.church_cells where id=(p_data->>'cell_id')::uuid and organization_id=p_org and unit_id=p_unit and status='active' for update;
   if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
   chosen=(p_data->>'person_id')::uuid;canonical=btrim(p_data->>'person_name');
   if chosen is not null then select full_name into canonical from public.people where id=chosen and organization_id=p_org and unit_id=p_unit and status='active' and private.can_view_person(id) for share;if not found then raise exception 'cell_access_denied' using errcode='42501';end if;end if;
   if referral.id is null then insert into private.cell_referrals(id,organization_id,unit_id,cell_id,person_id,person_name,status,created_by) values(p_id,p_org,p_unit,(p_data->>'cell_id')::uuid,chosen,canonical,'pending',actor) returning version into v;
   else update private.cell_referrals set person_id=chosen,person_name=canonical,version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;end if;
  else
   if p_data<>'{}' or referral.id is null then raise exception 'invalid_cell_plus' using errcode='22023';end if;
   if p_kind='accept_referral' then
    perform 1 from public.church_cells where id=referral.cell_id and status='active' for update;if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
    perform 1 from public.people where id=referral.person_id and organization_id=p_org and unit_id=p_unit and status='active' and private.can_view_person(id) for share;
    if not found then raise exception 'link_member_before_accept' using errcode='22023';end if;
    insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values(gen_random_uuid(),p_org,p_unit,referral.cell_id,referral.person_id,'active',actor)
    on conflict(cell_id,person_id) do update set status='active',version=public.church_cell_participants.version+1,updated_at=clock_timestamp();
   end if;
   update private.cell_referrals set status=case p_kind when 'accept_referral' then 'accepted' else 'rejected' end,version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;
  end if;
 else
  if p_kind='report' then
   if not(p_data?'present') or p_data-'present'<>'{}' or jsonb_typeof(p_data->'present')<>'array' or jsonb_array_length(p_data->'present')>500 or exists(select 1 from jsonb_array_elements(p_data->'present')x where jsonb_typeof(x)<>'string') then raise exception 'invalid_cell_plus' using errcode='22023';end if;
  elsif p_data<>'{}' then raise exception 'invalid_cell_plus' using errcode='22023';end if;
  select * into meeting from public.church_cell_meetings where id=p_id and organization_id=p_org and unit_id=p_unit;
  if meeting.id is null then raise exception 'cell_access_denied' using errcode='42501';end if;
  perform 1 from public.church_cells where id=meeting.cell_id and status='active' for update;
  -- Existing assignment writer updates this row, not the cell version. Lock it to detect stale snapshots.
  perform 1 from public.church_cell_network_links where cell_id=meeting.cell_id for share;
  if not exists(select 1 from public.church_cells where id=meeting.cell_id and status='active') or not private.cell_plus_cell(p_org,p_unit,meeting.cell_id,actor,case when p_kind='report' then 'report' when p_kind='notify' then 'followup' else 'read' end) then raise exception 'cell_access_denied' using errcode='42501';end if;
  select * into meeting from public.church_cell_meetings where id=p_id for update;
  if meeting.version<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if p_kind='report' then
   if meeting.status not in('scheduled','completed') then raise exception 'invalid_cell_plus' using errcode='22023';end if;
   select coalesce(array_agg(value::uuid order by value::uuid),'{}') into ids from jsonb_array_elements_text(p_data->'present');
   select coalesce(array_agg(participant_id order by participant_id),'{}') into snapshot from public.church_cell_attendance where meeting_id=p_id;
   if cardinality(ids)<>(select count(distinct x) from unnest(ids)x) or not ids<@snapshot then raise exception 'invalid_cell_plus' using errcode='22023';end if;
   update public.church_cell_attendance set present=participant_id=any(ids) where meeting_id=p_id;
   update public.church_cell_meetings set status='completed',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;
  elsif p_kind='read' then
   update private.cell_report_notifications set read_at=coalesce(read_at,clock_timestamp()) where meeting_id=p_id and recipient_id=actor returning 1 into v;
   if not found then raise exception 'cell_access_denied' using errcode='42501';end if;v=p_version;
  else
   if meeting.status<>'scheduled' or meeting.meeting_date>=(now() at time zone 'America/Sao_Paulo')::date then raise exception 'invalid_cell_plus' using errcode='22023';end if;
   for recipient in select distinct u from (
    select p.auth_user_id as u from public.church_cells c join public.people p on p.id=c.leader_person_id and p.organization_id=c.organization_id and p.unit_id=c.unit_id and p.status='active' where c.id=meeting.cell_id
    union select g.user_id from private.cell_supervisor_grants g join public.church_cell_network_links l on l.cell_id=meeting.cell_id where g.organization_id=p_org and g.unit_id=p_unit and g.status='active' and private.cell_plus_network(p_org,p_unit,l.network_id,g.user_id))r where u is not null loop
    perform 1 from public.organization_memberships where organization_id=p_org and user_id=recipient for share;
    if private.cell_plus_active(p_org,p_unit,recipient) and private.cell_plus_cell(p_org,p_unit,meeting.cell_id,recipient) then
     insert into private.cell_report_notifications(organization_id,unit_id,cell_id,meeting_id,recipient_id,created_by) values(p_org,p_unit,meeting.cell_id,p_id,recipient,actor) on conflict(meeting_id,recipient_id) do nothing;
     if found then counted=counted+1;end if;
    end if;
   end loop;
   v=p_version;
  end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'cell.integrated_'||p_kind,'church_cell_integrated',p_id::text,jsonb_build_object('unit_id',p_unit,'version',v,'notifications_created',counted));
 return jsonb_build_object('id',p_id,'version',v,'notificationsCreated',counted);
end $$;
revoke all on function private.cell_plus_save(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.cell_plus_save(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.cell_plus_save(p_org uuid,p_unit uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.cell_plus_save(p_org,p_unit,p_kind,p_id,p_version,p_data)$$;
revoke all on function public.cell_plus_save(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_plus_save(uuid,uuid,text,uuid,integer,jsonb) to authenticated;

-- A scheduled service can create only deduplicated internal reminders, never send externally.
create function private.cell_report_reminder_batch(p_after uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare meeting public.church_cell_meetings;recipient uuid;created integer=0;scanned integer=0;cursor_id uuid;unreachable integer=0;reachable integer;
begin
 if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('cell-reminder-scan',0)) then return jsonb_build_object('created',0,'scanned',0,'unreachable',0,'nextCursor',null);end if;
 insert into private.cell_report_scan_checkpoint(id) values(true) on conflict(id) do nothing;
 if p_after is null then select after_id into p_after from private.cell_report_scan_checkpoint where id=true for update;end if;
 for meeting in select m.* from public.church_cell_meetings m where m.status='scheduled' and m.meeting_date<(now() at time zone 'America/Sao_Paulo')::date and(p_after is null or m.id>p_after) order by m.id limit 100 loop
  scanned=scanned+1;cursor_id=meeting.id;reachable=0;
  perform 1 from public.organizations where id=meeting.organization_id for share;
  perform 1 from public.organization_units where id=meeting.unit_id and organization_id=meeting.organization_id for share;
  perform 1 from public.saas_unit_contracts where organization_id=meeting.organization_id and unit_id=meeting.unit_id for share;
  insert into private.cell_hierarchy_guards(unit_id) values(meeting.unit_id) on conflict(unit_id) do update set version=private.cell_hierarchy_guards.version+1;
  perform 1 from public.church_cell_networks where organization_id=meeting.organization_id and unit_id=meeting.unit_id order by id for share;
  perform 1 from private.cell_supervisor_grants where organization_id=meeting.organization_id and unit_id=meeting.unit_id order by id for share;
  perform 1 from public.church_cells where id=meeting.cell_id and status='active' for share;
  if not found then continue;end if;
  perform 1 from public.church_cell_meetings where id=meeting.id and status='scheduled' for share;if not found then continue;end if;
  for recipient in select distinct u from (
   select p.auth_user_id as u from public.church_cells c join public.people p on p.id=c.leader_person_id and p.organization_id=c.organization_id and p.unit_id=c.unit_id and p.status='active' where c.id=meeting.cell_id
   union select g.user_id from private.cell_supervisor_grants g join public.church_cell_network_links l on l.cell_id=meeting.cell_id where g.organization_id=meeting.organization_id and g.unit_id=meeting.unit_id and g.status='active' and private.cell_plus_network(meeting.organization_id,meeting.unit_id,l.network_id,g.user_id))r where u is not null loop
   perform 1 from public.organization_memberships where organization_id=meeting.organization_id and user_id=recipient for share;
   perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=meeting.organization_id and m.user_id=recipient for share of a;
   perform 1 from public.people p where p.organization_id=meeting.organization_id and p.unit_id=meeting.unit_id and p.auth_user_id=recipient for share;
   if private.cell_plus_cell(meeting.organization_id,meeting.unit_id,meeting.cell_id,recipient) then
    reachable=reachable+1;
    insert into private.cell_report_notifications(organization_id,unit_id,cell_id,meeting_id,recipient_id,source) values(meeting.organization_id,meeting.unit_id,meeting.cell_id,meeting.id,recipient,'scheduled') on conflict(meeting_id,recipient_id) do nothing;
    if found then created=created+1;end if;
   end if;
  end loop;
  if reachable=0 then unreachable=unreachable+1;end if;
 end loop;
 update private.cell_report_scan_checkpoint set after_id=case when scanned=100 then cursor_id else null end where id=true;
 return jsonb_build_object('created',created,'scanned',scanned,'unreachable',unreachable,'nextCursor',case when scanned=100 then cursor_id else null end);
end $$;
revoke all on function private.cell_report_reminder_batch(uuid) from public,anon,authenticated;
grant execute on function private.cell_report_reminder_batch(uuid) to service_role;
grant usage on schema private to service_role;
create function public.cell_report_reminder_batch(p_after uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.cell_report_reminder_batch(p_after)$$;
revoke all on function public.cell_report_reminder_batch(uuid) from public,anon,authenticated;
grant execute on function public.cell_report_reminder_batch(uuid) to service_role;
create or replace function public.ministry_language_save(p_organization uuid,p_version integer,p_labels jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous public.ministry_language; v integer;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for update;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() for share;
 if not private.has_organization_role(p_organization,array['owner','admin']::public.membership_role[])
 or not exists(select 1 from public.organizations where id=p_organization and status in ('active','trial')) then raise exception 'language_access_denied' using errcode='42501';end if;
 if p_version is null or p_version<0 or p_labels is null or jsonb_typeof(p_labels)<>'object' or pg_column_size(p_labels)>8192 then raise exception 'invalid_language' using errcode='22023';end if;
 if exists(select 1 from jsonb_each(p_labels)e where e.key<>all(array['inicio','pessoas','familias','aplicativo','kids','igrejas','usuarios','eventos','celulas','escalas','louvor','comunicacao','transmissoes','financeiro','relatorios','configuracoes','celulas.geral','celulas.redes','celulas.supervisor','celulas.singular','celulas.plural','celulas.cadastro','celulas.encontros','celulas.participantes','celulas.visitantes','celulas.relatorios','celulas.categorias','celulas.responsavel','celulas.local','celulas.indicacoes','celulas.materiais','celulas.consolidado','celulas.pendencias','celulas.supervisao'])
 or jsonb_typeof(e.value)<>'string' or length(btrim(e.value#>>'{}')) not between 2 and 48 or (e.value#>>'{}') ~ '[[:cntrl:]]') then raise exception 'invalid_language' using errcode='22023';end if;
 select * into previous from public.ministry_language where organization_id=p_organization for update;
 if coalesce(previous.version,0)<>p_version then
  if previous.version=p_version+1 and previous.updated_by=auth.uid() and previous.labels=p_labels then return public.ministry_language_read(p_organization);end if;
  raise exception 'language_version_conflict' using errcode='40001';
 end if;
 insert into public.ministry_language(organization_id,labels,updated_by) values(p_organization,p_labels,auth.uid())
 on conflict(organization_id) do update set labels=excluded.labels,updated_by=excluded.updated_by,version=public.ministry_language.version+1,updated_at=clock_timestamp() returning version into v;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,auth.uid(),'language.updated','ministry_language',p_organization::text,jsonb_build_object('version',v,'keys',(select jsonb_agg(key) from jsonb_object_keys(p_labels)key)));
 return public.ministry_language_read(p_organization);
end $$;
revoke all on function public.ministry_language_save(uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.ministry_language_save(uuid,integer,jsonb) to authenticated;
