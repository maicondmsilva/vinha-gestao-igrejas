-- Member-facing Kids and life groups. Custody remains an assisted operation.
create table private.member_family_requests(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 user_id uuid not null references auth.users(id),person_id uuid not null,kind text not null check(kind in('kids.create','kids.edit','cell.leave')),
 profile_id uuid,cell_id uuid,data jsonb not null check(jsonb_typeof(data)='object'),nonce text not null,profile_version integer,care_version integer,
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),reason text not null default '',
 version integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id),
 foreign key(profile_id,organization_id,unit_id) references private.kids_profiles(id,organization_id,unit_id),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id),unique(organization_id,user_id,nonce)
);
create index member_family_requests_scope on private.member_family_requests(organization_id,unit_id,status,id);
create index member_family_requests_user on private.member_family_requests(user_id);
create index member_family_requests_person on private.member_family_requests(person_id);
create index member_family_requests_profile on private.member_family_requests(profile_id);
create index member_family_requests_cell on private.member_family_requests(cell_id);
create index member_family_requests_reviewer on private.member_family_requests(reviewed_by);
create unique index member_family_pending_edit on private.member_family_requests(profile_id,user_id) where status='pending' and kind='kids.edit';
create unique index member_family_pending_exit on private.member_family_requests(cell_id,person_id) where status='pending' and kind='cell.leave';
create table private.kids_member_reservations(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null,unit_id uuid not null,session_id uuid not null,group_id uuid not null,
 profile_id uuid not null,user_id uuid not null references auth.users(id),person_id uuid not null,
 status text not null default 'reserved' check(status in('reserved','cancelled')),version integer not null default 1,
 pickup_requested_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(session_id,profile_id),foreign key(session_id,organization_id,unit_id) references private.kids_sessions(id,organization_id,unit_id),
 foreign key(group_id,organization_id,unit_id,session_id) references private.kids_session_rooms(id,organization_id,unit_id,session_id),
 foreign key(profile_id,organization_id,unit_id) references private.kids_profiles(id,organization_id,unit_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create index kids_member_reservations_scope on private.kids_member_reservations(organization_id,unit_id,session_id,group_id,status);
create index kids_member_reservations_profile on private.kids_member_reservations(profile_id);
create index kids_member_reservations_user on private.kids_member_reservations(user_id);
create index kids_member_reservations_person on private.kids_member_reservations(person_id);
create index kids_member_reservations_group on private.kids_member_reservations(group_id);
create table private.cell_app_publications(
 cell_id uuid primary key,organization_id uuid not null,unit_id uuid not null,
 area text not null default '' check(length(area)<=160),description text not null default '' check(length(description)<=2000),
 published boolean not null default false,version integer not null default 1,updated_by uuid not null references auth.users(id),
 foreign key(cell_id,organization_id,unit_id) references public.church_cells(id,organization_id,unit_id)
);
create index cell_app_publications_scope on private.cell_app_publications(organization_id,unit_id);
create index cell_app_publications_actor on private.cell_app_publications(updated_by);
alter table private.member_family_requests enable row level security;
alter table private.kids_member_reservations enable row level security;
alter table private.cell_app_publications enable row level security;
revoke all on private.member_family_requests,private.kids_member_reservations,private.cell_app_publications from public,anon,authenticated,service_role;

-- Contract eligibility for self-service, without granting staff unit access.
create function private.member_family_module(p_org uuid,p_unit uuid,p_module text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare c public.saas_unit_contracts;
begin
 if auth.uid() is null or not private.community_scope(p_org,p_unit) or not exists(select 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active') or not exists(select 1 from public.saas_module_catalog where code=p_module) then return false;end if;
 select * into c from public.saas_unit_contracts where organization_id=p_org and unit_id=p_unit;
 if c.id is null or c.status='draft' then return true;end if;
 if c.status<>'active' then return false;end if;
 if c.module_decisions?p_module then return c.module_decisions->p_module='true'::jsonb;end if;
 return exists(select 1 from public.saas_plan_modules where plan_id=c.plan_id and module_code=p_module and included);
end $$;
revoke all on function private.member_family_module(uuid,uuid,text) from public,anon,authenticated,service_role;
create function private.member_kids_guardian(p_org uuid,p_unit uuid,p_profile uuid,p_person uuid,p_edit boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.kids_profiles k join private.kids_guardians g on g.profile_id=k.id join public.people child on child.id=k.person_id join public.people adult on adult.id=g.person_id
 where k.id=p_profile and k.organization_id=p_org and k.unit_id=p_unit and k.status='active' and k.review_status='approved'
 and child.organization_id=p_org and child.unit_id=p_unit and child.status='active' and child.birth_date<=current_date and child.birth_date>current_date-interval '18 years' and adult.organization_id=p_org and adult.unit_id=p_unit and adult.status='active'
 and adult.birth_date<=current_date-interval '18 years' and g.person_id=p_person and g.status='approved' and (g.valid_until is null or g.valid_until>=current_date)
 and(case when p_edit then g.can_edit else g.can_pickup or g.can_edit end));
$$;
revoke all on function private.member_kids_guardian(uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;

create function private.member_family(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid();person uuid;rows jsonb;children jsonb;reservations jsonb;requests jsonb;v integer;result uuid;chosen uuid;profile private.kids_profiles;room private.kids_session_rooms;session private.kids_sessions;booking private.kids_member_reservations;req private.member_family_requests;cell public.church_cells;present_count integer;reserved_count integer;birth date;month_age integer;
begin
 person=private.community_identity(p_org,p_unit,true);
 if p_unit is null or p_action is null or p_data is null or jsonb_typeof(p_data)<>'object' or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_family' using errcode='22023';end if;
 if p_action not in('cells.list','cells.detail') and not exists(select 1 from public.people where id=person and unit_id=p_unit) then raise exception 'family_local_membership_required' using errcode='42501';end if;
 if not private.member_family_module(p_org,p_unit,'people') then raise exception 'family_denied' using errcode='42501';end if;
 if p_action like 'kids.%' and not private.member_family_module(p_org,p_unit,'kids') then raise exception 'family_denied' using errcode='42501';end if;
 if p_action like 'cells.%' and not private.member_family_module(p_org,p_unit,'cells') then raise exception 'family_denied' using errcode='42501';end if;
 if p_action='kids.list' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into children from(select k.id,p.full_name name,p.birth_date birth,k.version,g.can_edit,g.can_pickup,case when g.can_edit then (select instructions from private.kids_care where profile_id=k.id) else null end care from private.kids_profiles k join public.people p on p.id=k.person_id join private.kids_guardians g on g.profile_id=k.id and g.person_id=person where k.organization_id=p_org and k.unit_id=p_unit and private.member_kids_guardian(p_org,p_unit,k.id,person) order by k.id limit 21 offset p_offset)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into reservations from(select r.id,r.profile_id,r.session_id,r.group_id,r.status,r.version,r.pickup_requested_at,s.name session,s.starts_at,s.ends_at,c.full_name name,exists(select 1 from private.kids_guardians g where g.profile_id=r.profile_id and g.person_id=person and g.can_pickup) can_pickup,
    a.status attendance,a.checked_in_at,a.checked_out_at,rm.name room from private.kids_member_reservations r join private.kids_profiles k on k.id=r.profile_id join public.people c on c.id=k.person_id join private.kids_sessions s on s.id=r.session_id join private.kids_session_rooms sr on sr.id=r.group_id join private.kids_rooms rm on rm.id=sr.room_id left join private.kids_attendance a on a.session_id=r.session_id and a.profile_id=r.profile_id
    where r.organization_id=p_org and r.unit_id=p_unit and private.member_kids_guardian(p_org,p_unit,r.profile_id,person) order by s.starts_at desc,r.id limit 20 offset p_offset)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into requests from(select id,kind,data,status,reason,version,created_at from private.member_family_requests where organization_id=p_org and unit_id=p_unit and user_id=actor and kind like 'kids.%' order by created_at desc,id limit 20 offset p_offset)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select a.id,a.status,a.checked_in_at,a.checked_out_at,c.full_name name,s.name session,rm.name room from private.kids_attendance a join private.kids_profiles k on k.id=a.profile_id join public.people c on c.id=k.person_id join private.kids_sessions s on s.id=a.session_id join private.kids_session_rooms sr on sr.id=a.group_id join private.kids_rooms rm on rm.id=sr.room_id where a.organization_id=p_org and a.unit_id=p_unit and private.member_kids_guardian(p_org,p_unit,a.profile_id,person) order by a.checked_in_at desc,a.id limit 20 offset p_offset)q;
  return jsonb_build_object('children',case when jsonb_array_length(children)>20 then children-20 else children end,'more',jsonb_array_length(children)>20 or jsonb_array_length(reservations)=20 or jsonb_array_length(requests)=20 or jsonb_array_length(rows)=20,'reservations',reservations,'requests',requests,'presence',rows);
 elsif p_action='kids.sessions' then
  if not private.member_kids_guardian(p_org,p_unit,p_id,person) or not exists(select 1 from private.kids_guardians where profile_id=p_id and person_id=person and can_pickup) then raise exception 'family_denied' using errcode='42501';end if;
  select p.birth_date into birth from public.people p join private.kids_profiles k on k.person_id=p.id where k.id=p_id;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select sr.id,s.name,s.starts_at,s.ends_at,rm.name room,cl.name class_name,
   greatest(0,least(sr.capacity,rm.capacity)-sr.occupied-(select count(*) from private.kids_member_reservations r where r.group_id=sr.id and r.status='reserved' and private.member_kids_guardian(r.organization_id,r.unit_id,r.profile_id,r.person_id) and not exists(select 1 from private.kids_attendance a where a.session_id=s.id and a.profile_id=r.profile_id))) available
   from private.kids_sessions s join private.kids_session_rooms sr on sr.session_id=s.id join private.kids_rooms rm on rm.id=sr.room_id join private.kids_classes cl on cl.id=sr.class_id
   where s.organization_id=p_org and s.unit_id=p_unit and s.status='open' and s.ends_at>clock_timestamp() and rm.active and cl.active
   and (extract(year from age((s.starts_at at time zone 'America/Sao_Paulo')::date,birth))*12+extract(month from age((s.starts_at at time zone 'America/Sao_Paulo')::date,birth))) between cl.min_months and cl.max_months order by s.starts_at,sr.id limit 21 offset p_offset)q;
  return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
 elsif p_action='kids.reserve' then
  if p_data-array['profile']<>'{}' or jsonb_typeof(p_data->'profile') is distinct from 'string' then raise exception 'invalid_family' using errcode='22023';end if;
  chosen=(p_data->>'profile')::uuid;
  if not private.member_kids_guardian(p_org,p_unit,chosen,person) or not exists(select 1 from private.kids_guardians where profile_id=chosen and person_id=person and can_pickup) then raise exception 'family_denied' using errcode='42501';end if;
  select * into room from private.kids_session_rooms where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'family_denied' using errcode='42501';end if;
  -- Written row prevents stale repeatable-read snapshots from overbooking.
  update private.kids_session_rooms set version=version+1 where id=room.id;
  select * into session from private.kids_sessions where id=room.session_id and status='open' and ends_at>clock_timestamp() for share;
  if not found then raise exception 'family_closed' using errcode='40001';end if;
  select * into booking from private.kids_member_reservations where session_id=session.id and profile_id=chosen for update;
  if found and booking.status='reserved' then return jsonb_build_object('ok',true,'id',booking.id);end if;
  if exists(select 1 from private.kids_attendance where session_id=session.id and profile_id=chosen) then raise exception 'family_already_received' using errcode='40001';end if;
  select p.birth_date into birth from public.people p join private.kids_profiles k on k.person_id=p.id where k.id=chosen;
  month_age=extract(year from age((session.starts_at at time zone 'America/Sao_Paulo')::date,birth))*12+extract(month from age((session.starts_at at time zone 'America/Sao_Paulo')::date,birth));
  if not exists(select 1 from private.kids_classes where id=room.class_id and active and month_age between min_months and max_months) or not exists(select 1 from private.kids_rooms where id=room.room_id and active) then raise exception 'family_age' using errcode='22023';end if;
  select count(*) into reserved_count from private.kids_member_reservations r where r.group_id=room.id and r.status='reserved' and private.member_kids_guardian(r.organization_id,r.unit_id,r.profile_id,r.person_id) and not exists(select 1 from private.kids_attendance a where a.session_id=session.id and a.profile_id=r.profile_id);
  if room.occupied+reserved_count>=least(room.capacity,(select capacity from private.kids_rooms where id=room.room_id)) then raise exception 'family_full' using errcode='40001';end if;
  insert into private.kids_member_reservations(organization_id,unit_id,session_id,group_id,profile_id,user_id,person_id) values(p_org,p_unit,session.id,room.id,chosen,actor,person)
  on conflict(session_id,profile_id) do update set status='reserved',group_id=excluded.group_id,user_id=actor,person_id=person,version=private.kids_member_reservations.version+1,updated_at=clock_timestamp() returning id into result;
 elsif p_action in('kids.cancel','kids.pickup') then
  select * into booking from private.kids_member_reservations where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found or not private.member_kids_guardian(p_org,p_unit,booking.profile_id,person) or not exists(select 1 from private.kids_guardians where profile_id=booking.profile_id and person_id=person and can_pickup) then raise exception 'family_denied' using errcode='42501';end if;
  if p_data<>'{}' or booking.version is distinct from p_version or booking.status<>'reserved' then raise exception 'family_changed' using errcode='40001';end if;
  if p_action='kids.cancel' then
   if exists(select 1 from private.kids_attendance where session_id=booking.session_id and profile_id=booking.profile_id) then raise exception 'family_already_received' using errcode='40001';end if;
   update private.kids_session_rooms set version=version+1 where id=booking.group_id;
   update private.kids_member_reservations set status='cancelled',version=version+1,updated_at=clock_timestamp() where id=booking.id;
  else
   if not exists(select 1 from private.kids_attendance where session_id=booking.session_id and profile_id=booking.profile_id and status='present') then raise exception 'family_not_present' using errcode='40001';end if;
   update private.kids_member_reservations set pickup_requested_at=coalesce(pickup_requested_at,clock_timestamp()),version=version+1,updated_at=clock_timestamp() where id=booking.id;
  end if;result=booking.id;
 elsif p_action in('kids.create','kids.edit','cells.leave') then
  if length(coalesce(p_data->>'nonce','')) not between 10 and 100 then raise exception 'invalid_family' using errcode='22023';end if;
  if p_action='cells.leave' then
   if p_data-array['nonce']<>'{}' or not exists(select 1 from public.church_cell_participants where cell_id=p_id and person_id=person and organization_id=p_org and unit_id=p_unit and status='active') then raise exception 'family_denied' using errcode='42501';end if;
  else
   if p_data-array['nonce','name','birth','care']<>'{}' or not(p_data?&array['nonce','name','birth','care']) or exists(select 1 from jsonb_each(p_data) where jsonb_typeof(value)<>'string') or length(btrim(p_data->>'name')) not between 2 and 160 or length(p_data->>'care')>2000 then raise exception 'invalid_family' using errcode='22023';end if;
   birth=(p_data->>'birth')::date;
   if birth>current_date or birth<=current_date-interval '18 years' or not exists(select 1 from public.people where id=person and birth_date<=current_date-interval '18 years') then raise exception 'family_age' using errcode='22023';end if;
   if p_action='kids.edit' and not private.member_kids_guardian(p_org,p_unit,p_id,person,true) then raise exception 'family_denied' using errcode='42501';end if;
  end if;
  insert into private.member_family_requests(organization_id,unit_id,user_id,person_id,kind,profile_id,cell_id,data,nonce,profile_version,care_version)
   values(p_org,p_unit,actor,person,case when p_action='cells.leave' then 'cell.leave' else p_action end,case when p_action='kids.edit' then p_id end,case when p_action='cells.leave' then p_id end,p_data-'nonce',p_data->>'nonce',case when p_action='kids.edit' then (select version from private.kids_profiles where id=p_id) end,case when p_action='kids.edit' then coalesce((select version from private.kids_care where profile_id=p_id),0) end) on conflict(organization_id,user_id,nonce) do nothing returning id into result;
  if result is null then select id into result from private.member_family_requests where organization_id=p_org and user_id=actor and nonce=p_data->>'nonce';end if;
 elsif p_action='request.cancel' then
  select * into req from private.member_family_requests where id=p_id and organization_id=p_org and unit_id=p_unit and user_id=actor for update;
  if not found then raise exception 'family_denied' using errcode='42501';end if;
  if p_data<>'{}' or req.version is distinct from p_version or req.status<>'pending' then raise exception 'family_changed' using errcode='40001';end if;
  update private.member_family_requests set status='cancelled',version=version+1,updated_at=clock_timestamp() where id=req.id;result=req.id;
 elsif p_action in('cells.list','cells.detail') then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select c.id,c.name,c.meeting_day,c.meeting_time,c.meeting_format,a.area,a.description,
    exists(select 1 from public.church_cell_participants cp where cp.cell_id=c.id and cp.person_id=person and cp.status='active') joined,
    case when exists(select 1 from public.church_cell_participants cp where cp.cell_id=c.id and cp.person_id=person and cp.status='active') then c.location else '' end location,
    private.cell_plus_cell(p_org,p_unit,c.id,actor,'report') can_report
   from public.church_cells c left join private.cell_app_publications a on a.cell_id=c.id where c.organization_id=p_org and c.unit_id=p_unit and c.status='active'
    and (a.published or exists(select 1 from public.church_cell_participants cp where cp.cell_id=c.id and cp.person_id=person and cp.status='active') or private.cell_plus_cell(p_org,p_unit,c.id,actor,'read'))
    and (p_id is null or c.id=p_id) order by c.id limit 21 offset p_offset)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into requests from(select r.id,r.cell_id,c.name,r.status,r.version,r.created_at from private.cell_referrals r join public.church_cells c on c.id=r.cell_id where r.organization_id=p_org and r.unit_id=p_unit and r.person_id=person and r.created_by=actor order by r.created_at desc,r.id limit 20 offset p_offset)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into children from(select id,cell_id,kind,status,reason,version from private.member_family_requests where organization_id=p_org and unit_id=p_unit and user_id=actor and kind='cell.leave' order by created_at desc,id limit 20 offset p_offset)q;
  reservations='[]';
  if p_action='cells.detail' and exists(select 1 from jsonb_array_elements(rows) x where (x->>'joined')::boolean or (x->>'can_report')::boolean) then
   select coalesce(jsonb_agg(to_jsonb(q)),'[]') into reservations from(select m.id,m.title,m.body,m.url from private.cell_study_materials m where m.organization_id=p_org and m.unit_id=p_unit and m.status='published' and(m.network_id is null or exists(select 1 from public.church_cell_network_links l where l.cell_id=p_id and l.network_id=m.network_id)) order by m.id limit 20 offset p_offset)q;
  end if;
  return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20 or jsonb_array_length(requests)=20 or jsonb_array_length(children)=20 or jsonb_array_length(reservations)=20,'requests',requests,'exits',children,'materials',reservations);
 elsif p_action='cells.join' then
  if p_data<>'{}' then raise exception 'invalid_family' using errcode='22023';end if;
  select * into cell from public.church_cells where id=p_id and organization_id=p_org and unit_id=p_unit and status='active' for update;
  if not found or not exists(select 1 from private.cell_app_publications where cell_id=cell.id and published) then raise exception 'family_denied' using errcode='42501';end if;
  if exists(select 1 from public.church_cell_participants where cell_id=cell.id and person_id=person and status='active') then raise exception 'family_already_joined' using errcode='40001';end if;
  select id into result from private.cell_referrals where cell_id=cell.id and person_id=person and status='pending';
  if result is null then insert into private.cell_referrals(id,organization_id,unit_id,cell_id,person_id,person_name,status,created_by) select extensions.gen_random_uuid(),p_org,p_unit,cell.id,person,p.full_name,'pending',actor from public.people p where p.id=person returning id into result;end if;
 elsif p_action='cells.cancel' then
  if p_data<>'{}' then raise exception 'invalid_family' using errcode='22023';end if;
  update private.cell_referrals set status='rejected',version=version+1,updated_at=clock_timestamp() where id=p_id and organization_id=p_org and unit_id=p_unit and created_by=actor and person_id=person and status='pending' and version=p_version returning id into result;
  if result is null then raise exception 'family_changed' using errcode='40001';end if;
 else raise exception 'invalid_family' using errcode='22023';end if;
 return jsonb_build_object('ok',true,'id',result);
end $$;
revoke all on function private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function public.member_family(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.member_family(p_org,p_unit,p_action,p_id,p_version,p_data,p_offset)$$;
revoke all on function public.member_family(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function public.member_family(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;

create function private.member_family_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;req private.member_family_requests;person public.people;child uuid;profile uuid;answer text;is_kids boolean;v integer;
begin
 perform private.community_identity(p_org,p_unit,false);
 is_kids=p_action in('kids.requests','kids.review','kids.reception');
 if p_unit is null or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) or
 (is_kids and not private.kids_allowed(p_org,p_unit,'approve')) or
 (not is_kids and not private.cell_flow_manager(p_org,p_unit,auth.uid())) then raise exception 'family_denied' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_family' using errcode='22023';end if;
 if p_action in('kids.requests','cells.requests') then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select r.id,r.kind,r.profile_id,r.cell_id,r.data,r.status,r.reason,r.version,r.created_at,p.full_name requester,c.name cell_name
   from private.member_family_requests r join public.people p on p.id=r.person_id left join public.church_cells c on c.id=r.cell_id
   where r.organization_id=p_org and r.unit_id=p_unit and r.status='pending' and (is_kids and r.kind like 'kids.%' or not is_kids and r.kind='cell.leave') order by r.created_at,r.id limit 21 offset p_offset)q;
 elsif p_action='kids.reception' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select r.id,r.profile_id,r.group_id,r.status,r.pickup_requested_at,s.name session,s.starts_at,c.full_name child,p.full_name requester,
   a.status attendance,a.checked_in_at,a.checked_out_at from private.kids_member_reservations r join private.kids_sessions s on s.id=r.session_id join private.kids_profiles k on k.id=r.profile_id join public.people c on c.id=k.person_id join public.people p on p.id=r.person_id left join private.kids_attendance a on a.session_id=r.session_id and a.profile_id=r.profile_id
   where r.organization_id=p_org and r.unit_id=p_unit and r.status='reserved' and s.status='open' order by r.pickup_requested_at nulls last,r.created_at,r.id limit 21 offset p_offset)q;
 elsif p_action='cells.catalog' then
  if not private.target_unit_module_enabled(p_org,p_unit,'cells') then raise exception 'family_denied' using errcode='42501';end if;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select c.id,c.name,c.meeting_day,c.meeting_time,c.status,coalesce(a.area,'') area,coalesce(a.description,'') description,coalesce(a.published,false) published,coalesce(a.version,0) version from public.church_cells c left join private.cell_app_publications a on a.cell_id=c.id where c.organization_id=p_org and c.unit_id=p_unit order by c.id limit 21 offset p_offset)q;
 elsif p_action='cells.publish' then
  if not private.target_unit_module_enabled(p_org,p_unit,'cells') or p_data-array['area','description','published']<>'{}' or not(p_data?&array['area','description','published']) or jsonb_typeof(p_data->'area')<>'string' or jsonb_typeof(p_data->'description')<>'string' or jsonb_typeof(p_data->'published')<>'boolean' or length(p_data->>'area')>160 or length(p_data->>'description')>2000 then raise exception 'invalid_family' using errcode='22023';end if;
  perform 1 from public.church_cells where id=p_id and organization_id=p_org and unit_id=p_unit and status='active' for update;
  if not found then raise exception 'family_denied' using errcode='42501';end if;
  select version into v from private.cell_app_publications where cell_id=p_id for update;
  if coalesce(v,0) is distinct from p_version then raise exception 'family_changed' using errcode='40001';end if;
  insert into private.cell_app_publications(cell_id,organization_id,unit_id,area,description,published,updated_by) values(p_id,p_org,p_unit,p_data->>'area',p_data->>'description',(p_data->>'published')::boolean,auth.uid())
  on conflict(cell_id) do update set area=excluded.area,description=excluded.description,published=excluded.published,version=private.cell_app_publications.version+1,updated_by=auth.uid();
 elsif p_action in('kids.review','cells.review') then
  if p_data-array['decision','reason','verification','existingProfile']<>'{}' or not(p_data?&array['decision','reason','verification','existingProfile']) or jsonb_typeof(p_data->'decision')<>'string' or jsonb_typeof(p_data->'reason')<>'string' or jsonb_typeof(p_data->'verification')<>'string' or p_data->>'decision' not in('approved','rejected') or length(p_data->>'reason')>1000 or length(p_data->>'verification')>500 then raise exception 'invalid_family' using errcode='22023';end if;
  select * into req from private.member_family_requests where id=p_id and organization_id=p_org and unit_id=p_unit and(case when is_kids then kind like 'kids.%' else kind='cell.leave' end) for update;
  if not found then raise exception 'family_denied' using errcode='42501';end if;
  if req.status<>'pending' or req.version is distinct from p_version then raise exception 'family_changed' using errcode='40001';end if;
  answer=p_data->>'decision';
  if length(btrim(p_data->>'reason'))<3 then raise exception 'invalid_family' using errcode='22023';end if;
  if answer='approved' then
   select * into person from public.people where id=req.person_id and organization_id=p_org and unit_id=p_unit and status='active' and auth_user_id=req.user_id for share;
   if not found then raise exception 'family_denied' using errcode='42501';end if;
   if req.kind='cell.leave' then
    perform 1 from public.church_cells where id=req.cell_id and organization_id=p_org and unit_id=p_unit for update;
    update public.church_cell_participants set status='inactive',version=version+1,updated_at=clock_timestamp() where cell_id=req.cell_id and person_id=req.person_id and status='active';
   else
    if person.birth_date is null or person.birth_date>current_date-interval '18 years' or length(btrim(p_data->>'verification'))<10 then raise exception 'family_verification_required' using errcode='22023';end if;
    if (req.data->>'birth')::date>current_date or (req.data->>'birth')::date<=current_date-interval '18 years' then raise exception 'family_age' using errcode='22023';end if;
    if req.kind='kids.edit' then
     if not private.member_kids_guardian(p_org,p_unit,req.profile_id,req.person_id,true) then raise exception 'family_denied' using errcode='42501';end if;
     select id,person_id into profile,child from private.kids_profiles where id=req.profile_id and organization_id=p_org and unit_id=p_unit for update;
     if (select version from private.kids_profiles where id=profile) is distinct from req.profile_version or coalesce((select version from private.kids_care where profile_id=profile),0) is distinct from req.care_version then raise exception 'family_changed' using errcode='40001';end if;
     update public.people set full_name=btrim(req.data->>'name'),birth_date=(req.data->>'birth')::date,updated_at=clock_timestamp() where id=child;
     update private.kids_profiles set version=version+1,updated_at=clock_timestamp() where id=profile;
    elsif nullif(p_data->>'existingProfile','') is not null then
     select k.id,k.person_id into profile,child from private.kids_profiles k join public.people p on p.id=k.person_id where k.id=(p_data->>'existingProfile')::uuid and k.organization_id=p_org and k.unit_id=p_unit and k.status='active' and k.review_status='approved' and p.status='active' and p.unit_id=p_unit and p.birth_date=(req.data->>'birth')::date for update of k;
     if not found then raise exception 'family_profile_mismatch' using errcode='22023';end if;
    else
     child=extensions.gen_random_uuid();profile=extensions.gen_random_uuid();
     insert into public.people(id,organization_id,unit_id,full_name,birth_date,status) values(child,p_org,p_unit,btrim(req.data->>'name'),(req.data->>'birth')::date,'active');
     insert into private.kids_profiles(id,organization_id,unit_id,person_id,review_status,created_by) values(profile,p_org,p_unit,child,'approved',auth.uid());
    end if;
    if req.kind='kids.create' then
     insert into private.kids_guardians(organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,can_edit,status,approved_by,approved_at,created_by)
     values(p_org,p_unit,profile,req.person_id,'Responsável conferido',p_data->>'verification',true,true,'approved',auth.uid(),clock_timestamp(),auth.uid())
     on conflict(profile_id,person_id) do update set status='approved',can_pickup=true,can_edit=true,valid_until=null,verification_note=excluded.verification_note,approved_by=auth.uid(),approved_at=clock_timestamp(),version=private.kids_guardians.version+1;
    end if;
    if req.kind='kids.edit' or nullif(p_data->>'existingProfile','') is null then
     insert into private.kids_care(profile_id,organization_id,unit_id,instructions,source) values(profile,p_org,p_unit,req.data->>'care','Informado pelo responsável e revisado pela equipe') on conflict(profile_id) do update set instructions=excluded.instructions,source=excluded.source,version=private.kids_care.version+1,updated_at=clock_timestamp();
    end if;
    insert into private.kids_history(organization_id,unit_id,profile_id,person_id,actor_id,action,changed_fields) values(p_org,p_unit,profile,child,auth.uid(),'kids.app.review',array['profile','guardian','care']);
   end if;
  end if;
  update private.member_family_requests set status=answer,reason=p_data->>'reason',reviewed_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=req.id;
 else raise exception 'invalid_family' using errcode='22023';end if;
 if rows is not null then return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.family.'||p_action,'member_service',p_id);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.member_family_admin(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function private.member_family_admin(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function public.member_family_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.member_family_admin(p_org,p_unit,p_action,p_id,p_version,p_data,p_offset)$$;
revoke all on function public.member_family_admin(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function public.member_family_admin(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;

-- Admissions and room transfers must preserve places reserved by other families.
-- K2 increments occupied before writing attendance; any failure rolls it all back.
create function private.kids_app_capacity_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare g private.kids_session_rooms;holds integer;
begin
 if tg_op='UPDATE' and new.group_id=old.group_id then return new;end if;
 select * into g from private.kids_session_rooms where id=new.group_id for update;
 select count(*) into holds from private.kids_member_reservations r where r.group_id=g.id and r.status='reserved' and r.profile_id<>new.profile_id
 and private.member_kids_guardian(r.organization_id,r.unit_id,r.profile_id,r.person_id)
 and not exists(select 1 from private.kids_attendance a where a.session_id=r.session_id and a.profile_id=r.profile_id);
 if g.occupied+holds>least(g.capacity,(select capacity from private.kids_rooms where id=g.room_id)) then raise exception 'kids_reserved_capacity' using errcode='40001';end if;
 return new;
end $$;
revoke all on function private.kids_app_capacity_guard() from public,anon,authenticated,service_role;
create trigger kids_app_reserved_capacity before insert or update of group_id on private.kids_attendance for each row execute function private.kids_app_capacity_guard();

create function private.kids_app_room_capacity_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare holds integer;
begin
 if new.capacity>=old.capacity then return new;end if;
 select count(*) into holds from private.kids_member_reservations r where r.group_id=new.id and r.status='reserved'
 and private.member_kids_guardian(r.organization_id,r.unit_id,r.profile_id,r.person_id)
 and not exists(select 1 from private.kids_attendance a where a.session_id=r.session_id and a.profile_id=r.profile_id);
 if new.occupied+holds>new.capacity then raise exception 'kids_reserved_capacity' using errcode='40001';end if;
 return new;
end $$;
revoke all on function private.kids_app_room_capacity_guard() from public,anon,authenticated,service_role;
create trigger kids_app_room_capacity before update of capacity on private.kids_session_rooms for each row execute function private.kids_app_room_capacity_guard();

-- Extend the existing private inbox without exposing names or care instructions.
create or replace function private.member_inbox_rows(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $$
 select * from(select * from private.member_inbox_before_learning(p_org,p_unit)
 union all select 'learning:'||e.id||':'||e.version,'Leitura e jornada concluída',p.title||' — todas as etapas foram marcadas como concluídas.',e.completed_at,'learning',e.program_id from private.learning_enrollments e join private.learning_programs p on p.id=e.program_id where e.organization_id=p_org and e.user_id=auth.uid() and e.completed_at is not null
 union all select 'family:'||r.id||':'||r.version,case when r.kind='cell.leave' then 'Solicitação de grupo atualizada' else 'Solicitação Kids atualizada' end,'A igreja revisou sua solicitação. Consulte a decisão na sua área privada.',r.updated_at,case when r.kind='cell.leave' then 'cells' else 'kids' end,r.id from private.member_family_requests r where r.organization_id=p_org and r.user_id=auth.uid() and r.status in('approved','rejected')
 union all select 'cell-participation:'||r.id||':'||r.version,'Participação em grupo atualizada','Consulte sua solicitação e os grupos da igreja.',r.updated_at,'cells',r.cell_id from private.cell_referrals r where r.organization_id=p_org and r.created_by=auth.uid() and r.status in('accepted','rejected'))q order by occurred_at desc nulls last,message_key limit 100;
$$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated,service_role;

-- Preserve K2 authorization and include member reservations in staff occupancy.
create or replace function private.kids_operations_page(p_org uuid,p_unit uuid,p_session uuid default null,p_after uuid default null,p_search text default '',p_status text default 'present') returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid=p_session;manager boolean;receiver boolean;supervisor boolean;items jsonb;next_id uuid;result jsonb;
begin
 perform private.require_confirmed_self_service_email();
 manager=private.kids_op_allowed(p_org,p_unit,null,'configure');
 if not manager and not private.kids_allowed(p_org,p_unit,'read') and not exists(select 1 from private.kids_sessions s where s.organization_id=p_org and s.unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,s.id)) then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_status is null or p_status not in ('present','out','all') or p_search is null or length(p_search)>100 then raise exception 'kids_invalid' using errcode='22023';end if;
 if sid is null then select id into sid from private.kids_sessions s where organization_id=p_org and unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,s.id) order by (status='open') desc,starts_at desc limit 1;end if;
 if sid is not null and not exists(select 1 from private.kids_sessions s where s.id=sid and s.organization_id=p_org and s.unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,s.id)) then raise exception 'kids_access_denied' using errcode='42501';end if;
 receiver=coalesce(private.kids_op_allowed(p_org,p_unit,sid,'receive'),false);supervisor=coalesce(private.kids_op_allowed(p_org,p_unit,sid,'supervise'),false);
 select coalesce(jsonb_agg(x.entry order by x.id),'[]'::jsonb) into items from (
 select a.id,jsonb_build_object('id',a.id,'profileId',a.profile_id,'name',p.full_name,'groupId',a.group_id,'status',a.status,'version',a.version,'inAt',a.checked_in_at,'outAt',a.checked_out_at,
 'hold',a.hold,'holdReason',case when supervisor then a.hold_reason else '' end,'transferTo',a.transfer_to,'canAccept',a.transfer_to is not null and private.kids_op_allowed(p_org,p_unit,sid,'accept',a.transfer_to),
 'failedAttempts',case when receiver then a.failed_attempts else 0 end,'receiptExpiresAt',case when receiver then a.receipt_expires_at else null end,
 'guardians',case when receiver then (select coalesce(jsonb_agg(jsonb_build_object('id',g.person_id,'name',adult.full_name) order by adult.full_name),'[]'::jsonb) from private.kids_guardians g join public.people adult on adult.id=g.person_id and adult.organization_id=g.organization_id and adult.unit_id=g.unit_id where g.profile_id=a.profile_id and g.status='approved' and g.can_pickup and (g.valid_until is null or g.valid_until>=(clock_timestamp() at time zone 'America/Sao_Paulo')::date) and adult.status='active' and adult.birth_date<=current_date-interval '18 years') else '[]'::jsonb end,
 'care',case when private.kids_allowed(p_org,p_unit,'care') or exists(select 1 from private.kids_assignments z where z.session_id=sid and z.active and z.can_care and (z.group_id=a.group_id or z.group_id is null) and private.kids_op_staff(p_org,p_unit,sid,array[z.role],a.group_id) and z.member_id in(select m.id from public.organization_memberships m where m.user_id=auth.uid())) then (select instructions from private.kids_care where profile_id=a.profile_id) else null end) entry
 from private.kids_attendance a join private.kids_profiles k on k.id=a.profile_id join public.people p on p.id=k.person_id
 where a.organization_id=p_org and a.unit_id=p_unit and a.session_id=sid and (p_status='all' or a.status=p_status) and (p_after is null or a.id>p_after) and strpos(lower(p.full_name),lower(p_search))>0
 and (receiver or private.kids_op_staff(p_org,p_unit,sid,array['teacher','assistant'],a.group_id) or a.transfer_to is not null and private.kids_op_staff(p_org,p_unit,sid,array['teacher'],a.transfer_to)) order by a.id limit 50) x;
 if jsonb_array_length(items)=50 then next_id=(items->49->>'id')::uuid;end if;
 result=jsonb_build_object('unitId',p_unit,'sessionId',sid,'canConfigure',manager,'canSupervise',supervisor,'canReceive',receiver,'canDirectory',private.kids_allowed(p_org,p_unit,'read'),'updatedAt',clock_timestamp(),'items',items,'nextCursor',next_id,
 'rooms',case when manager then (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]'::jsonb) from (select id,name,location,capacity,active,version from private.kids_rooms where organization_id=p_org and unit_id=p_unit order by name limit 200) x) else '[]'::jsonb end,
 'classes',case when manager then (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'minMonths',min_months,'maxMonths',max_months,'active',active,'version',version) order by name),'[]'::jsonb) from (select * from private.kids_classes where organization_id=p_org and unit_id=p_unit order by name limit 200) x) else '[]'::jsonb end,
 'sessions',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'startsAt',starts_at,'endsAt',ends_at,'status',status,'version',version) order by starts_at desc),'[]'::jsonb) from (select * from private.kids_sessions s where organization_id=p_org and unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,s.id) order by (id=sid) desc,starts_at desc limit 60) x),
 'groups',(select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'roomId',g.room_id,'classId',g.class_id,'room',r.name,'className',c.name,'capacity',g.capacity,'occupied',g.occupied,'reserved',(select count(*) from private.kids_member_reservations z where z.group_id=g.id and z.status='reserved' and private.member_kids_guardian(z.organization_id,z.unit_id,z.profile_id,z.person_id) and not exists(select 1 from private.kids_attendance a where a.session_id=z.session_id and a.profile_id=z.profile_id)),'minStaff',g.min_staff,'staffCount',private.kids_op_staff_count(p_org,p_unit,sid,g.id),'version',g.version) order by r.name),'[]'::jsonb) from private.kids_session_rooms g join private.kids_rooms r on r.id=g.room_id join private.kids_classes c on c.id=g.class_id where g.session_id=sid and (receiver or private.kids_op_staff(p_org,p_unit,sid,array['teacher','assistant'],g.id))),
 'assignments',case when supervisor then (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'personId',a.person_id,'name',p.full_name,'groupId',a.group_id,'role',a.role,'canCare',a.can_care,'active',a.active,'version',a.version) order by p.full_name),'[]'::jsonb) from private.kids_assignments a join public.people p on p.id=a.person_id where a.session_id=sid) else '[]'::jsonb end,
 'history',case when supervisor then (select coalesce(jsonb_agg(x.entry order by x.id desc),'[]'::jsonb) from (select e.id,jsonb_build_object('id',e.id::text,'action',e.action,'at',e.created_at,'actor',coalesce(nullif(p.full_name,''),'Operador'),'child',child.full_name,'details',e.details) entry from private.kids_custody_events e left join public.profiles p on p.id=e.actor_id left join private.kids_attendance a on a.id=e.attendance_id left join private.kids_profiles k on k.id=a.profile_id left join public.people child on child.id=k.person_id where e.organization_id=p_org and e.unit_id=p_unit and (sid is null and e.session_id is null or e.session_id=sid) order by e.id desc limit 50) x) else '[]'::jsonb end);
 return result;
end $$;
