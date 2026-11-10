-- Flat networks inside one authorized unit. A supervisor name never grants access.
create table public.church_cell_networks (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 100 and name !~ '[[:cntrl:]]'),
 supervisor_name text not null default '' check(length(supervisor_name)<=120 and supervisor_name !~ '[[:cntrl:]]'),supervisor_person_id uuid,
 status text not null check(status in ('active','archived')),version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id) on delete restrict,
 foreign key(supervisor_person_id,organization_id) references public.people(id,organization_id) on delete restrict,
 unique(id,organization_id,unit_id)
);
create index cell_networks_scope_idx on public.church_cell_networks(organization_id,unit_id,id);
create index cell_networks_unit_idx on public.church_cell_networks(unit_id,organization_id);
create index cell_networks_supervisor_idx on public.church_cell_networks(supervisor_person_id,organization_id);
create index cell_networks_actor_idx on public.church_cell_networks(created_by);
create unique index cell_networks_name_idx on public.church_cell_networks(organization_id,unit_id,lower(name)) where status='active';
create table public.church_cell_network_links (
 cell_id uuid primary key,organization_id uuid not null,unit_id uuid not null,network_id uuid,
 version integer not null default 1 check(version>0),updated_by uuid not null references auth.users(id) on delete restrict,updated_at timestamptz not null default now(),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 foreign key(network_id,organization_id,unit_id) references public.church_cell_networks(id,organization_id,unit_id) on delete restrict
);
create index cell_network_links_network_idx on public.church_cell_network_links(network_id,organization_id,unit_id);
create index cell_network_links_cell_fk_idx on public.church_cell_network_links(cell_id,organization_id,unit_id);
create index cell_network_links_scope_idx on public.church_cell_network_links(organization_id,unit_id);
create index cell_network_links_actor_idx on public.church_cell_network_links(updated_by);
alter table public.church_cell_networks enable row level security;
alter table public.church_cell_network_links enable row level security;
revoke all on public.church_cell_networks,public.church_cell_network_links from public,anon,authenticated,service_role;
grant select on public.church_cell_networks,public.church_cell_network_links to authenticated;
create policy cell_networks_read on public.church_cell_networks for select to authenticated using(private.cell_people_allowed(organization_id,unit_id));
create policy cell_network_links_read on public.church_cell_network_links for select to authenticated using(private.cell_people_allowed(organization_id,unit_id));

create function public.cell_networks_read(p_organization uuid,p_unit uuid,p_kind text,p_network uuid default null,p_after uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare items jsonb; next_id uuid;
begin
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_kind is null or p_kind not in ('networks','cells') or (p_kind='networks' and p_network is not null) then raise exception 'invalid_network' using errcode='22023';end if;
 if p_network is not null and not exists(select 1 from public.church_cell_networks where id=p_network and organization_id=p_organization and unit_id=p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_kind='networks' then
  select coalesce(jsonb_agg(to_jsonb(n) order by n.id),'[]'::jsonb) into items from
  (select id,name,supervisor_name,supervisor_person_id,status,version from public.church_cell_networks where organization_id=p_organization and unit_id=p_unit and(p_after is null or id>p_after) order by id limit 101)n;
 else
  select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]'::jsonb) into items from
  (select c.id,c.name,c.status,l.network_id,n.name as network_name,n.status as network_status,coalesce(l.version,0) as version from public.church_cells c
   left join public.church_cell_network_links l on l.cell_id=c.id and l.organization_id=c.organization_id and l.unit_id=c.unit_id
   left join public.church_cell_networks n on n.id=l.network_id and n.organization_id=c.organization_id and n.unit_id=c.unit_id
   where c.organization_id=p_organization and c.unit_id=p_unit and(p_network is null or l.network_id=p_network) and(p_after is null or c.id>p_after) order by c.id limit 101)c;
 end if;
 if jsonb_array_length(items)>100 then next_id=(items->99->>'id')::uuid;items=items-100;end if;
 return jsonb_build_object('unitId',p_unit,'kind',p_kind,'networkId',p_network,'items',items,'nextCursor',next_id,
 'canManage',private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]));
end $$;
revoke all on function public.cell_networks_read(uuid,uuid,text,uuid,uuid) from public,anon,service_role;
grant execute on function public.cell_networks_read(uuid,uuid,text,uuid,uuid) to authenticated;

create function private.cell_networks_save(p_organization uuid,p_unit uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid(); previous public.church_cell_networks; link public.church_cell_network_links;
 chosen uuid; chosen_name text; new_version integer;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_organization for share;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=actor for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_organization and m.user_id=actor for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_organization and unit_id=p_unit for share;
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false)
 or not private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 or not private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_id is null or p_version is null or p_version<0 or p_kind is null or p_kind not in ('network','assignment') or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_network' using errcode='22023';end if;
 if p_kind='network' then
  if not(p_data ?& array['name','supervisor_name','supervisor_person_id','status']) or p_data-array['name','supervisor_name','supervisor_person_id','status']<>'{}'
  or jsonb_typeof(p_data->'supervisor_person_id') not in ('null','string') or exists(select 1 from jsonb_each(p_data)e where e.key<>'supervisor_person_id' and jsonb_typeof(e.value)<>'string')
  or length(btrim(p_data->>'name')) not between 2 and 100 or length(p_data->>'supervisor_name')>120 or (p_data->>'name') ~ '[[:cntrl:]]' or (p_data->>'supervisor_name') ~ '[[:cntrl:]]' or p_data->>'status' not in ('active','archived') then raise exception 'invalid_network' using errcode='22023';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
  select * into previous from public.church_cell_networks where id=p_id for update;
  if previous.id is not null and(previous.organization_id<>p_organization or previous.unit_id<>p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  chosen=(p_data->>'supervisor_person_id')::uuid;chosen_name=btrim(p_data->>'supervisor_name');
  if chosen is not null then
   select full_name into chosen_name from public.people where id=chosen and organization_id=p_organization and unit_id=p_unit and status='active' for share;
   if not found then raise exception 'invalid_network_person' using errcode='22023';end if;
  end if;
  if previous.id is not null then
   if previous.created_by=actor and previous.version=p_version+1 and previous.name=btrim(p_data->>'name') and previous.supervisor_name=chosen_name and previous.supervisor_person_id is not distinct from chosen and previous.status=p_data->>'status' then return jsonb_build_object('id',p_id,'version',previous.version);end if;
   if previous.version<>p_version then raise exception 'network_version_conflict' using errcode='40001';end if;
   update public.church_cell_networks set name=btrim(p_data->>'name'),supervisor_name=chosen_name,supervisor_person_id=chosen,status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning version into new_version;
  else
   if p_version<>0 or p_data->>'status'<>'active' then raise exception 'network_version_conflict' using errcode='40001';end if;
   insert into public.church_cell_networks(id,organization_id,unit_id,name,supervisor_name,supervisor_person_id,status,created_by) values(p_id,p_organization,p_unit,btrim(p_data->>'name'),chosen_name,chosen,'active',actor) returning version into new_version;
  end if;
 else
  if not(p_data ? 'network_id') or p_data-'network_id'<>'{}' or jsonb_typeof(p_data->'network_id') not in ('null','string') then raise exception 'invalid_network' using errcode='22023';end if;
  if not exists(select 1 from public.church_cells where id=p_id and organization_id=p_organization and unit_id=p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  -- Same lock order as the directory writer: advisory cell key, then row lock.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
  perform 1 from public.church_cells where id=p_id and organization_id=p_organization and unit_id=p_unit and status='active' for share;
  if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
  chosen=(p_data->>'network_id')::uuid;
  if chosen is not null then
   perform 1 from public.church_cell_networks where id=chosen and organization_id=p_organization and unit_id=p_unit and status='active' for share;
   if not found then raise exception 'invalid_network_target' using errcode='22023';end if;
  end if;
  select * into link from public.church_cell_network_links where cell_id=p_id for update;
  if link.cell_id is not null and(link.organization_id<>p_organization or link.unit_id<>p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if link.updated_by=actor and link.version=p_version+1 and link.network_id is not distinct from chosen then return jsonb_build_object('id',p_id,'version',link.version);end if;
  if coalesce(link.version,0)<>p_version then raise exception 'network_version_conflict' using errcode='40001';end if;
  insert into public.church_cell_network_links(cell_id,organization_id,unit_id,network_id,updated_by) values(p_id,p_organization,p_unit,chosen,actor)
  on conflict(cell_id) do update set network_id=excluded.network_id,updated_by=excluded.updated_by,version=public.church_cell_network_links.version+1,updated_at=clock_timestamp() returning version into new_version;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,actor,'cell.network_'||p_kind||'_saved','church_cell_network',p_id::text,
 jsonb_build_object('unit_id',p_unit,'version',new_version)||case when p_kind='assignment' then jsonb_build_object('previous_network_id',link.network_id,'network_id',chosen) else jsonb_build_object('status',p_data->>'status','member_linked',chosen is not null) end);
 return jsonb_build_object('id',p_id,'version',new_version);
end $$;
revoke all on function private.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.cell_networks_save(p_organization uuid,p_unit uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.cell_networks_save(p_organization,p_unit,p_kind,p_id,p_version,p_data)$$;
revoke all on function public.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb) to authenticated;

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
 if exists(select 1 from jsonb_each(p_labels)e where e.key<>all(array['inicio','pessoas','familias','aplicativo','kids','igrejas','usuarios','eventos','celulas','escalas','louvor','comunicacao','transmissoes','financeiro','relatorios','configuracoes','celulas.geral','celulas.redes','celulas.supervisor','celulas.singular','celulas.plural','celulas.cadastro','celulas.encontros','celulas.participantes','celulas.visitantes','celulas.relatorios','celulas.categorias','celulas.responsavel','celulas.local'])
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
