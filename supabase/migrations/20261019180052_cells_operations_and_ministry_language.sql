-- Shared display names do not change identifiers, permissions or entitlements.
create table public.ministry_language (
 organization_id uuid primary key references public.organizations(id) on delete restrict,
 labels jsonb not null default '{}' check(jsonb_typeof(labels)='object'),
 version integer not null default 1 check(version>0),
 updated_by uuid not null references auth.users(id) on delete restrict,
 updated_at timestamptz not null default now()
);
create index ministry_language_actor_idx on public.ministry_language(updated_by);
alter table public.ministry_language enable row level security;
revoke all on public.ministry_language from public,anon,authenticated,service_role;
grant select on public.ministry_language to authenticated;
create policy ministry_language_read on public.ministry_language for select to authenticated using(
 exists(select 1 from public.organization_memberships m where m.organization_id=ministry_language.organization_id and m.user_id=(select auth.uid()) and m.status='active')
);
create function public.ministry_language_read(p_organization uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare state public.ministry_language;
begin
 if not exists(select 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() and status='active') then raise exception 'language_access_denied' using errcode='42501';end if;
 select * into state from public.ministry_language where organization_id=p_organization;
 return jsonb_build_object('organizationId',p_organization,'labels',coalesce(state.labels,'{}'), 'version',coalesce(state.version,0),
 'canManage',private.has_organization_role(p_organization,array['owner','admin']::public.membership_role[]));
end $$;
revoke all on function public.ministry_language_read(uuid) from public,anon,service_role;
grant execute on function public.ministry_language_read(uuid) to authenticated;
create function public.ministry_language_save(p_organization uuid,p_version integer,p_labels jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous public.ministry_language; v integer;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for update;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() for share;
 if not private.has_organization_role(p_organization,array['owner','admin']::public.membership_role[])
 or not exists(select 1 from public.organizations where id=p_organization and status in ('active','trial')) then raise exception 'language_access_denied' using errcode='42501';end if;
 if p_version is null or p_version<0 or p_labels is null or jsonb_typeof(p_labels)<>'object' or pg_column_size(p_labels)>8192 then raise exception 'invalid_language' using errcode='22023';end if;
 if exists(select 1 from jsonb_each(p_labels)e where e.key<>all(array['inicio','pessoas','familias','aplicativo','kids','igrejas','usuarios','eventos','celulas','escalas','louvor','comunicacao','transmissoes','financeiro','relatorios','configuracoes','celulas.singular','celulas.plural','celulas.cadastro','celulas.encontros','celulas.participantes','celulas.relatorios','celulas.categorias','celulas.responsavel','celulas.local'])
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

alter table public.church_cells add constraint church_cells_scope_key unique(id,organization_id,unit_id);
create table public.church_cell_categories (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 80),
 status text not null check(status in ('active','archived')),version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id) on delete restrict,
 unique(id,organization_id,unit_id)
);
create unique index cell_categories_name_idx on public.church_cell_categories(organization_id,unit_id,lower(name)) where status='active';
create index cell_categories_actor_idx on public.church_cell_categories(created_by);
create table public.church_cell_category_links (
 cell_id uuid primary key,organization_id uuid not null,unit_id uuid not null,category_id uuid,
 version integer not null default 1 check(version>0),updated_by uuid not null references auth.users(id) on delete restrict,
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 foreign key(category_id,organization_id,unit_id) references public.church_cell_categories(id,organization_id,unit_id) on delete restrict
);
create index cell_category_links_category_idx on public.church_cell_category_links(category_id,organization_id,unit_id);
create index cell_category_links_scope_idx on public.church_cell_category_links(organization_id,unit_id);
create index cell_category_links_actor_idx on public.church_cell_category_links(updated_by);
create table public.church_cell_participants (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,cell_id uuid not null,person_id uuid not null,
 status text not null check(status in ('active','inactive')),version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete restrict,
 unique(cell_id,person_id),unique(id,cell_id,organization_id,unit_id)
);
create index cell_participants_scope_idx on public.church_cell_participants(organization_id,unit_id,cell_id,id);
create index cell_participants_person_idx on public.church_cell_participants(person_id,organization_id);
create index cell_participants_actor_idx on public.church_cell_participants(created_by);
create table public.church_cell_meetings (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,cell_id uuid not null,
 topic text not null check(length(btrim(topic)) between 2 and 120),meeting_date date not null check(meeting_date between date '1900-01-01' and date '2200-12-31'),
 meeting_time text not null check(meeting_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
 status text not null check(status in ('scheduled','completed','cancelled')),version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 unique(id,cell_id,organization_id,unit_id)
);
create unique index cell_meetings_slot_idx on public.church_cell_meetings(cell_id,meeting_date,meeting_time) where status<>'cancelled';
create index cell_meetings_scope_idx on public.church_cell_meetings(organization_id,unit_id,meeting_date,id);
create index cell_meetings_actor_idx on public.church_cell_meetings(created_by);
create table public.church_cell_attendance (
 meeting_id uuid not null,participant_id uuid not null,cell_id uuid not null,organization_id uuid not null,unit_id uuid not null,present boolean not null,
 primary key(meeting_id,participant_id),
 foreign key(meeting_id,cell_id,organization_id,unit_id) references public.church_cell_meetings(id,cell_id,organization_id,unit_id) on delete restrict,
 foreign key(participant_id,cell_id,organization_id,unit_id) references public.church_cell_participants(id,cell_id,organization_id,unit_id) on delete restrict
);
create index cell_attendance_person_idx on public.church_cell_attendance(participant_id,cell_id,organization_id,unit_id);
create index cell_attendance_scope_idx on public.church_cell_attendance(organization_id,unit_id);

create function private.cell_people_allowed(p_organization uuid,p_unit uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select private.cell_directory_allowed(p_organization,p_unit) and private.target_unit_module_enabled(p_organization,p_unit,'people');
$$;
revoke all on function private.cell_people_allowed(uuid,uuid) from public,anon,service_role;
grant execute on function private.cell_people_allowed(uuid,uuid) to authenticated;
alter table public.church_cell_categories enable row level security;
alter table public.church_cell_category_links enable row level security;
alter table public.church_cell_participants enable row level security;
alter table public.church_cell_meetings enable row level security;
alter table public.church_cell_attendance enable row level security;
revoke all on public.church_cell_categories,public.church_cell_category_links,public.church_cell_participants,public.church_cell_meetings,public.church_cell_attendance from public,anon,authenticated,service_role;
grant select on public.church_cell_categories,public.church_cell_category_links,public.church_cell_participants,public.church_cell_meetings,public.church_cell_attendance to authenticated;
create policy cell_categories_read on public.church_cell_categories for select to authenticated using(private.cell_directory_allowed(organization_id,unit_id));
create policy cell_category_links_read on public.church_cell_category_links for select to authenticated using(private.cell_directory_allowed(organization_id,unit_id));
create policy cell_participants_read on public.church_cell_participants for select to authenticated using(private.cell_people_allowed(organization_id,unit_id));
create policy cell_meetings_read on public.church_cell_meetings for select to authenticated using(private.cell_people_allowed(organization_id,unit_id));
create policy cell_attendance_read on public.church_cell_attendance for select to authenticated using(private.cell_people_allowed(organization_id,unit_id));

create function public.cell_operations_read(p_organization uuid,p_unit uuid,p_kind text,p_cell uuid default null,p_record uuid default null,p_after uuid default null,p_search text default '',p_from date default current_date-30,p_to date default current_date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare items jsonb; more uuid; assignment jsonb; page_limit integer=100;
begin
 if p_kind is null or p_kind<>all(array['categories','participants','meetings','roster','people','report']) then raise exception 'invalid_cell_operation' using errcode='22023';end if;
 if not coalesce(private.cell_directory_allowed(p_organization,p_unit),false) or (p_kind<>'categories' and not coalesce(private.cell_people_allowed(p_organization,p_unit),false)) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'invalid_cell_period' using errcode='22023';end if;
 if p_cell is not null and not exists(select 1 from public.church_cells where id=p_cell and organization_id=p_organization and unit_id=p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_kind in ('participants','roster') and p_cell is null then raise exception 'cell_required' using errcode='22023';end if;
 if p_kind='categories' then
  select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') into items from (select id,name,status,version from public.church_cell_categories where organization_id=p_organization and unit_id=p_unit and (p_after is null or id>p_after) order by id limit 101)c;
  select jsonb_build_object('category_id',category_id,'version',version) into assignment from public.church_cell_category_links where cell_id=p_cell and organization_id=p_organization and unit_id=p_unit;
 elsif p_kind='people' then
  if p_search is null or length(btrim(p_search)) not between 2 and 80 then raise exception 'search_required' using errcode='22023';end if;
  page_limit=30;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') into items from (select id,full_name as name from public.people where organization_id=p_organization and unit_id=p_unit and status='active' and strpos(lower(full_name),lower(btrim(p_search)))>0 and (p_after is null or id>p_after) order by id limit 31)c;
 elsif p_kind='participants' then
  select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') into items from (select m.id,m.person_id,m.status,m.version,
  coalesce(p.full_name,'Cadastro indisponível nesta unidade') as name from public.church_cell_participants m left join public.people p on p.id=m.person_id and p.organization_id=m.organization_id and p.unit_id=m.unit_id
  where m.organization_id=p_organization and m.unit_id=p_unit and m.cell_id=p_cell and (p_after is null or m.id>p_after) order by m.id limit 101)c;
 elsif p_kind='meetings' then
  select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') into items from (select id,cell_id,topic,meeting_date,meeting_time,status,version from public.church_cell_meetings where organization_id=p_organization and unit_id=p_unit and (p_cell is null or cell_id=p_cell) and meeting_date between p_from and p_to and (p_after is null or id>p_after) order by id limit 101)c;
 elsif p_kind='roster' then
  page_limit=500;
  if p_record is not null and not exists(select 1 from public.church_cell_meetings where id=p_record and cell_id=p_cell and organization_id=p_organization and unit_id=p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') into items from (select m.id,coalesce(p.full_name,'Cadastro indisponível nesta unidade') as name,coalesce(a.present,false) as present
   from public.church_cell_participants m left join public.people p on p.id=m.person_id and p.organization_id=m.organization_id and p.unit_id=m.unit_id
   left join public.church_cell_attendance a on a.participant_id=m.id and a.meeting_id=p_record
   where m.organization_id=p_organization and m.unit_id=p_unit and m.cell_id=p_cell
   and ((p_record is null and m.status='active' and p.status='active') or (p_record is not null and a.meeting_id is not null)) order by m.id limit 501)c;
  if jsonb_array_length(items)>500 then raise exception 'cell_roster_too_large' using errcode='22023';end if;
 elsif p_kind='report' then
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') into items from (
   select c.id,c.name,c.status,coalesce(cat.name,'Sem categoria') as category,
   (select count(*)::integer from public.church_cell_participants m join public.people p on p.id=m.person_id and p.organization_id=m.organization_id and p.unit_id=m.unit_id where m.cell_id=c.id and m.status='active' and p.status='active') as participants,
   (select count(*)::integer from public.church_cell_meetings m where m.cell_id=c.id and m.status='completed' and m.meeting_date between p_from and p_to) as meetings,
   (select count(*)::integer from public.church_cell_attendance a join public.church_cell_meetings m on m.id=a.meeting_id where m.cell_id=c.id and m.status='completed' and m.meeting_date between p_from and p_to) as expected,
   (select count(*)::integer from public.church_cell_attendance a join public.church_cell_meetings m on m.id=a.meeting_id where m.cell_id=c.id and m.status='completed' and a.present and m.meeting_date between p_from and p_to) as present
   from public.church_cells c left join public.church_cell_category_links l on l.cell_id=c.id left join public.church_cell_categories cat on cat.id=l.category_id
   where c.organization_id=p_organization and c.unit_id=p_unit and (p_cell is null or c.id=p_cell) and (p_after is null or c.id>p_after) order by c.id limit 101
  )r;
 end if;
 if jsonb_array_length(items)>page_limit then more=(items->(page_limit-1)->>'id')::uuid;items=items-page_limit;end if;
 return jsonb_build_object('unitId',p_unit,'kind',p_kind,'cellId',p_cell,'items',items,'nextCursor',more,'assignment',assignment,
 'canManage',private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[]) and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]));
end $$;
revoke all on function public.cell_operations_read(uuid,uuid,text,uuid,uuid,uuid,text,date,date) from public,anon,service_role;
grant execute on function public.cell_operations_read(uuid,uuid,text,uuid,uuid,uuid,text,date,date) to authenticated;

-- Privileged write is intentionally restricted to validated, atomic commands.
create function public.cell_operations_save(p_organization uuid,p_unit uuid,p_kind text,p_cell uuid,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cat public.church_cell_categories; participant public.church_cell_participants; meeting public.church_cell_meetings; link public.church_cell_category_links;
 v integer; changed boolean=true; present_ids uuid[]; snapshot_ids uuid[]; before_ids uuid[];
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_organization for share;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_organization and m.user_id=auth.uid() for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_organization and unit_id=p_unit for share;
 if not coalesce(private.cell_directory_allowed(p_organization,p_unit),false)
 or not private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 or not private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[])
 or (p_kind in ('participant','meeting') and not coalesce(private.cell_people_allowed(p_organization,p_unit),false)) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_kind is null or p_kind<>all(array['category','assign_category','participant','meeting']) or p_id is null or p_version is null or p_version<0 or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>32768 then raise exception 'invalid_cell_input' using errcode='22023';end if;
 -- Parent row serializes participant changes, roster snapshots and archiving.
 if p_kind<>'category' then
  perform 1 from public.church_cells where id=p_cell and organization_id=p_organization and unit_id=p_unit for update;
  if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 if p_kind='category' then
  if p_cell is not null or not(p_data ?& array['name','status']) or p_data-array['name','status']<>'{}' or jsonb_typeof(p_data->'name')<>'string' or jsonb_typeof(p_data->'status')<>'string' or p_data->>'status'<>all(array['active','archived']) then raise exception 'invalid_cell_input' using errcode='22023';end if;
  select * into cat from public.church_cell_categories where id=p_id for update;
  if found then
   if cat.organization_id<>p_organization or cat.unit_id<>p_unit then raise exception 'cell_access_denied' using errcode='42501';end if;
   if p_version=0 and cat.version=1 and cat.created_by=auth.uid() and cat.name=btrim(p_data->>'name') and cat.status=p_data->>'status' then return jsonb_build_object('id',p_id,'version',1);end if;
   if cat.version<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
   update public.church_cell_categories set name=btrim(p_data->>'name'),status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;
  else
   if p_version<>0 or p_data->>'status'<>'active' then raise exception 'cell_version_conflict' using errcode='40001';end if;
   insert into public.church_cell_categories(id,organization_id,unit_id,name,status,created_by) values(p_id,p_organization,p_unit,btrim(p_data->>'name'),'active',auth.uid()) returning version into v;
  end if;
 elsif p_kind='assign_category' then
  if p_id<>p_cell or not(p_data?'category_id') or p_data-'category_id'<>'{}' or jsonb_typeof(p_data->'category_id')<>all(array['string','null']) then raise exception 'invalid_cell_input' using errcode='22023';end if;
  if p_data->>'category_id' is not null then
   perform 1 from public.church_cell_categories where id=(p_data->>'category_id')::uuid and organization_id=p_organization and unit_id=p_unit and status='active' for share;
   if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
  end if;
  select * into link from public.church_cell_category_links where cell_id=p_cell for update;
  if coalesce(link.version,0)<>p_version then
   if link.version=p_version+1 and link.updated_by=auth.uid() and link.category_id is not distinct from (p_data->>'category_id')::uuid then return jsonb_build_object('id',p_id,'version',link.version);end if;
   raise exception 'cell_version_conflict' using errcode='40001';
  end if;
  insert into public.church_cell_category_links(cell_id,organization_id,unit_id,category_id,updated_by) values(p_cell,p_organization,p_unit,(p_data->>'category_id')::uuid,auth.uid()) on conflict(cell_id) do update set category_id=excluded.category_id,updated_by=excluded.updated_by,version=public.church_cell_category_links.version+1 returning version into v;
 elsif p_kind='participant' then
  if not(p_data ?& array['person_id','status']) or p_data-array['person_id','status']<>'{}' or jsonb_typeof(p_data->'person_id')<>'string' or jsonb_typeof(p_data->'status')<>'string' or p_data->>'status'<>all(array['active','inactive']) then raise exception 'invalid_cell_input' using errcode='22023';end if;
  select * into participant from public.church_cell_participants where id=p_id for update;
  if participant.id is not null and (participant.organization_id<>p_organization or participant.unit_id<>p_unit or participant.cell_id<>p_cell or participant.person_id<>(p_data->>'person_id')::uuid) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if p_data->>'status'='active' then
   if not exists(select 1 from public.church_cells where id=p_cell and status='active') then raise exception 'cell_archived' using errcode='22023';end if;
   perform 1 from public.people where id=(p_data->>'person_id')::uuid and organization_id=p_organization and unit_id=p_unit and status='active' and private.can_view_person(id) for share;
   if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
  end if;
  if participant.id is not null then
   if p_version=0 and participant.version=1 and participant.created_by=auth.uid() and participant.status=p_data->>'status' then return jsonb_build_object('id',p_id,'version',1);end if;
   if participant.version<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
   update public.church_cell_participants set status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;
  else
   if p_version<>0 or p_data->>'status'<>'active' then raise exception 'cell_version_conflict' using errcode='40001';end if;
   insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values(p_id,p_organization,p_unit,p_cell,(p_data->>'person_id')::uuid,'active',auth.uid()) returning version into v;
  end if;
 elsif p_kind='meeting' then
  if not(p_data ?& array['topic','meeting_date','meeting_time','status','present']) or p_data-array['topic','meeting_date','meeting_time','status','present']<>'{}'
  or exists(select 1 from jsonb_each(p_data)e where e.key<>'present' and jsonb_typeof(e.value)<>'string')
  or jsonb_typeof(p_data->'present')<>'array' or p_data->>'status'<>all(array['scheduled','completed','cancelled']) then raise exception 'invalid_cell_input' using errcode='22023';end if;
  if jsonb_array_length(p_data->'present')>500 or exists(select 1 from jsonb_array_elements(p_data->'present') as entry(value) where jsonb_typeof(entry.value)<>'string') then raise exception 'invalid_cell_input' using errcode='22023';end if;
  select coalesce(array_agg(value::uuid order by value::uuid),'{}') into present_ids from jsonb_array_elements_text(p_data->'present');
  if cardinality(present_ids)<>(select count(distinct x) from unnest(present_ids)x) or (p_data->>'status'<>'completed' and cardinality(present_ids)>0) then raise exception 'invalid_cell_input' using errcode='22023';end if;
  select * into meeting from public.church_cell_meetings where id=p_id for update;
  if meeting.id is not null and (meeting.organization_id<>p_organization or meeting.unit_id<>p_unit or meeting.cell_id<>p_cell) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if meeting.id is not null then
   select coalesce(array_agg(participant_id order by participant_id),'{}') into snapshot_ids from public.church_cell_attendance where meeting_id=p_id;
   select coalesce(array_agg(participant_id order by participant_id),'{}') into before_ids from public.church_cell_attendance where meeting_id=p_id and present;
   if p_version=0 and meeting.version=1 and meeting.created_by=auth.uid() and meeting.topic=btrim(p_data->>'topic') and meeting.meeting_date=(p_data->>'meeting_date')::date and meeting.meeting_time=p_data->>'meeting_time' and meeting.status=p_data->>'status' and before_ids=present_ids then return jsonb_build_object('id',p_id,'version',1);end if;
   if meeting.version<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
  else
   if p_version<>0 then raise exception 'cell_version_conflict' using errcode='40001';end if;
   if not exists(select 1 from public.church_cells where id=p_cell and status='active') then raise exception 'cell_archived' using errcode='22023';end if;
   perform 1 from public.church_cell_participants where cell_id=p_cell for share;
   perform 1 from public.people p join public.church_cell_participants m on m.person_id=p.id where m.cell_id=p_cell for share of p;
   select coalesce(array_agg(m.id order by m.id),'{}') into snapshot_ids from public.church_cell_participants m join public.people p on p.id=m.person_id and p.organization_id=m.organization_id and p.unit_id=m.unit_id where m.cell_id=p_cell and m.status='active' and p.status='active' and private.can_view_person(p.id);
  end if;
  if cardinality(snapshot_ids)>500 or not(present_ids<@snapshot_ids) then raise exception 'invalid_cell_roster' using errcode='22023';end if;
  if meeting.id is null then
   insert into public.church_cell_meetings(id,organization_id,unit_id,cell_id,topic,meeting_date,meeting_time,status,created_by) values(p_id,p_organization,p_unit,p_cell,btrim(p_data->>'topic'),(p_data->>'meeting_date')::date,p_data->>'meeting_time',p_data->>'status',auth.uid()) returning version into v;
   insert into public.church_cell_attendance(meeting_id,participant_id,cell_id,organization_id,unit_id,present) select p_id,x,p_cell,p_organization,p_unit,x=any(present_ids) from unnest(snapshot_ids)x;
  else
   update public.church_cell_meetings set topic=btrim(p_data->>'topic'),meeting_date=(p_data->>'meeting_date')::date,meeting_time=p_data->>'meeting_time',status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into v;
   update public.church_cell_attendance set present=participant_id=any(present_ids) where meeting_id=p_id;
  end if;
 end if;
 -- Fence stale REPEATABLE READ/SERIALIZABLE snapshots after a roster change.
 -- Directory fields/version are unchanged; updated_at represents latest activity.
 if p_kind<>'category' then update public.church_cells set updated_at=clock_timestamp() where id=p_cell;end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,auth.uid(),'cell.'||p_kind||'.saved','cell_operation',p_id::text,jsonb_build_object('unit_id',p_unit,'cell_id',p_cell,'version',v,'status',p_data->>'status','present_before',before_ids,'present_after',present_ids));
 return jsonb_build_object('id',p_id,'version',v);
end $$;
revoke all on function public.cell_operations_save(uuid,uuid,text,uuid,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_operations_save(uuid,uuid,text,uuid,uuid,integer,jsonb) to authenticated;
