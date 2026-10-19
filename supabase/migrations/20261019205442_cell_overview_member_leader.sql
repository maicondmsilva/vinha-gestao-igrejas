-- Optional member identity; manual names remain valid and create no member/account.
alter table public.church_cells add column leader_person_id uuid;
alter table public.church_cells add constraint church_cells_leader_person_fk foreign key(leader_person_id,organization_id) references public.people(id,organization_id) on delete restrict;
create index church_cells_leader_person_idx on public.church_cells(leader_person_id,organization_id);
create function public.cell_directory_list_v2(p_organization uuid,p_unit uuid,p_after uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; next_id uuid;
begin
 if not coalesce(private.cell_directory_allowed(p_organization,p_unit),false) then
  raise exception 'cell_access_denied' using errcode='42501';
 end if;
 -- Keyset paging is bounded; the directory never exposes another unit.
 select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]'::jsonb) into result from
 (select id,name,leader_name,leader_person_id,meeting_day,meeting_time,meeting_format,location,status,version
  from public.church_cells where organization_id=p_organization and unit_id=p_unit
  and (p_after is null or id>p_after) order by id limit 101)c;
 if jsonb_array_length(result)>100 then next_id=(result->99->>'id')::uuid;result=result-100;end if;
 return jsonb_build_object('unitId',p_unit,'items',result,'nextCursor',next_id,
 'canManage',private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]));
end $$;
revoke all on function public.cell_directory_list_v2(uuid,uuid,uuid) from public,anon,service_role;
grant execute on function public.cell_directory_list_v2(uuid,uuid,uuid) to authenticated;


create or replace function public.cell_directory_save(p_organization uuid,p_unit uuid,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_cell public.church_cells; saved public.church_cells; actor uuid=auth.uid(); chosen_person uuid; chosen_name text;
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
 or p_data - array['leader_person_id','name','leader_name','meeting_day','meeting_time','meeting_format','location','status'] <> '{}'::jsonb
 or exists(select 1 from jsonb_each(p_data)e where (e.key='meeting_day' and (jsonb_typeof(e.value)<>'number' or e.value::text !~ '^[0-6]$'))
 or (e.key not in ('meeting_day','leader_person_id') and jsonb_typeof(e.value)<>'string') or (e.key='leader_person_id' and jsonb_typeof(e.value) not in ('null','string'))) then
  raise exception 'invalid_cell_input' using errcode='22023';
 end if;
 -- Advisory key serializes initial insert/retry without broad table locks.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into current_cell from public.church_cells where id=p_id for update;
 if current_cell.id is not null and (current_cell.organization_id<>p_organization or current_cell.unit_id<>p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_data ? 'leader_person_id' then chosen_person=(p_data->>'leader_person_id')::uuid;
 elsif current_cell.id is not null and current_cell.leader_name=btrim(p_data->>'leader_name') then chosen_person=current_cell.leader_person_id;end if;
 if chosen_person is not null then
  if not coalesce(private.cell_people_allowed(p_organization,p_unit),false) then raise exception 'cell_people_denied' using errcode='42501';end if;
  select full_name into chosen_name from public.people where id=chosen_person and organization_id=p_organization and unit_id=p_unit and status='active' for share;
  if not found then raise exception 'invalid_leader' using errcode='22023';end if;
  p_data=jsonb_set(p_data,'{leader_name}',to_jsonb(chosen_name));
 end if;
 if current_cell.id is not null then
  if current_cell.organization_id<>p_organization or current_cell.unit_id<>p_unit then raise exception 'cell_access_denied' using errcode='42501';end if;
  if p_version=0 and current_cell.created_by=actor and current_cell.version=1
  and (to_jsonb(current_cell)-array['id','organization_id','unit_id','version','created_by','created_at','updated_at','leader_person_id'])=(p_data-'leader_person_id') and current_cell.leader_person_id is not distinct from chosen_person then
   return jsonb_build_object('id',current_cell.id,'version',current_cell.version);
  end if;
  if current_cell.version<>p_version then raise exception 'cell_version_conflict' using errcode='40001';end if;
  update public.church_cells set name=btrim(p_data->>'name'),leader_name=btrim(p_data->>'leader_name'),leader_person_id=chosen_person,meeting_day=(p_data->>'meeting_day')::smallint,
   meeting_time=p_data->>'meeting_time',meeting_format=p_data->>'meeting_format',location=btrim(p_data->>'location'),status=p_data->>'status',
   version=version+1,updated_at=clock_timestamp() where id=p_id returning * into saved;
 else
  if p_version<>0 or p_data->>'status'<>'active' then raise exception 'cell_version_conflict' using errcode='40001';end if;
  insert into public.church_cells(id,organization_id,unit_id,name,leader_name,leader_person_id,meeting_day,meeting_time,meeting_format,location,status,created_by)
   values(p_id,p_organization,p_unit,btrim(p_data->>'name'),btrim(p_data->>'leader_name'),chosen_person,(p_data->>'meeting_day')::smallint,
   p_data->>'meeting_time',p_data->>'meeting_format',btrim(p_data->>'location'),'active',actor) returning * into saved;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,actor,case when p_version=0 then 'cell.created' else 'cell.updated' end,'church_cell',saved.id::text,
 jsonb_build_object('unit_id',p_unit,'version',saved.version,'status',saved.status,'leader_linked',saved.leader_person_id is not null));
 return jsonb_build_object('id',saved.id,'version',saved.version);
end $$;
revoke all on function public.cell_directory_save(uuid,uuid,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_directory_save(uuid,uuid,uuid,integer,jsonb) to authenticated;

create function public.cell_overview(p_organization uuid,p_unit uuid,p_month date default current_date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare start_day date=date_trunc('month',p_month)::date; end_day date=(date_trunc('month',p_month)+interval '1 month')::date; previous_day date=(date_trunc('month',p_month)-interval '1 month')::date; result jsonb;
begin
 if p_month is null or p_month<'1900-01-01' or p_month>'2200-12-31' then raise exception 'invalid_period' using errcode='22023';end if;
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false) then raise exception 'cell_access_denied' using errcode='42501';end if;
 with scoped as (select * from public.church_cells where organization_id=p_organization and unit_id=p_unit),
 meetings as (select * from public.church_cell_meetings where organization_id=p_organization and unit_id=p_unit and meeting_date>=previous_day and meeting_date<end_day and status='completed'),
 counts as (select count(*) filter(where meeting_date>=start_day) as completed,count(*) filter(where meeting_date<start_day) as previous_completed from meetings),
 attendance as (select count(*) filter(where m.meeting_date>=start_day) as expected,count(*) filter(where m.meeting_date>=start_day and a.present) as present,count(*) filter(where m.meeting_date<start_day) as previous_expected,count(*) filter(where m.meeting_date<start_day and a.present) as previous_present from meetings m join public.church_cell_attendance a on a.meeting_id=m.id and a.cell_id=m.cell_id and a.organization_id=m.organization_id and a.unit_id=m.unit_id)
 select jsonb_build_object('unitId',p_unit,'month',start_day,
 'active',(select count(*) from scoped where status='active'),
 'newCells',(select count(*) from scoped where created_at>=start_day and created_at<end_day),
 'previousNewCells',(select count(*) from scoped where created_at>=previous_day and created_at<start_day),
 'participants',(select count(distinct person_id) from public.church_cell_participants where organization_id=p_organization and unit_id=p_unit and status='active'),
 'completed',counts.completed,'previousCompleted',counts.previous_completed,
 'expected',attendance.expected,'present',attendance.present,'previousExpected',attendance.previous_expected,'previousPresent',attendance.previous_present,
 'pending',(select count(*) from public.church_cell_meetings where organization_id=p_organization and unit_id=p_unit and status='scheduled' and meeting_date<current_date),
 'series',(select coalesce(jsonb_agg(jsonb_build_object('date',d.day::date,'meetings',(select count(*) from meetings m where m.meeting_date=d.day::date)) order by d.day),'[]'::jsonb) from generate_series(start_day::timestamp,(end_day-1)::timestamp,interval '1 day') d(day))) into result from counts cross join attendance;
 return result;
end $$;
revoke all on function public.cell_overview(uuid,uuid,date) from public,anon,service_role;
grant execute on function public.cell_overview(uuid,uuid,date) to authenticated;

-- Minimal reusable member lookup: no contacts/documents; caller remains subject to people RLS.
create function public.member_choices(p_organization uuid,p_unit uuid,p_search text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare rows jsonb;
begin
 if p_search is null or length(btrim(p_search))<2 or length(p_search)>80 then raise exception 'invalid_search' using errcode='22023';end if;
 if auth.uid() is null
 or not private.has_organization_role(p_organization,array['owner','admin','pastor','leader','secretary']::public.membership_role[])
 or not private.can_access_unit(p_organization,p_unit)
 or not private.target_unit_module_enabled(p_organization,p_unit,'people')
 or not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_organization and u.status='active' and o.status in ('active','trial')) then raise exception 'member_lookup_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name,id),'[]'::jsonb) into rows from
 (select id,full_name from public.people where organization_id=p_organization and unit_id=p_unit and status='active' and strpos(lower(full_name),lower(btrim(p_search)))>0 order by full_name,id limit 31)p;
 return jsonb_build_object('unitId',p_unit,'hasMore',jsonb_array_length(rows)>30,'items',case when jsonb_array_length(rows)>30 then rows-30 else rows end);
end $$;
revoke all on function public.member_choices(uuid,uuid,text) from public,anon,service_role;
grant execute on function public.member_choices(uuid,uuid,text) to authenticated;
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
 if exists(select 1 from jsonb_each(p_labels)e where e.key<>all(array['inicio','pessoas','familias','aplicativo','kids','igrejas','usuarios','eventos','celulas','escalas','louvor','comunicacao','transmissoes','financeiro','relatorios','configuracoes','celulas.geral','celulas.singular','celulas.plural','celulas.cadastro','celulas.encontros','celulas.participantes','celulas.relatorios','celulas.categorias','celulas.responsavel','celulas.local'])
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
