-- First slice only: directory, not meetings/attendance. No direct client writes.
-- Production receipt: Supabase Vinha Igrejas 20261019094950.
create table public.church_cells (
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete restrict,
 unit_id uuid not null references public.organization_units(id) on delete restrict,
 name text not null check(length(btrim(name)) between 2 and 120),
 leader_name text not null default '' check(length(leader_name)<=120),
 meeting_day smallint not null check(meeting_day between 0 and 6),
 meeting_time text not null check(meeting_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
 meeting_format text not null check(meeting_format in ('presential','online','hybrid')),
 location text not null default '' check(length(location)<=300),
 status text not null default 'active' check(status in ('active','archived')),
 version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index church_cells_directory_idx on public.church_cells(organization_id,unit_id,id);
create index church_cells_unit_idx on public.church_cells(unit_id);
create index church_cells_actor_idx on public.church_cells(created_by);
alter table public.church_cells enable row level security;
revoke all on public.church_cells from public,anon,authenticated,service_role;
grant select on public.church_cells to authenticated;

create function private.cell_directory_allowed(p_organization uuid,p_unit uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null
 and private.has_organization_role(p_organization,array['owner','admin','pastor','leader','secretary']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit)
 and private.target_unit_module_enabled(p_organization,p_unit,'cells')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id
 where u.id=p_unit and u.organization_id=p_organization and u.status='active' and o.status in ('active','trial'));
$$;
revoke all on function private.cell_directory_allowed(uuid,uuid) from public,anon,service_role;
grant execute on function private.cell_directory_allowed(uuid,uuid) to authenticated;
create policy church_cells_read on public.church_cells for select to authenticated
 using(private.cell_directory_allowed(organization_id,unit_id));

create function public.cell_directory_list(p_organization uuid,p_unit uuid,p_after uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; next_id uuid;
begin
 if not coalesce(private.cell_directory_allowed(p_organization,p_unit),false) then
  raise exception 'cell_access_denied' using errcode='42501';
 end if;
 -- Keyset paging is bounded; the directory never exposes another unit.
 select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]'::jsonb) into result from
 (select id,name,leader_name,meeting_day,meeting_time,meeting_format,location,status,version
  from public.church_cells where organization_id=p_organization and unit_id=p_unit
  and (p_after is null or id>p_after) order by id limit 101)c;
 if jsonb_array_length(result)>100 then next_id=(result->99->>'id')::uuid;result=result-100;end if;
 return jsonb_build_object('unitId',p_unit,'items',result,'nextCursor',next_id,
 'canManage',private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]));
end $$;
revoke all on function public.cell_directory_list(uuid,uuid,uuid) from public,anon,service_role;
grant execute on function public.cell_directory_list(uuid,uuid,uuid) to authenticated;

-- Definer is necessary only for atomic, audited writes: clients have SELECT only.
create function public.cell_directory_save(p_organization uuid,p_unit uuid,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_cell public.church_cells; saved public.church_cells; actor uuid=auth.uid();
begin
 perform private.require_confirmed_self_service_email();
 -- Serialize state/access revocations with this operation before authorization.
 perform 1 from public.organizations where id=p_organization for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_organization for share;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=actor for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id
 where m.organization_id=p_organization and m.user_id=actor for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_organization and unit_id=p_unit for share;
 if not coalesce(private.cell_directory_allowed(p_organization,p_unit),false)
 or not private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 or not private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]) then
  raise exception 'cell_access_denied' using errcode='42501';
 end if;
 if p_id is null or p_version is null or p_version<0 or p_data is null or jsonb_typeof(p_data)<>'object'
 or not(p_data ?& array['name','leader_name','meeting_day','meeting_time','meeting_format','location','status'])
 or p_data - array['name','leader_name','meeting_day','meeting_time','meeting_format','location','status'] <> '{}'::jsonb
 or exists(select 1 from jsonb_each(p_data)e where (e.key='meeting_day' and (jsonb_typeof(e.value)<>'number' or e.value::text !~ '^[0-6]$'))
 or (e.key<>'meeting_day' and jsonb_typeof(e.value)<>'string')) then
  raise exception 'invalid_cell_input' using errcode='22023';
 end if;
 -- Advisory key serializes initial insert/retry without broad table locks.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into current_cell from public.church_cells where id=p_id for update;
 if found then
  if current_cell.organization_id<>p_organization or current_cell.unit_id<>p_unit then raise exception 'cell_access_denied' using errcode='42501';end if;
  if p_version=0 and current_cell.created_by=actor and current_cell.version=1
  and (to_jsonb(current_cell)-array['id','organization_id','unit_id','version','created_by','created_at','updated_at'])=p_data then
   return jsonb_build_object('id',current_cell.id,'version',current_cell.version);
  end if;
  if current_cell.version<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
  update public.church_cells set name=btrim(p_data->>'name'),leader_name=btrim(p_data->>'leader_name'),meeting_day=(p_data->>'meeting_day')::smallint,
   meeting_time=p_data->>'meeting_time',meeting_format=p_data->>'meeting_format',location=btrim(p_data->>'location'),status=p_data->>'status',
   version=version+1,updated_at=clock_timestamp() where id=p_id returning * into saved;
 else
  if p_version<>0 or p_data->>'status'<>'active' then raise exception 'cell_version_conflict' using errcode='40001';end if;
  insert into public.church_cells(id,organization_id,unit_id,name,leader_name,meeting_day,meeting_time,meeting_format,location,status,created_by)
   values(p_id,p_organization,p_unit,btrim(p_data->>'name'),btrim(p_data->>'leader_name'),(p_data->>'meeting_day')::smallint,
   p_data->>'meeting_time',p_data->>'meeting_format',btrim(p_data->>'location'),'active',actor) returning * into saved;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,actor,case when p_version=0 then 'cell.created' else 'cell.updated' end,'church_cell',saved.id::text,
 jsonb_build_object('unit_id',p_unit,'version',saved.version,'status',saved.status));
 return jsonb_build_object('id',saved.id,'version',saved.version);
end $$;
revoke all on function public.cell_directory_save(uuid,uuid,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_directory_save(uuid,uuid,uuid,integer,jsonb) to authenticated;
