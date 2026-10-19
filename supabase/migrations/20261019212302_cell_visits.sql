-- A visit records attendance, not membership, account creation or consent to contact.
create table public.church_cell_visits (
 id uuid primary key, organization_id uuid not null, unit_id uuid not null, cell_id uuid not null,
 person_id uuid, visitor_name text not null check(length(btrim(visitor_name)) between 2 and 120 and visitor_name !~ '[[:cntrl:]]'),
 visit_date date not null check(visit_date between date '1900-01-01' and date '2200-12-31'),
 status text not null check(status in ('recorded','cancelled')),version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id) on delete restrict,
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete restrict
);
create index cell_visits_scope_idx on public.church_cell_visits(organization_id,unit_id,visit_date,id);
create index cell_visits_cell_idx on public.church_cell_visits(cell_id,organization_id,unit_id);
create index cell_visits_person_idx on public.church_cell_visits(person_id,organization_id);
create index cell_visits_actor_idx on public.church_cell_visits(created_by);
-- Prevent double-counting a selected member on the same day; manual names are not identities.
create unique index cell_visits_member_day_idx on public.church_cell_visits(cell_id,person_id,visit_date) where person_id is not null and status='recorded';
alter table public.church_cell_visits enable row level security;
revoke all on public.church_cell_visits from public,anon,authenticated,service_role;
grant select on public.church_cell_visits to authenticated;
create policy cell_visits_read on public.church_cell_visits for select to authenticated
 using(private.cell_people_allowed(organization_id,unit_id));

create function public.cell_visits_read(p_organization uuid,p_unit uuid,p_cell uuid,p_from date,p_to date,p_after uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare items jsonb; next_id uuid;
begin
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from<'1900-01-01' or p_to>'2200-12-31' or p_to<p_from or p_to-p_from>365 then raise exception 'invalid_period' using errcode='22023';end if;
 if p_cell is not null and not exists(select 1 from public.church_cells where id=p_cell and organization_id=p_organization and unit_id=p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]'::jsonb) into items from
 (select id,cell_id,person_id,visitor_name,visit_date,status,version from public.church_cell_visits
 where organization_id=p_organization and unit_id=p_unit and (p_cell is null or cell_id=p_cell)
 and visit_date between p_from and p_to and (p_after is null or id>p_after) order by id limit 101)v;
 if jsonb_array_length(items)>100 then next_id=(items->99->>'id')::uuid;items=items-100;end if;
 return jsonb_build_object('unitId',p_unit,'cellId',p_cell,'items',items,'nextCursor',next_id,
 'canManage',private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]));
end $$;
revoke all on function public.cell_visits_read(uuid,uuid,uuid,date,date,uuid) from public,anon,service_role;
grant execute on function public.cell_visits_read(uuid,uuid,uuid,date,date,uuid) to authenticated;

-- Definer is required for the audited/versioned write: clients have no table write grant.
create function private.cell_visits_save(p_organization uuid,p_unit uuid,p_cell uuid,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid(); previous public.church_cell_visits; saved public.church_cell_visits;
 chosen uuid; chosen_name text; chosen_date date; chosen_status text;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_organization for share;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=actor for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id
 where m.organization_id=p_organization and m.user_id=actor for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_organization and unit_id=p_unit for share;
 if not coalesce(private.cell_people_allowed(p_organization,p_unit),false)
 or not private.has_organization_role(p_organization,array['owner','admin','pastor','leader']::public.membership_role[])
 or not private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_id is null or p_cell is null or p_version is null or p_version<0 or p_data is null or jsonb_typeof(p_data)<>'object'
 or not(p_data ?& array['person_id','visitor_name','visit_date','status']) or p_data-array['person_id','visitor_name','visit_date','status']<>'{}'
 or jsonb_typeof(p_data->'person_id') not in ('null','string')
 or exists(select 1 from jsonb_each(p_data)e where e.key<>'person_id' and jsonb_typeof(e.value)<>'string')
 then raise exception 'invalid_visit' using errcode='22023';end if;
 perform 1 from public.church_cells where id=p_cell and organization_id=p_organization and unit_id=p_unit and status='active' for share;
 if not found then raise exception 'cell_access_denied' using errcode='42501';end if;
 chosen=(p_data->>'person_id')::uuid;chosen_name=btrim(p_data->>'visitor_name');chosen_status=p_data->>'status';
 if p_data->>'visit_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_visit' using errcode='22023';end if;
 chosen_date=(p_data->>'visit_date')::date;
 if chosen_date<'1900-01-01' or chosen_date>'2200-12-31' or chosen_date>(current_timestamp at time zone 'America/Sao_Paulo')::date
 or chosen_status not in ('recorded','cancelled') or length(chosen_name) not between 2 and 120 or chosen_name ~ '[[:cntrl:]]' then raise exception 'invalid_visit' using errcode='22023';end if;
 if chosen is not null then
  select full_name into chosen_name from public.people where id=chosen and organization_id=p_organization and unit_id=p_unit and status='active' for share;
  if not found then raise exception 'invalid_visit_person' using errcode='22023';end if;
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into previous from public.church_cell_visits where id=p_id for update;
 if previous.id is not null then
  if previous.organization_id<>p_organization or previous.unit_id<>p_unit or previous.cell_id<>p_cell then raise exception 'cell_access_denied' using errcode='42501';end if;
  -- A retry is accepted only if exactly the same actor, version and content were committed.
  if previous.created_by=actor and previous.version=p_version+1 and previous.person_id is not distinct from chosen and previous.visitor_name=chosen_name and previous.visit_date=chosen_date and previous.status=chosen_status then
   return jsonb_build_object('id',previous.id,'version',previous.version);
  end if;
  if previous.version<>p_version then raise exception 'visit_version_conflict' using errcode='40001';end if;
  update public.church_cell_visits set person_id=chosen,visitor_name=chosen_name,visit_date=chosen_date,status=chosen_status,version=version+1,updated_at=clock_timestamp() where id=p_id returning * into saved;
 else
  if p_version<>0 or chosen_status<>'recorded' then raise exception 'visit_version_conflict' using errcode='40001';end if;
  insert into public.church_cell_visits(id,organization_id,unit_id,cell_id,person_id,visitor_name,visit_date,status,created_by)
  values(p_id,p_organization,p_unit,p_cell,chosen,chosen_name,chosen_date,chosen_status,actor) returning * into saved;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,actor,case when p_version=0 then 'cell.visit_created' else 'cell.visit_updated' end,'church_cell_visit',saved.id::text,
 jsonb_build_object('unit_id',p_unit,'cell_id',p_cell,'version',saved.version,'status',saved.status,'member_linked',saved.person_id is not null));
 return jsonb_build_object('id',saved.id,'version',saved.version);
end $$;
revoke all on function private.cell_visits_save(uuid,uuid,uuid,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.cell_visits_save(uuid,uuid,uuid,uuid,integer,jsonb) to authenticated;
-- Exposed API is an invoker wrapper; privileged implementation stays outside the API schema.
create function public.cell_visits_save(p_organization uuid,p_unit uuid,p_cell uuid,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$
 select private.cell_visits_save(p_organization,p_unit,p_cell,p_id,p_version,p_data);
$$;
revoke all on function public.cell_visits_save(uuid,uuid,uuid,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.cell_visits_save(uuid,uuid,uuid,uuid,integer,jsonb) to authenticated;

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
 if exists(select 1 from jsonb_each(p_labels)e where e.key<>all(array['inicio','pessoas','familias','aplicativo','kids','igrejas','usuarios','eventos','celulas','escalas','louvor','comunicacao','transmissoes','financeiro','relatorios','configuracoes','celulas.geral','celulas.singular','celulas.plural','celulas.cadastro','celulas.encontros','celulas.participantes','celulas.visitantes','celulas.relatorios','celulas.categorias','celulas.responsavel','celulas.local'])
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
