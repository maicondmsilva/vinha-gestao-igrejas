-- K2: all custody writes are transactional and scoped to a verified ministry/unit.
set local check_function_bodies=on;
create table private.kids_rooms (
 id uuid primary key, organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 100),location text not null check(length(location)<=200),
 capacity integer not null check(capacity between 1 and 500),active boolean not null default true,version integer not null default 1,
 unique(id,organization_id,unit_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index kids_rooms_scope on private.kids_rooms(organization_id,unit_id);
create table private.kids_classes (
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 100),min_months integer not null check(min_months>=0),
 max_months integer not null check(max_months between min_months and 215),active boolean not null default true,version integer not null default 1,
 unique(id,organization_id,unit_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index kids_classes_scope on private.kids_classes(organization_id,unit_id);
create table private.kids_sessions (
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 100),starts_at timestamptz not null,ends_at timestamptz not null,
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),version integer not null default 1,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 check(ends_at>starts_at and ends_at<=starts_at+interval '24 hours'),unique(id,organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index kids_sessions_scope on private.kids_sessions(organization_id,unit_id,starts_at desc);
create index kids_sessions_actor on private.kids_sessions(created_by);
create table private.kids_session_rooms (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,session_id uuid not null,room_id uuid not null,class_id uuid not null,
 capacity integer not null check(capacity between 1 and 500),min_staff integer not null default 1 check(min_staff between 1 and 30),
 occupied integer not null default 0 check(occupied between 0 and capacity),version integer not null default 1,
 unique(session_id,room_id),unique(id,organization_id,unit_id,session_id),
 foreign key(session_id,organization_id,unit_id) references private.kids_sessions(id,organization_id,unit_id),
 foreign key(room_id,organization_id,unit_id) references private.kids_rooms(id,organization_id,unit_id),
 foreign key(class_id,organization_id,unit_id) references private.kids_classes(id,organization_id,unit_id)
);
create index kids_session_rooms_scope on private.kids_session_rooms(organization_id,unit_id,session_id);
create index kids_session_rooms_room on private.kids_session_rooms(room_id);
create index kids_session_rooms_class on private.kids_session_rooms(class_id);
create table private.kids_assignments (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,session_id uuid not null,group_id uuid,
 person_id uuid not null,member_id uuid not null references public.organization_memberships(id),
 role text not null check(role in ('supervisor','reception','teacher','assistant')),can_care boolean not null default false,
 active boolean not null default true,version integer not null default 1,
 check((role in ('supervisor','reception'))=(group_id is null)),check(not can_care or role in ('teacher','supervisor')),
 foreign key(session_id,organization_id,unit_id) references private.kids_sessions(id,organization_id,unit_id),
 foreign key(group_id,organization_id,unit_id,session_id) references private.kids_session_rooms(id,organization_id,unit_id,session_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create index kids_assignments_scope on private.kids_assignments(organization_id,unit_id,session_id,member_id);
create index kids_assignments_person on private.kids_assignments(person_id);
create index kids_assignments_member on private.kids_assignments(member_id);
create index kids_assignments_group on private.kids_assignments(group_id);
create unique index kids_assignment_unique on private.kids_assignments(session_id,member_id,role,coalesce(group_id,'00000000-0000-0000-0000-000000000000'::uuid));
create table private.kids_attendance (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,session_id uuid not null,group_id uuid not null,profile_id uuid not null,
 arrival_guardian uuid not null,pickup_guardian uuid,
 status text not null default 'present' check(status in ('present','out')),version integer not null default 1,
 checked_in_at timestamptz not null default clock_timestamp(),checked_out_at timestamptz,
 checked_in_by uuid not null references auth.users(id),checked_out_by uuid references auth.users(id),
 receipt_hash text not null check(length(receipt_hash)=64),receipt_expires_at timestamptz not null,
 failed_attempts integer not null default 0 check(failed_attempts between 0 and 5),
 hold boolean not null default false,hold_reason text not null default '' check(length(hold_reason)<=500),
 transfer_to uuid,transfer_reason text not null default '' check(length(transfer_reason)<=500),transfer_requested_by uuid references auth.users(id),
 unique(id,organization_id,unit_id),check((status='out')=(checked_out_at is not null and checked_out_by is not null and pickup_guardian is not null)),
 foreign key(session_id,organization_id,unit_id) references private.kids_sessions(id,organization_id,unit_id),
 foreign key(group_id,organization_id,unit_id,session_id) references private.kids_session_rooms(id,organization_id,unit_id,session_id),
 foreign key(transfer_to,organization_id,unit_id,session_id) references private.kids_session_rooms(id,organization_id,unit_id,session_id),
 foreign key(profile_id,organization_id,unit_id) references private.kids_profiles(id,organization_id,unit_id),
 foreign key(arrival_guardian,organization_id) references public.people(id,organization_id),
 foreign key(pickup_guardian,organization_id) references public.people(id,organization_id)
);
create unique index kids_one_active_presence on private.kids_attendance(organization_id,profile_id) where status='present';
create unique index kids_one_session_presence on private.kids_attendance(session_id,profile_id);
create index kids_attendance_scope on private.kids_attendance(organization_id,unit_id,session_id,status,id);
create index kids_attendance_profile on private.kids_attendance(profile_id);
create index kids_attendance_group on private.kids_attendance(group_id,status);
create index kids_attendance_transfer on private.kids_attendance(transfer_to) where transfer_to is not null;
create index kids_attendance_arrival on private.kids_attendance(arrival_guardian);
create index kids_attendance_pickup on private.kids_attendance(pickup_guardian);
create index kids_attendance_in_actor on private.kids_attendance(checked_in_by);
create index kids_attendance_out_actor on private.kids_attendance(checked_out_by);
create index kids_attendance_transfer_actor on private.kids_attendance(transfer_requested_by);
create table private.kids_custody_events (
 id bigint generated always as identity primary key,organization_id uuid not null,unit_id uuid not null,session_id uuid,
 attendance_id uuid,actor_id uuid not null references auth.users(id),action text not null,
 entity_id uuid not null,details jsonb not null default '{}',created_at timestamptz not null default clock_timestamp(),
 foreign key(attendance_id,organization_id,unit_id) references private.kids_attendance(id,organization_id,unit_id),
 foreign key(session_id,organization_id,unit_id) references private.kids_sessions(id,organization_id,unit_id)
);
create index kids_custody_events_scope on private.kids_custody_events(organization_id,unit_id,session_id,id desc);
create index kids_custody_events_attendance on private.kids_custody_events(attendance_id);
create index kids_custody_events_actor on private.kids_custody_events(actor_id);
create table private.kids_operation_requests (
 organization_id uuid not null,unit_id uuid not null,actor_id uuid not null,request_id uuid not null,
 fingerprint text not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(organization_id,actor_id,request_id)
);
create index kids_operation_requests_unit on private.kids_operation_requests(organization_id,unit_id);
create table private.kids_operation_mutex (
 unit_id uuid primary key references public.organization_units(id),revision bigint not null default 1
);
do $$declare tab text;begin
 foreach tab in array array['kids_rooms','kids_classes','kids_sessions','kids_session_rooms','kids_assignments','kids_attendance','kids_custody_events','kids_operation_requests','kids_operation_mutex'] loop
 execute format('alter table private.%I enable row level security',tab);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',tab);
 end loop;
end $$;
revoke all on sequence private.kids_custody_events_id_seq from public,anon,authenticated,service_role;

-- No dependency on editable JWT metadata. Assignments reference a current adult
-- People record AND that person's current active membership/account.
create function private.kids_op_staff(p_org uuid,p_unit uuid,p_session uuid,p_roles text[],p_group uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.kids_assignments a
 join public.people p on p.id=a.person_id and p.organization_id=a.organization_id and p.unit_id=a.unit_id
 join public.organization_memberships m on m.id=a.member_id and m.organization_id=a.organization_id and m.user_id=p.auth_user_id
 join auth.users u on u.id=m.user_id
 where a.organization_id=p_org and a.unit_id=p_unit and a.session_id=p_session and a.active and a.role=any(p_roles)
 and (p_group is null or a.group_id is null or a.group_id=p_group) and m.user_id=auth.uid() and m.status='active'
 and p.status='active' and p.birth_date<=current_date-interval '18 years'
 and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false) and coalesce(u.banned_until,clock_timestamp())<=clock_timestamp());
$$;
revoke all on function private.kids_op_staff(uuid,uuid,uuid,text[],uuid) from public,anon,authenticated,service_role;
create function private.kids_op_allowed(p_org uuid,p_unit uuid,p_session uuid default null,p_mode text default 'read',p_group uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and private.can_access_unit(p_org,p_unit,array['read','manage','admin']::public.unit_access_level[])
 and private.target_unit_module_enabled(p_org,p_unit,'kids') and private.target_unit_module_enabled(p_org,p_unit,'people')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in ('active','trial'))
 and (private.kids_allowed(p_org,p_unit,'approve')
 or p_mode<>'configure' and private.kids_op_staff(p_org,p_unit,p_session,
 case p_mode when 'supervise' then array['supervisor'] when 'receive' then array['supervisor','reception'] when 'accept' then array['supervisor','teacher'] else array['supervisor','reception','teacher','assistant'] end,p_group));
$$;
revoke all on function private.kids_op_allowed(uuid,uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
create function private.kids_op_guardian(p_org uuid,p_unit uuid,p_profile uuid,p_person uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.people where id=p_person and organization_id=p_org and unit_id=p_unit and status='active' and birth_date<=current_date-interval '18 years' for share;
 if not found then return false;end if;
 perform 1 from private.kids_guardians where organization_id=p_org and unit_id=p_unit and profile_id=p_profile and person_id=p_person and status='approved' and can_pickup and (valid_until is null or valid_until>=(clock_timestamp() at time zone 'America/Sao_Paulo')::date) for share;
 return found;
end $$;
revoke all on function private.kids_op_guardian(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function private.kids_op_member_scope(p_member uuid,p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(with recursive ancestors as (
 select id,parent_unit_id from public.organization_units where id=p_unit and organization_id=p_org
 union all select u.id,u.parent_unit_id from public.organization_units u join ancestors a on a.parent_unit_id=u.id where u.organization_id=p_org)
 select 1 from public.organization_memberships m where m.id=p_member and m.organization_id=p_org and m.status='active' and
 (m.role in ('owner','admin','pastor') or exists(select 1 from public.membership_unit_access x join ancestors a on a.id=x.unit_id where x.membership_id=m.id and (x.unit_id=p_unit or x.include_children))));
$$;
revoke all on function private.kids_op_member_scope(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function private.kids_op_staff_count(p_org uuid,p_unit uuid,p_session uuid,p_group uuid) returns integer
language sql stable security definer set search_path='' as $$
 select count(distinct a.member_id)::integer from private.kids_assignments a
 join public.people p on p.id=a.person_id and p.organization_id=a.organization_id and p.unit_id=a.unit_id
 join public.organization_memberships m on m.id=a.member_id and m.organization_id=a.organization_id and m.user_id=p.auth_user_id
 join auth.users u on u.id=m.user_id
 where a.organization_id=p_org and a.unit_id=p_unit and a.session_id=p_session and a.group_id=p_group and a.role in ('teacher','assistant') and a.active
 and p.status='active' and p.birth_date<=current_date-interval '18 years' and m.status='active' and private.kids_op_member_scope(m.id,p_org,p_unit)
 and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false) and coalesce(u.banned_until,clock_timestamp())<=clock_timestamp();
$$;
revoke all on function private.kids_op_staff_count(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function private.kids_operations_save(p_org uuid,p_unit uuid,p_request uuid,p_action text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid();fp text;result jsonb;cached private.kids_operation_requests;
 r private.kids_rooms;c private.kids_classes;s private.kids_sessions;g private.kids_session_rooms;a private.kids_assignments;
 present private.kids_attendance;k private.kids_profiles;person public.people;member public.organization_memberships;
 sid uuid;pid uuid;target uuid;cnt integer;next_status text;event_details jsonb='{}';event_attendance uuid;secret text;age_months integer;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for share;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=actor for share;
 perform 1 from public.membership_unit_access x join public.organization_memberships m on m.id=x.membership_id where m.organization_id=p_org and m.user_id=actor for share of x;
 perform 1 from public.saas_unit_contracts where organization_id=p_org and unit_id=p_unit for share;
 if p_request is null or p_id is null or p_version is null or p_version<0 or p_action is null or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'kids_invalid' using errcode='22023';end if;
 -- A written row, not only an advisory lock: stale repeatable-read snapshots
 -- must fail serialization instead of checking old occupancy or assignments.
 if not private.kids_op_allowed(p_org,p_unit,null,'configure') and not exists(select 1 from private.kids_assignments x where x.organization_id=p_org and x.unit_id=p_unit and x.active and private.kids_op_allowed(p_org,p_unit,x.session_id,'read')) then raise exception 'kids_access_denied' using errcode='42501';end if;
 insert into private.kids_operation_mutex(unit_id) values(p_unit) on conflict(unit_id) do update set revision=private.kids_operation_mutex.revision+1;
 if p_action in ('room','class','session','group','assignment','sessionState') then
  if p_action='sessionState' then sid=p_id;else sid=nullif(p_data->>'sessionId','')::uuid;end if;
  if not private.kids_op_allowed(p_org,p_unit,sid,case when p_action='sessionState' then 'supervise' else 'configure' end) then raise exception 'kids_access_denied' using errcode='42501';end if;
 else
  if p_action='checkin' then sid=(p_data->>'sessionId')::uuid;
  else select * into present from private.kids_attendance where id=p_id and organization_id=p_org and unit_id=p_unit for update;
   if not found then raise exception 'kids_not_found' using errcode='P0002';end if;sid=present.session_id;
  end if;
  if not private.kids_op_allowed(p_org,p_unit,sid,case when p_action in ('recover','hold') then 'supervise' when p_action='transferAccept' then 'accept' else 'receive' end,case when p_action='transferAccept' then present.transfer_to else null end) then raise exception 'kids_access_denied' using errcode='42501';end if;
 end if;
 fp=encode(extensions.digest(jsonb_build_array(p_unit,p_action,p_id,p_version,p_data)::text,'sha256'),'hex');
 -- Serialize staff eligibility with suspensions and unit-scope revocations.
 perform 1 from public.organization_memberships m join private.kids_assignments x on x.member_id=m.id where x.session_id=sid order by m.id for share of m;
 perform 1 from public.membership_unit_access z join private.kids_assignments x on x.member_id=z.membership_id where x.session_id=sid order by z.membership_id,z.unit_id for share of z;
 perform 1 from public.people p join private.kids_assignments x on x.person_id=p.id where x.session_id=sid order by p.id for share of p;
 perform 1 from auth.users u join public.organization_memberships m on m.user_id=u.id join private.kids_assignments x on x.member_id=m.id where x.session_id=sid order by u.id for share of u;
 select * into cached from private.kids_operation_requests where organization_id=p_org and actor_id=actor and request_id=p_request;
 if found then if cached.fingerprint<>fp or cached.unit_id<>p_unit then raise exception 'kids_version_conflict' using errcode='40001';end if;return cached.result;end if;
 if p_action='room' then
  if p_data-array['name','location','capacity','active']<>'{}'::jsonb or not(p_data ?& array['name','location','capacity','active']) or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'kids_invalid' using errcode='22023';end if;
  select * into r from private.kids_rooms where id=p_id for update;
  if found and (r.organization_id<>p_org or r.unit_id<>p_unit) then raise exception 'kids_access_denied' using errcode='42501';end if;
  if coalesce(r.version,0)<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
  if exists(select 1 from private.kids_session_rooms x join private.kids_sessions y on y.id=x.session_id where x.room_id=p_id and y.status='open') then raise exception 'kids_room_in_use' using errcode='40001';end if;
  insert into private.kids_rooms(id,organization_id,unit_id,name,location,capacity,active) values(p_id,p_org,p_unit,btrim(p_data->>'name'),p_data->>'location',(p_data->>'capacity')::integer,(p_data->>'active')::boolean)
  on conflict(id) do update set name=excluded.name,location=excluded.location,capacity=excluded.capacity,active=excluded.active,version=private.kids_rooms.version+1 returning version into cnt;
 elsif p_action='class' then
  if p_data-array['name','minMonths','maxMonths','active']<>'{}'::jsonb or not(p_data ?& array['name','minMonths','maxMonths','active']) or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'kids_invalid' using errcode='22023';end if;
  select * into c from private.kids_classes where id=p_id for update;
  if found and (c.organization_id<>p_org or c.unit_id<>p_unit) then raise exception 'kids_access_denied' using errcode='42501';end if;
  if coalesce(c.version,0)<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
  if exists(select 1 from private.kids_session_rooms x join private.kids_sessions y on y.id=x.session_id where x.class_id=p_id and y.status='open') then raise exception 'kids_class_in_use' using errcode='40001';end if;
  insert into private.kids_classes(id,organization_id,unit_id,name,min_months,max_months,active) values(p_id,p_org,p_unit,btrim(p_data->>'name'),(p_data->>'minMonths')::integer,(p_data->>'maxMonths')::integer,(p_data->>'active')::boolean)
  on conflict(id) do update set name=excluded.name,min_months=excluded.min_months,max_months=excluded.max_months,active=excluded.active,version=private.kids_classes.version+1 returning version into cnt;
 elsif p_action='session' then
  if p_data-array['name','startsAt','endsAt']<>'{}'::jsonb or not(p_data ?& array['name','startsAt','endsAt']) then raise exception 'kids_invalid' using errcode='22023';end if;
  select * into s from private.kids_sessions where id=p_id for update;
  if found and (s.organization_id<>p_org or s.unit_id<>p_unit) then raise exception 'kids_access_denied' using errcode='42501';end if;
  if coalesce(s.version,0)<>p_version or s.id is not null and s.status<>'draft' then raise exception 'kids_version_conflict' using errcode='40001';end if;
  insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,created_by) values(p_id,p_org,p_unit,btrim(p_data->>'name'),(p_data->>'startsAt')::timestamptz,(p_data->>'endsAt')::timestamptz,actor)
  on conflict(id) do update set name=excluded.name,starts_at=excluded.starts_at,ends_at=excluded.ends_at,version=private.kids_sessions.version+1 returning version into cnt;
 elsif p_action in ('group','assignment','sessionState') then
  select * into s from private.kids_sessions where id=sid and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  if p_action='group' then
   if s.status<>'draft' or p_data-array['sessionId','roomId','classId','capacity','minStaff']<>'{}'::jsonb or not(p_data ?& array['sessionId','roomId','classId','capacity','minStaff']) then raise exception 'kids_invalid' using errcode='22023';end if;
   select * into r from private.kids_rooms where id=(p_data->>'roomId')::uuid and organization_id=p_org and unit_id=p_unit and active for share;
   select * into c from private.kids_classes where id=(p_data->>'classId')::uuid and organization_id=p_org and unit_id=p_unit and active for share;
   if r.id is null or c.id is null or (p_data->>'capacity')::integer>r.capacity then raise exception 'kids_invalid' using errcode='22023';end if;
   select * into g from private.kids_session_rooms where id=p_id for update;
   if found and (g.organization_id<>p_org or g.unit_id<>p_unit or g.session_id<>sid or g.room_id<>r.id or g.class_id<>c.id) then raise exception 'kids_access_denied' using errcode='42501';end if;
   if coalesce(g.version,0)<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   insert into private.kids_session_rooms(id,organization_id,unit_id,session_id,room_id,class_id,capacity,min_staff) values(p_id,p_org,p_unit,sid,r.id,c.id,(p_data->>'capacity')::integer,(p_data->>'minStaff')::integer)
   on conflict(id) do update set capacity=excluded.capacity,min_staff=excluded.min_staff,version=private.kids_session_rooms.version+1 returning version into cnt;
  elsif p_action='assignment' then
   if s.status not in ('draft','open') or p_data-array['sessionId','groupId','personId','role','canCare','active']<>'{}'::jsonb or not(p_data ?& array['sessionId','groupId','personId','role','canCare','active']) or jsonb_typeof(p_data->'canCare')<>'boolean' or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'kids_invalid' using errcode='22023';end if;
   select * into a from private.kids_assignments where id=p_id for update;
   if found and (a.organization_id<>p_org or a.unit_id<>p_unit or a.session_id<>sid or a.person_id<>(p_data->>'personId')::uuid) then raise exception 'kids_access_denied' using errcode='42501';end if;
   if coalesce(a.version,0)<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   if a.id is not null and p_data->'active'='false'::jsonb then
    select * into person from public.people where id=a.person_id;select * into member from public.organization_memberships where id=a.member_id;
   else
    select * into person from public.people where id=(p_data->>'personId')::uuid and organization_id=p_org and unit_id=p_unit and status='active' and birth_date<=current_date-interval '18 years' for share;
    select * into member from public.organization_memberships where user_id=person.auth_user_id and organization_id=p_org and status='active' for share;
    if person.id is null or member.id is null or not private.kids_op_member_scope(member.id,p_org,p_unit) then raise exception 'kids_staff_identity_required' using errcode='22023';end if;
    perform 1 from auth.users where id=member.user_id and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and coalesce(banned_until,clock_timestamp())<=clock_timestamp() for share;
    if not found then raise exception 'kids_staff_identity_required' using errcode='22023';end if;
    if exists(select 1 from private.kids_assignments x join private.kids_sessions y on y.id=x.session_id where x.member_id=member.id and x.active and x.id<>p_id and y.status in ('draft','open') and (x.session_id=sid or y.starts_at<s.ends_at and y.ends_at>s.starts_at)) then raise exception 'kids_staff_overlap' using errcode='40001';end if;
   end if;
   insert into private.kids_assignments(id,organization_id,unit_id,session_id,group_id,person_id,member_id,role,can_care,active)
   values(p_id,p_org,p_unit,sid,nullif(p_data->>'groupId','')::uuid,person.id,member.id,p_data->>'role',(p_data->>'canCare')::boolean,(p_data->>'active')::boolean)
   on conflict(id) do update set group_id=excluded.group_id,role=excluded.role,can_care=excluded.can_care,active=excluded.active,version=private.kids_assignments.version+1 returning version into cnt;
  else
   if s.version<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   if p_data-array['status']<>'{}'::jsonb or not(p_data ? 'status') or coalesce(p_data->>'status','') not in ('open','closed','cancelled') then raise exception 'kids_invalid' using errcode='22023';end if;next_status=p_data->>'status';
   if s.status='draft' and next_status='open' then
    if s.starts_at>clock_timestamp()+interval '2 hours' or s.ends_at<=clock_timestamp() or not exists(select 1 from private.kids_session_rooms where session_id=sid) then raise exception 'kids_session_not_ready' using errcode='22023';end if;
    if exists(select 1 from private.kids_session_rooms x join private.kids_rooms room_row on room_row.id=x.room_id join private.kids_classes class_row on class_row.id=x.class_id where x.session_id=sid and (not room_row.active or not class_row.active or x.capacity>room_row.capacity or private.kids_op_staff_count(p_org,p_unit,sid,x.id)<x.min_staff)) then raise exception 'kids_staff_insufficient' using errcode='22023';end if;
    if exists(select 1 from private.kids_session_rooms x join private.kids_session_rooms y on y.room_id=x.room_id and y.session_id<>sid join private.kids_sessions other on other.id=y.session_id where x.session_id=sid and other.status='open' and other.starts_at<s.ends_at and other.ends_at>s.starts_at) then raise exception 'kids_room_overlap' using errcode='40001';end if;
   elsif s.status='open' and next_status='closed' then
    if exists(select 1 from private.kids_attendance where session_id=sid and status='present') then raise exception 'kids_children_present' using errcode='40001';end if;
   elsif not(s.status='draft' and next_status='cancelled') then raise exception 'kids_invalid' using errcode='22023';end if;
   update private.kids_sessions set status=next_status,version=version+1 where id=sid returning version into cnt;
  end if;
 else
  select * into s from private.kids_sessions where id=sid and organization_id=p_org and unit_id=p_unit for update;
  if s.id is null or s.status<>'open' then raise exception 'kids_session_not_open' using errcode='40001';end if;
  if p_action='checkin' then
   if p_version<>0 or p_data-array['sessionId','groupId','profileId','guardianId','identityConfirmed','receiptSecret']<>'{}'::jsonb or not(p_data ?& array['sessionId','groupId','profileId','guardianId','identityConfirmed','receiptSecret']) then raise exception 'kids_invalid' using errcode='22023';end if;
   pid=(p_data->>'profileId')::uuid;target=(p_data->>'groupId')::uuid;
  else
   if present.version<>p_version or present.status<>'present' then raise exception 'kids_version_conflict' using errcode='40001';end if;pid=present.profile_id;target=present.group_id;
  end if;
  select * into k from private.kids_profiles where id=pid and organization_id=p_org and unit_id=p_unit for update;
  select * into person from public.people where id=k.person_id and organization_id=p_org and unit_id=p_unit for share;
  if k.id is null or person.id is null then raise exception 'kids_access_denied' using errcode='42501';end if;
  if p_action in ('checkin','checkout','recover') then
   if p_data->'identityConfirmed' is distinct from 'true'::jsonb or not private.kids_op_guardian(p_org,p_unit,pid,(p_data->>'guardianId')::uuid) then raise exception 'kids_guardian_required' using errcode='42501';end if;
  end if;
  if p_action in ('checkin','recover') then
   secret=p_data->>'receiptSecret';if secret is null or secret !~ '^[a-f0-9]{64}$' then raise exception 'kids_invalid' using errcode='22023';end if;
  end if;
  if p_action='checkin' then
   if k.status<>'active' or k.review_status<>'approved' or person.status<>'active' or person.birth_date is null or person.birth_date>current_date or person.birth_date<=current_date-interval '18 years' or s.ends_at<=clock_timestamp() then raise exception 'kids_child_not_ready' using errcode='22023';end if;
   select * into g from private.kids_session_rooms where id=target and session_id=sid for update;
   select * into c from private.kids_classes where id=g.class_id and active for share;
   perform 1 from private.kids_rooms where id=g.room_id and active for share;
   if g.id is null or c.id is null or not found then raise exception 'kids_invalid' using errcode='22023';end if;
   age_months=extract(year from age((s.starts_at at time zone 'America/Sao_Paulo')::date,person.birth_date))*12+extract(month from age((s.starts_at at time zone 'America/Sao_Paulo')::date,person.birth_date));
   if age_months not between c.min_months and c.max_months then raise exception 'kids_age_outside_class' using errcode='22023';end if;
   if private.kids_op_staff_count(p_org,p_unit,sid,g.id)<g.min_staff then raise exception 'kids_staff_insufficient' using errcode='22023';end if;
   update private.kids_session_rooms set occupied=occupied+1 where id=g.id and occupied<capacity returning occupied into cnt;
   if not found then raise exception 'kids_capacity_full' using errcode='40001';end if;
   -- This write also serializes identity transfer/archival with admission.
   update private.kids_profiles set version=version+1 where id=k.id;
   insert into private.kids_attendance(id,organization_id,unit_id,session_id,group_id,profile_id,arrival_guardian,checked_in_by,receipt_hash,receipt_expires_at)
   values(p_id,p_org,p_unit,sid,g.id,k.id,(p_data->>'guardianId')::uuid,actor,encode(extensions.digest(secret,'sha256'),'hex'),least(s.ends_at+interval '4 hours',clock_timestamp()+interval '12 hours')) returning * into present;
   event_details=jsonb_build_object('groupId',g.id,'guardianId',present.arrival_guardian,'identityConfirmed',true);cnt=1;
  elsif p_action='checkout' then
   if p_data-array['guardianId','identityConfirmed','receiptSecret']<>'{}'::jsonb or not(p_data ?& array['guardianId','identityConfirmed','receiptSecret']) then raise exception 'kids_invalid' using errcode='22023';end if;
   if present.hold or present.transfer_to is not null then raise exception 'kids_hold_or_transfer_pending' using errcode='40001';end if;
   if present.failed_attempts>=5 or present.receipt_expires_at<=clock_timestamp() then raise exception 'kids_receipt_recovery_required' using errcode='40001';end if;
   if coalesce(p_data->>'receiptSecret','') !~ '^[a-f0-9]{64}$' or encode(extensions.digest(p_data->>'receiptSecret','sha256'),'hex')<>present.receipt_hash then
    update private.kids_attendance set failed_attempts=failed_attempts+1,version=version+1 where id=p_id returning * into present;
    result=jsonb_build_object('ok',false,'id',p_id,'version',present.version,'reason','receipt_invalid','remainingAttempts',5-present.failed_attempts);
    event_details=jsonb_build_object('attempt',present.failed_attempts);
   else
    update private.kids_attendance set status='out',pickup_guardian=(p_data->>'guardianId')::uuid,checked_out_by=actor,checked_out_at=clock_timestamp(),version=version+1 where id=p_id returning * into present;
    update private.kids_session_rooms set occupied=occupied-1 where id=present.group_id;
    event_details=jsonb_build_object('groupId',present.group_id,'guardianId',present.pickup_guardian,'identityConfirmed',true);
   end if;cnt=present.version;
  elsif p_action='recover' then
   if p_data-array['guardianId','identityConfirmed','receiptSecret','reason']<>'{}'::jsonb or not(p_data ?& array['guardianId','identityConfirmed','receiptSecret','reason']) or length(btrim(p_data->>'reason')) not between 20 and 500 then raise exception 'kids_invalid' using errcode='22023';end if;
   update private.kids_attendance set receipt_hash=encode(extensions.digest(secret,'sha256'),'hex'),receipt_expires_at=clock_timestamp()+interval '2 hours',failed_attempts=0,version=version+1 where id=p_id returning * into present;
   event_details=jsonb_build_object('guardianId',(p_data->>'guardianId')::uuid,'identityConfirmed',true,'reason',p_data->>'reason');cnt=present.version;
  elsif p_action='hold' then
   if p_data-array['hold','reason']<>'{}'::jsonb or not(p_data ?& array['hold','reason']) or jsonb_typeof(p_data->'hold')<>'boolean' or length(btrim(p_data->>'reason')) not between 10 and 500 then raise exception 'kids_invalid' using errcode='22023';end if;
   update private.kids_attendance set hold=(p_data->>'hold')::boolean,hold_reason=p_data->>'reason',version=version+1 where id=p_id returning * into present;
   event_details=jsonb_build_object('hold',present.hold,'reason',present.hold_reason);cnt=present.version;
  elsif p_action='transfer' then
   if p_data-array['targetGroupId','reason']<>'{}'::jsonb or not(p_data ?& array['targetGroupId','reason']) or present.hold or present.transfer_to is not null or length(btrim(p_data->>'reason')) not between 10 and 500 then raise exception 'kids_invalid' using errcode='22023';end if;
   target=(p_data->>'targetGroupId')::uuid;
   perform 1 from private.kids_session_rooms where id=target and session_id=sid and id<>present.group_id for share;
   if not found then raise exception 'kids_invalid' using errcode='22023';end if;
   update private.kids_attendance set transfer_to=target,transfer_reason=p_data->>'reason',transfer_requested_by=actor,version=version+1 where id=p_id returning * into present;
   event_details=jsonb_build_object('fromGroupId',present.group_id,'toGroupId',target,'reason',present.transfer_reason);cnt=present.version;
  elsif p_action='transferAccept' then
   if p_data<>'{}'::jsonb or present.transfer_to is null or present.hold then raise exception 'kids_invalid' using errcode='22023';end if;
   if actor=present.transfer_requested_by and not private.kids_op_allowed(p_org,p_unit,sid,'supervise') then raise exception 'kids_receiving_team_required' using errcode='42501';end if;
   select * into g from private.kids_session_rooms where id=present.transfer_to and session_id=sid for update;
   select * into c from private.kids_classes where id=g.class_id and active;
   age_months=extract(year from age((s.starts_at at time zone 'America/Sao_Paulo')::date,person.birth_date))*12+extract(month from age((s.starts_at at time zone 'America/Sao_Paulo')::date,person.birth_date));
   if c.id is null or age_months not between c.min_months and c.max_months or private.kids_op_staff_count(p_org,p_unit,sid,g.id)<g.min_staff then raise exception 'kids_staff_or_age' using errcode='22023';end if;
   update private.kids_session_rooms set occupied=occupied+1 where id=g.id and occupied<capacity returning occupied into cnt;
   if not found then raise exception 'kids_capacity_full' using errcode='40001';end if;
   update private.kids_session_rooms set occupied=occupied-1 where id=present.group_id;
   event_details=jsonb_build_object('fromGroupId',present.group_id,'toGroupId',g.id,'requestActor',present.transfer_requested_by);
   update private.kids_attendance set group_id=g.id,transfer_to=null,transfer_reason='',transfer_requested_by=null,version=version+1 where id=p_id returning * into present;cnt=present.version;
  elsif p_action='transferCancel' then
   if p_data<>'{}'::jsonb or present.transfer_to is null then raise exception 'kids_invalid' using errcode='22023';end if;
   event_details=jsonb_build_object('fromGroupId',present.group_id,'toGroupId',present.transfer_to);
   update private.kids_attendance set transfer_to=null,transfer_reason='',transfer_requested_by=null,version=version+1 where id=p_id returning * into present;cnt=present.version;
  else raise exception 'kids_invalid' using errcode='22023';end if;
  event_attendance=present.id;
 end if;
 if result is null then result=jsonb_build_object('ok',true,'id',p_id,'version',cnt);end if;
 insert into private.kids_custody_events(organization_id,unit_id,session_id,attendance_id,actor_id,action,entity_id,details)
 values(p_org,p_unit,sid,event_attendance,actor,case when result->>'ok'='false' then 'receiptRefused' else p_action end,p_id,event_details);
 -- Never persist receipt secrets, health contents or identity documents here.
 insert into private.kids_operation_requests(organization_id,unit_id,actor_id,request_id,fingerprint,result) values(p_org,p_unit,actor,p_request,fp,result);
 return result;
end $$;
revoke all on function private.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.kids_operations_save(p_organization uuid,p_unit uuid,p_request uuid,p_action text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.kids_operations_save(p_organization,p_unit,p_request,p_action,p_id,p_version,p_data);$$;
revoke all on function public.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

-- Refuse archiving or moving a child who is physically present. Identity
-- changes contend on the profile version, including repeatable-read sessions.
create function private.kids_custody_identity_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='kids_profiles' then
  if new.status='archived' and exists(select 1 from private.kids_attendance where profile_id=new.id and status='present') then raise exception 'kids_child_present' using errcode='42501';end if;
 else
  if new.unit_id is distinct from old.unit_id or new.organization_id is distinct from old.organization_id then
   update private.kids_profiles set version=version+1 where person_id=old.id;
   if exists(select 1 from private.kids_attendance a join private.kids_profiles k on k.id=a.profile_id where k.person_id=old.id and a.status='present') then raise exception 'kids_child_present' using errcode='42501';end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function private.kids_custody_identity_guard() from public,anon,authenticated,service_role;
create trigger kids_present_profile_guard before update of status on private.kids_profiles for each row execute function private.kids_custody_identity_guard();
create trigger kids_present_person_guard before update of unit_id,organization_id on public.people for each row execute function private.kids_custody_identity_guard();

create function private.kids_operations_page(p_org uuid,p_unit uuid,p_session uuid default null,p_after uuid default null,p_search text default '',p_status text default 'present') returns jsonb
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
 'groups',(select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'roomId',g.room_id,'classId',g.class_id,'room',r.name,'className',c.name,'capacity',g.capacity,'occupied',g.occupied,'minStaff',g.min_staff,'staffCount',private.kids_op_staff_count(p_org,p_unit,sid,g.id),'version',g.version) order by r.name),'[]'::jsonb) from private.kids_session_rooms g join private.kids_rooms r on r.id=g.room_id join private.kids_classes c on c.id=g.class_id where g.session_id=sid and (receiver or private.kids_op_staff(p_org,p_unit,sid,array['teacher','assistant'],g.id))),
 'assignments',case when supervisor then (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'personId',a.person_id,'name',p.full_name,'groupId',a.group_id,'role',a.role,'canCare',a.can_care,'active',a.active,'version',a.version) order by p.full_name),'[]'::jsonb) from private.kids_assignments a join public.people p on p.id=a.person_id where a.session_id=sid) else '[]'::jsonb end,
 'history',case when supervisor then (select coalesce(jsonb_agg(x.entry order by x.id desc),'[]'::jsonb) from (select e.id,jsonb_build_object('id',e.id::text,'action',e.action,'at',e.created_at,'actor',coalesce(nullif(p.full_name,''),'Operador'),'child',child.full_name,'details',e.details) entry from private.kids_custody_events e left join public.profiles p on p.id=e.actor_id left join private.kids_attendance a on a.id=e.attendance_id left join private.kids_profiles k on k.id=a.profile_id left join public.people child on child.id=k.person_id where e.organization_id=p_org and e.unit_id=p_unit and (sid is null and e.session_id is null or e.session_id=sid) order by e.id desc limit 50) x) else '[]'::jsonb end);
 return result;
end $$;
revoke all on function private.kids_operations_page(uuid,uuid,uuid,uuid,text,text) from public,anon,service_role;
grant execute on function private.kids_operations_page(uuid,uuid,uuid,uuid,text,text) to authenticated;
create function public.kids_operations_page(p_organization uuid,p_unit uuid,p_session uuid default null,p_after uuid default null,p_search text default '',p_status text default 'present') returns jsonb language sql security invoker set search_path='' as $$select private.kids_operations_page(p_organization,p_unit,p_session,p_after,p_search,p_status);$$;
revoke all on function public.kids_operations_page(uuid,uuid,uuid,uuid,text,text) from public,anon,service_role;
grant execute on function public.kids_operations_page(uuid,uuid,uuid,uuid,text,text) to authenticated;

create function private.kids_admission_choices(p_org uuid,p_unit uuid,p_session uuid,p_search text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform private.require_confirmed_self_service_email();
 if not private.kids_op_allowed(p_org,p_unit,p_session,'receive') then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_search is null or length(btrim(p_search)) not between 2 and 80 then raise exception 'kids_invalid' using errcode='22023';end if;
 select coalesce(jsonb_agg(x.entry order by x.name),'[]'::jsonb) into result from (
 select p.full_name name,jsonb_build_object('id',k.id,'name',p.full_name,'birthDate',p.birth_date,'guardians',(select coalesce(jsonb_agg(jsonb_build_object('id',adult.id,'name',adult.full_name) order by adult.full_name),'[]'::jsonb) from private.kids_guardians g join public.people adult on adult.id=g.person_id and adult.organization_id=g.organization_id and adult.unit_id=g.unit_id where g.profile_id=k.id and g.status='approved' and g.can_pickup and (g.valid_until is null or g.valid_until>=(clock_timestamp() at time zone 'America/Sao_Paulo')::date) and adult.status='active' and adult.birth_date<=current_date-interval '18 years')) entry
 from private.kids_profiles k join public.people p on p.id=k.person_id and p.organization_id=k.organization_id and p.unit_id=k.unit_id
 where k.organization_id=p_org and k.unit_id=p_unit and k.status='active' and k.review_status='approved' and p.status='active' and p.birth_date>current_date-interval '18 years' and p.birth_date<=current_date and strpos(lower(p.full_name),lower(btrim(p_search)))>0
 and not exists(select 1 from private.kids_attendance a where a.profile_id=k.id and (a.status='present' or a.session_id=p_session)) order by p.full_name,k.id limit 20) x;
 return jsonb_build_object('unitId',p_unit,'items',result);
end $$;
revoke all on function private.kids_admission_choices(uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function private.kids_admission_choices(uuid,uuid,uuid,text) to authenticated;
create function public.kids_admission_choices(p_organization uuid,p_unit uuid,p_session uuid,p_search text) returns jsonb language sql security invoker set search_path='' as $$select private.kids_admission_choices(p_organization,p_unit,p_session,p_search);$$;
revoke all on function public.kids_admission_choices(uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function public.kids_admission_choices(uuid,uuid,uuid,text) to authenticated;
