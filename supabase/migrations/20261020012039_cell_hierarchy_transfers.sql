-- Additive APIs: existing network and participant clients keep their contracts.
create table private.cell_hierarchy_guards (
 unit_id uuid primary key references public.organization_units(id) on delete restrict, version bigint not null default 1
);
revoke all on private.cell_hierarchy_guards from public,anon,authenticated,service_role;
create table public.church_cell_network_parents (
 network_id uuid primary key, organization_id uuid not null,unit_id uuid not null,parent_id uuid,
 version integer not null default 1 check(version>0),updated_by uuid not null references auth.users(id) on delete restrict,updated_at timestamptz not null default now(),
 check(parent_id is distinct from network_id),
 foreign key(network_id,organization_id,unit_id) references public.church_cell_networks(id,organization_id,unit_id) on delete restrict,
 foreign key(parent_id,organization_id,unit_id) references public.church_cell_networks(id,organization_id,unit_id) on delete restrict
);
create index cell_parents_child_fk_idx on public.church_cell_network_parents(network_id,organization_id,unit_id);
create index cell_parents_parent_fk_idx on public.church_cell_network_parents(parent_id,organization_id,unit_id);
create index cell_parents_scope_idx on public.church_cell_network_parents(organization_id,unit_id);
create index cell_parents_actor_idx on public.church_cell_network_parents(updated_by);
create table public.church_cell_transfers (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,source_id uuid not null,source_cell_id uuid not null,
 target_cell_id uuid not null,person_id uuid not null,source_version integer not null check(source_version>0),
 status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled')),
 version integer not null default 1 check(version>0),requested_by uuid not null references auth.users(id) on delete restrict,
 decided_by uuid references auth.users(id) on delete restrict,created_at timestamptz not null default now(),resolved_at timestamptz,
 check(source_cell_id<>target_cell_id),check((status='pending')=(resolved_at is null)),check((status='pending')=(decided_by is null)),
 foreign key(source_id,source_cell_id,organization_id,unit_id) references public.church_cell_participants(id,cell_id,organization_id,unit_id) on delete restrict,
 foreign key(target_cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete restrict
);
create unique index cell_transfers_pending_idx on public.church_cell_transfers(source_id) where status='pending';
create index cell_transfers_source_fk_idx on public.church_cell_transfers(source_id,source_cell_id,organization_id,unit_id);
create index cell_transfers_target_fk_idx on public.church_cell_transfers(target_cell_id,organization_id,unit_id);
create index cell_transfers_person_fk_idx on public.church_cell_transfers(person_id,organization_id);
create index cell_transfers_scope_idx on public.church_cell_transfers(organization_id,unit_id,id);
create index cell_transfers_requester_idx on public.church_cell_transfers(requested_by);
create index cell_transfers_decider_idx on public.church_cell_transfers(decided_by);
alter table public.church_cell_network_parents enable row level security;
alter table public.church_cell_transfers enable row level security;
revoke all on public.church_cell_network_parents,public.church_cell_transfers from public,anon,authenticated,service_role;
grant select on public.church_cell_network_parents,public.church_cell_transfers to authenticated;
create policy cell_parents_read on public.church_cell_network_parents for select to authenticated using(private.cell_people_allowed(organization_id,unit_id));
create policy cell_transfers_read on public.church_cell_transfers for select to authenticated using(private.cell_people_allowed(organization_id,unit_id) and private.can_view_person(person_id));

-- Mirrors existing explicit unit grants; selecting a network supervisor never grants access.
create function private.cell_flow_manager(p_org uuid,p_unit uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_memberships m where m.organization_id=p_org and m.user_id=p_actor and m.status='active'
 and m.role in ('owner','admin','pastor','leader') and (
 m.role in ('owner','admin','pastor') or exists(
 with recursive ancestors as (
 select id,parent_unit_id from public.organization_units where id=p_unit and organization_id=p_org
 union select u.id,u.parent_unit_id from public.organization_units u join ancestors a on a.parent_unit_id=u.id where u.organization_id=p_org)
 select 1 from public.membership_unit_access a join ancestors u on u.id=a.unit_id where a.membership_id=m.id and a.access_level in ('manage','admin') and(a.unit_id=p_unit or a.include_children))))
$$;
revoke all on function private.cell_flow_manager(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function public.cell_flows_read(p_organization uuid,p_unit uuid,p_kind text,p_after uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare items jsonb;next_id uuid;
begin
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_kind is null or p_kind not in ('hierarchy','transfers') then raise exception 'invalid_cell_flow' using errcode='22023';end if;
 if p_kind='hierarchy' then
 with scoped_networks as materialized(select id,name,status from public.church_cell_networks where organization_id=p_organization and unit_id=p_unit),
 scoped_parents as materialized(select network_id,parent_id,version from public.church_cell_network_parents where organization_id=p_organization and unit_id=p_unit)
 select coalesce(jsonb_agg(to_jsonb(n) order by n.id),'[]') into items from (
 select n.id,n.name,n.status,e.parent_id,p.name as parent_name,coalesce(e.version,0) as version,
 (with recursive path(id,parent_id,names,seen) as (
 select n.id,e.parent_id,array[n.name],array[n.id]
 union all select a.id,b.parent_id,array[a.name]||path.names,path.seen||a.id from path
 join scoped_networks a on a.id=path.parent_id
 left join scoped_parents b on b.network_id=a.id
 where not a.id=any(path.seen) and cardinality(path.seen)<32)
 select array_to_string(names,' → ') from path order by cardinality(seen) desc limit 1) as path
 from scoped_networks n left join scoped_parents e on e.network_id=n.id
 left join scoped_networks p on p.id=e.parent_id
 where(p_after is null or n.id>p_after) order by n.id limit 101)n;
 else
 select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]') into items from (
 select t.id,t.source_id,t.source_cell_id,t.target_cell_id,s.name as source_name,d.name as target_name,t.person_id,p.full_name as person_name,
 t.source_version,t.status,t.version,t.created_at,t.resolved_at,(t.requested_by=auth.uid()) as can_cancel
 from public.church_cell_transfers t join public.church_cells s on s.id=t.source_cell_id join public.church_cells d on d.id=t.target_cell_id
 join public.people p on p.id=t.person_id and private.can_view_person(p.id)
 where t.organization_id=p_organization and t.unit_id=p_unit and(p_after is null or t.id>p_after) order by t.id limit 101)t;
 end if;
 if jsonb_array_length(items)>100 then next_id=(items->99->>'id')::uuid;items=items-100;end if;
 return jsonb_build_object('unitId',p_unit,'kind',p_kind,'items',items,'nextCursor',next_id,'canManage',
 private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[]) and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]));
end $$;
revoke all on function public.cell_flows_read(uuid,uuid,text,uuid) from public,anon,service_role;
grant execute on function public.cell_flows_read(uuid,uuid,text,uuid) to authenticated;

create function private.cell_flows_save(p_organization uuid,p_unit uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid();edge public.church_cell_network_parents;transfer public.church_cell_transfers;
 source public.church_cell_participants;destination public.church_cell_participants;chosen uuid;v integer;d integer;h integer;new_status text;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_organization for share;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=actor for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_organization and m.user_id=actor for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_organization and unit_id=p_unit for share;
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false) or not private.cell_flow_manager(p_organization,p_unit,actor) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_id is null or p_version is null or p_version<0 or p_kind is null or p_kind not in ('hierarchy','request','accept','reject','cancel') or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_cell_flow' using errcode='22023';end if;
 if p_kind='hierarchy' then
  if not(p_data?'parent_id') or p_data-'parent_id'<>'{}' or jsonb_typeof(p_data->'parent_id') not in ('string','null') then raise exception 'invalid_cell_flow' using errcode='22023';end if;
  chosen=(p_data->>'parent_id')::uuid;
  -- Updating a real guard row also rejects stale repeatable-read/serializable snapshots.
  insert into private.cell_hierarchy_guards(unit_id) values(p_unit) on conflict(unit_id) do update set version=private.cell_hierarchy_guards.version+1;
  perform 1 from public.church_cell_networks where id in(p_id,chosen) and organization_id=p_organization and unit_id=p_unit order by id for share;
  if not exists(select 1 from public.church_cell_networks where id=p_id and organization_id=p_organization and unit_id=p_unit and status='active')
  or chosen is not null and not exists(select 1 from public.church_cell_networks where id=chosen and organization_id=p_organization and unit_id=p_unit and status='active') then raise exception 'cell_access_denied' using errcode='42501';end if;
  select * into edge from public.church_cell_network_parents where network_id=p_id for update;
  if edge.updated_by=actor and edge.version=p_version+1 and edge.parent_id is not distinct from chosen then return jsonb_build_object('id',p_id,'version',edge.version);end if;
  if coalesce(edge.version,0)<>p_version then raise exception 'cell_flow_conflict' using errcode='40001';end if;
  if chosen is not null then
   if exists(with recursive ancestors(id) as (select chosen union select e.parent_id from public.church_cell_network_parents e join ancestors a on e.network_id=a.id where e.parent_id is not null) select 1 from ancestors where id=p_id) then raise exception 'cell_hierarchy_cycle' using errcode='22023';end if;
   with recursive path(id,depth) as (select chosen,1 union all select e.parent_id,path.depth+1 from path join public.church_cell_network_parents e on e.network_id=path.id where e.parent_id is not null and path.depth<=32) select max(depth) into d from path;
  else d=0;end if;
  with recursive children(id,depth) as (select p_id,1 union all select e.network_id,c.depth+1 from children c join public.church_cell_network_parents e on e.parent_id=c.id where c.depth<=32) select max(depth) into h from children;
  if d+h>32 then raise exception 'cell_hierarchy_depth' using errcode='22023';end if;
  insert into public.church_cell_network_parents(network_id,organization_id,unit_id,parent_id,updated_by) values(p_id,p_organization,p_unit,chosen,actor)
  on conflict(network_id) do update set parent_id=excluded.parent_id,updated_by=excluded.updated_by,version=public.church_cell_network_parents.version+1,updated_at=clock_timestamp() returning version into v;
 else
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cell-transfer:'||p_id::text,0));
  select * into transfer from public.church_cell_transfers where id=p_id for update;
  if transfer.id is not null and(transfer.organization_id<>p_organization or transfer.unit_id<>p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
  if p_kind='request' then
   if not(p_data?&array['source_id','target_cell_id','source_version']) or p_data-array['source_id','target_cell_id','source_version']<>'{}'
   or jsonb_typeof(p_data->'source_id')<>'string' or jsonb_typeof(p_data->'target_cell_id')<>'string'
   or jsonb_typeof(p_data->'source_version')<>'number' or (p_data->>'source_version') !~ '^[1-9][0-9]*$' or p_version<>0 then raise exception 'invalid_cell_flow' using errcode='22023';end if;
   if transfer.id is not null then
    if transfer.requested_by=actor and transfer.source_id=(p_data->>'source_id')::uuid and transfer.target_cell_id=(p_data->>'target_cell_id')::uuid and transfer.source_version=(p_data->>'source_version')::integer then return jsonb_build_object('id',p_id,'version',transfer.version);end if;
    raise exception 'cell_flow_conflict' using errcode='40001';
   end if;
   select * into source from public.church_cell_participants where id=(p_data->>'source_id')::uuid and organization_id=p_organization and unit_id=p_unit;
   if source.id is null then raise exception 'cell_access_denied' using errcode='42501';end if;
   chosen=(p_data->>'target_cell_id')::uuid;
  else
   if p_data<>'{}' or transfer.id is null then raise exception 'invalid_cell_flow' using errcode='22023';end if;
   new_status=case p_kind when 'accept' then 'accepted' when 'reject' then 'rejected' else 'cancelled' end;
   if transfer.status=new_status and transfer.version=p_version+1 and transfer.decided_by=actor then return jsonb_build_object('id',p_id,'version',transfer.version);end if;
   if transfer.status<>'pending' or transfer.version<>p_version then raise exception 'cell_flow_conflict' using errcode='40001';end if;
   if p_kind='cancel' and transfer.requested_by<>actor then raise exception 'cell_access_denied' using errcode='42501';end if;
   select * into source from public.church_cell_participants where id=transfer.source_id;
   chosen=transfer.target_cell_id;
  end if;
  -- Stable order; no cell advisory lock is acquired after a row lock.
  perform 1 from public.church_cells where id in(source.cell_id,chosen) and organization_id=p_organization and unit_id=p_unit order by id for update;
  if p_kind in ('request','accept') then
   if source.cell_id=chosen or (select count(*) from public.church_cells where id in(source.cell_id,chosen) and organization_id=p_organization and unit_id=p_unit and status='active')<>2 then raise exception 'cell_access_denied' using errcode='42501';end if;
   select * into source from public.church_cell_participants where id=source.id for update;
   if source.status<>'active' or source.version<>(case when p_kind='request' then (p_data->>'source_version')::integer else transfer.source_version end) then raise exception 'cell_flow_conflict' using errcode='40001';end if;
   perform 1 from public.people where id=source.person_id and organization_id=p_organization and unit_id=p_unit and status='active' and private.can_view_person(id) for share;
   if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
   select * into destination from public.church_cell_participants where cell_id=chosen and person_id=source.person_id for update;
   if destination.status='active' then raise exception 'cell_flow_conflict' using errcode='40001';end if;
  end if;
  if p_kind='request' then
   insert into public.church_cell_transfers(id,organization_id,unit_id,source_id,source_cell_id,target_cell_id,person_id,source_version,requested_by)
   values(p_id,p_organization,p_unit,source.id,source.cell_id,chosen,source.person_id,source.version,actor) returning version into v;
  else
   if p_kind='accept' then
    -- Revalidate the issuer, without trusting a snapshot of its previous role.
    perform 1 from public.organization_memberships where organization_id=p_organization and user_id=transfer.requested_by for share;
    perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_organization and m.user_id=transfer.requested_by for share of a;
    if not private.cell_flow_manager(p_organization,p_unit,transfer.requested_by) then raise exception 'cell_access_denied' using errcode='42501';end if;
    update public.church_cell_participants set status='inactive',version=version+1,updated_at=clock_timestamp() where id=source.id;
    if destination.id is null then
     insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values(extensions.gen_random_uuid(),p_organization,p_unit,chosen,source.person_id,'active',actor);
    else
     update public.church_cell_participants set status='active',version=version+1,updated_at=clock_timestamp() where id=destination.id;
    end if;
   end if;
   update public.church_cell_transfers set status=new_status,version=version+1,decided_by=actor,resolved_at=clock_timestamp() where id=p_id returning version into v;
  end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,actor,'cell.flow_'||p_kind,'church_cell_flow',p_id::text,jsonb_build_object('unit_id',p_unit,'version',v)||
 case when p_kind='hierarchy' then jsonb_build_object('previous_parent_id',edge.parent_id,'parent_id',chosen) else jsonb_build_object('source_id',source.id,'target_cell_id',chosen) end);
 return jsonb_build_object('id',p_id,'version',v);
end $$;
revoke all on function private.cell_flows_save(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.cell_flows_save(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.cell_flows_save(p_organization uuid,p_unit uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.cell_flows_save(p_organization,p_unit,p_kind,p_id,p_version,p_data)$$;
revoke all on function public.cell_flows_save(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_flows_save(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
