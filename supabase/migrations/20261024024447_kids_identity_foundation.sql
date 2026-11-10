-- K1: private complementary records; People remains the only identity source.
-- Public entrypoints are invokers; privileged implementation stays in private,
-- explicitly authenticates the caller and revalidates unit/contract/role.
create table private.kids_profiles (
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null,
 person_id uuid not null,
 status text not null default 'active' check(status in ('active','archived')),
 review_status text not null default 'pending' check(review_status in ('pending','approved')),
 version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_id,person_id), unique(id,organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create index kids_profiles_scope on private.kids_profiles(organization_id,unit_id,id);
create table private.kids_guardians (
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null, unit_id uuid not null, profile_id uuid not null,
 person_id uuid not null,
 relationship text not null check(length(btrim(relationship)) between 2 and 80),
 verification_note text not null default '' check(length(verification_note)<=500),
 can_pickup boolean not null default false,
 can_edit boolean not null default false,
 is_emergency boolean not null default false,
 status text not null default 'pending' check(status in ('pending','approved','revoked')),
 approved_by uuid references auth.users(id), approved_at timestamptz,
 valid_until date,
 version integer not null default 1 check(version>0),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(profile_id,person_id),
 foreign key(profile_id,organization_id,unit_id) references private.kids_profiles(id,organization_id,unit_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id),
 check((status='approved')=(approved_by is not null and approved_at is not null))
);
create index kids_guardians_person on private.kids_guardians(organization_id,person_id);
create table private.kids_care (
 profile_id uuid primary key,
 organization_id uuid not null, unit_id uuid not null,
 instructions text not null default '' check(length(instructions)<=3000),
 source text not null check(length(btrim(source)) between 3 and 300),
 version integer not null default 1 check(version>0), updated_at timestamptz not null default now(),
 foreign key(profile_id,organization_id,unit_id) references private.kids_profiles(id,organization_id,unit_id)
);
create table private.kids_history (
 id bigint generated always as identity primary key,
 organization_id uuid not null, unit_id uuid not null,
 profile_id uuid, person_id uuid, actor_id uuid not null references auth.users(id),
 action text not null, changed_fields text[] not null default '{}',
 created_at timestamptz not null default now()
);
create index kids_history_scope on private.kids_history(organization_id,unit_id,profile_id,id desc);
create index kids_history_person_scope on private.kids_history(organization_id,unit_id,person_id,id desc);
create table private.kids_requests (
 organization_id uuid not null, actor_id uuid not null, request_id uuid not null,
 fingerprint text not null, result jsonb not null, created_at timestamptz not null default now(),
 primary key(organization_id,actor_id,request_id)
);
alter table private.kids_profiles enable row level security;
alter table private.kids_guardians enable row level security;
alter table private.kids_care enable row level security;
alter table private.kids_history enable row level security;
alter table private.kids_requests enable row level security;
revoke all on private.kids_profiles,private.kids_guardians,private.kids_care,private.kids_history,private.kids_requests from public,anon,authenticated,service_role;
revoke all on sequence private.kids_history_id_seq from public,anon,authenticated,service_role;

create function private.kids_allowed(p_org uuid,p_unit uuid,p_mode text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and private.has_organization_role(p_org,case when p_mode='approve' or p_mode='care' then array['owner','admin','pastor']::public.membership_role[] else array['owner','admin','pastor','secretary']::public.membership_role[] end)
 and private.can_access_unit(p_org,p_unit,case when p_mode='read' then array['read','manage','admin']::public.unit_access_level[] else array['manage','admin']::public.unit_access_level[] end)
 and private.target_unit_module_enabled(p_org,p_unit,'kids')
 and private.target_unit_module_enabled(p_org,p_unit,'people')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id
 where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in ('active','trial'));
$$;
revoke all on function private.kids_allowed(uuid,uuid,text) from public,anon,authenticated,service_role;

create function private.kids_directory(p_org uuid,p_unit uuid,p_profile uuid,p_after uuid,p_search text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare items jsonb; pending_items jsonb='[]'; chosen private.kids_profiles; detail jsonb; can_manage boolean; can_approve boolean; care_allowed boolean;
begin
 perform private.require_confirmed_self_service_email();
 if not coalesce(private.kids_allowed(p_org,p_unit),false) then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_search is null or length(p_search)>100 then raise exception 'invalid_kids_input' using errcode='22023';end if;
 can_manage=private.kids_allowed(p_org,p_unit,'write'); can_approve=private.kids_allowed(p_org,p_unit,'approve'); care_allowed=private.kids_allowed(p_org,p_unit,'care');
 if p_profile is not null then
  select * into chosen from private.kids_profiles where id=p_profile and organization_id=p_org and unit_id=p_unit;
  if not found or not exists(select 1 from public.people where id=chosen.person_id and organization_id=p_org and unit_id=p_unit) then raise exception 'kids_not_found' using errcode='P0002';end if;
  select jsonb_build_object('id',k.id,'personId',p.id,'name',p.full_name,'birthDate',p.birth_date,'personStatus',p.status,'status',k.status,'reviewStatus',k.review_status,'version',k.version,
   'guardians',(select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'personId',a.id,'name',a.full_name,'phone',a.phone,'personStatus',a.status,'relationship',g.relationship,'verificationNote',case when can_approve then g.verification_note else '' end,'canPickup',g.can_pickup,'canEdit',g.can_edit,'isEmergency',g.is_emergency,'status',g.status,'validUntil',g.valid_until,'version',g.version) order by a.full_name,g.id),'[]'::jsonb) from private.kids_guardians g join public.people a on a.id=g.person_id and a.organization_id=g.organization_id where g.profile_id=k.id and a.unit_id=p_unit),
   'care',case when care_allowed then (select jsonb_build_object('instructions',c.instructions,'source',c.source,'version',c.version) from private.kids_care c where c.profile_id=k.id) else null end,
   'history',(select coalesce(jsonb_agg(h.entry order by h.id desc),'[]'::jsonb) from (select e.id,jsonb_build_object('id',e.id::text,'action',e.action,'fields',e.changed_fields,'at',e.created_at,'actor',coalesce(nullif(btrim(u.full_name),''),'Operador')) as entry from private.kids_history e left join public.profiles u on u.id=e.actor_id where (e.profile_id=k.id or e.profile_id is null and e.person_id=k.person_id) and e.organization_id=p_org and e.unit_id=p_unit order by e.id desc limit 50) h)
  ) into detail from private.kids_profiles k join public.people p on p.id=k.person_id and p.organization_id=k.organization_id where k.id=p_profile;
 end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'::jsonb) into items from (
  select k.id,k.person_id as "personId",p.full_name as name,p.birth_date as "birthDate",p.status as "personStatus",k.status,k.review_status as "reviewStatus",k.version,
   (select count(*) from private.kids_guardians g join public.people a on a.id=g.person_id and a.organization_id=g.organization_id where g.profile_id=k.id and k.review_status='approved' and k.status='active' and p.status='active' and g.status='approved' and g.can_pickup and a.status='active' and a.unit_id=p_unit and (g.valid_until is null or g.valid_until>=current_date)) as "authorizedCount"
  from private.kids_profiles k join public.people p on p.id=k.person_id and p.organization_id=k.organization_id
  where k.organization_id=p_org and k.unit_id=p_unit and p.unit_id=p_unit and (p_after is null or k.id>p_after)
  and (p_search='' or strpos(lower(p.full_name),lower(p_search))>0) order by k.id limit 51
 )r;
 if can_manage then
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'::jsonb) into pending_items from
  (select id,full_name as name,birth_date as "birthDate" from public.people where organization_id=p_org and unit_id=p_unit and status='pending' and (p_after is null or id>p_after) order by id limit 51)r;
 end if;
 return jsonb_build_object('unitId',p_unit,'items',case when jsonb_array_length(items)>50 then items-50 else items end,
 'nextCursor',case when jsonb_array_length(items)>50 then items->49->>'id' else null end,
 'canManage',can_manage,'canApprove',can_approve,'canCare',care_allowed,'detail',detail,
 'pendingPeople',case when jsonb_array_length(pending_items)>50 then pending_items-50 else pending_items end,
 'pendingNextCursor',case when jsonb_array_length(pending_items)>50 then pending_items->49->>'id' else null end);
end $$;
revoke all on function private.kids_directory(uuid,uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function private.kids_directory(uuid,uuid,uuid,uuid,text) to authenticated;
create function public.kids_directory(p_organization uuid,p_unit uuid,p_profile uuid default null,p_after uuid default null,p_search text default '') returns jsonb
language sql security invoker set search_path='' as $$ select private.kids_directory(p_organization,p_unit,p_profile,p_after,p_search); $$;
revoke all on function public.kids_directory(uuid,uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function public.kids_directory(uuid,uuid,uuid,uuid,text) to authenticated;

create function private.kids_save(p_org uuid,p_unit uuid,p_request uuid,p_action text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid(); receipt private.kids_requests; fingerprint text; result jsonb; person public.people;
 child private.kids_profiles; guardian private.kids_guardians; care private.kids_care; child_id uuid; fields text[]; next_status text;
begin
 perform private.require_confirmed_self_service_email();
 -- Lock the same authorization rows used by organization/unit governance.
 perform 1 from public.organizations where id=p_org for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for share;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=actor for share;
 perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_org and m.user_id=actor for share of a;
 perform 1 from public.saas_unit_contracts where organization_id=p_org and unit_id=p_unit for share;
 if not coalesce(private.kids_allowed(p_org,p_unit,'write'),false) then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_request is null or p_id is null or p_version is null or p_version<0 or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>12000
 or p_action not in ('profile','review','guardian','care','person','personReview') then raise exception 'invalid_kids_input' using errcode='22023';end if;
 if p_action in ('review','personReview') and not private.kids_allowed(p_org,p_unit,'approve') or p_action='care' and not private.kids_allowed(p_org,p_unit,'care') then raise exception 'kids_access_denied' using errcode='42501';end if;
 fingerprint=encode(extensions.digest(jsonb_build_array(p_unit,p_action,p_id,p_version,p_data)::text,'sha256'),'hex');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text||actor::text||p_request::text,0));
 select * into receipt from private.kids_requests where organization_id=p_org and actor_id=actor and request_id=p_request;
 if found then
  if receipt.fingerprint<>fingerprint then raise exception 'kids_version_conflict' using errcode='40001';end if;
  return receipt.result;
 end if;
 fields=array(select jsonb_object_keys(p_data));
 if p_action='person' then
  if p_version<>0 or not(p_data ?& array['name','birthDate']) or p_data-array['name','birthDate','phone']<>'{}'::jsonb
  or exists(select 1 from jsonb_each(p_data)e where jsonb_typeof(e.value)<>'string')
  or length(btrim(p_data->>'name')) not between 2 and 160 or length(coalesce(p_data->>'phone',''))>40
  or p_data->>'birthDate'='' or (p_data->>'birthDate')::date>current_date or (p_data->>'birthDate')::date<'1900-01-01' then raise exception 'invalid_kids_input' using errcode='22023';end if;
  -- Require explicit review of existing names; never merge identities automatically.
  if exists(select 1 from public.people where organization_id=p_org and unit_id=p_unit and lower(btrim(full_name))=lower(btrim(p_data->>'name')) and status in ('active','pending')) then raise exception 'kids_possible_duplicate' using errcode='23505';end if;
  insert into public.people(id,organization_id,unit_id,full_name,birth_date,phone,journey_status,status)
  values(p_id,p_org,p_unit,btrim(p_data->>'name'),nullif(p_data->>'birthDate','')::date,nullif(btrim(p_data->>'phone'),''),'Visitante','pending');
  result=jsonb_build_object('id',p_id,'version',1);
 elsif p_action='personReview' then
  if p_data<>'{}'::jsonb then raise exception 'invalid_kids_input' using errcode='22023';end if;
  select * into person from public.people where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found or person.status<>'pending' then raise exception 'kids_version_conflict' using errcode='40001';end if;
  update public.people set status='active',updated_at=clock_timestamp() where id=p_id;
  result=jsonb_build_object('id',p_id,'version',1);
 elsif p_action='profile' then
  if not(p_data ?& array['personId','status']) or p_data-array['personId','status']<>'{}'::jsonb
  or jsonb_typeof(p_data->'personId')<>'string' or jsonb_typeof(p_data->'status')<>'string' or p_data->>'status' not in ('active','archived') then raise exception 'invalid_kids_input' using errcode='22023';end if;
  select * into person from public.people where id=(p_data->>'personId')::uuid and organization_id=p_org and unit_id=p_unit and status in ('active','pending') for share;
  if not found or person.birth_date is null or person.birth_date>current_date or person.birth_date<=current_date-interval '18 years' then raise exception 'invalid_child' using errcode='22023';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
  select * into child from private.kids_profiles where id=p_id for update;
  if found then
   if child.organization_id<>p_org or child.unit_id<>p_unit or child.person_id<>person.id then raise exception 'kids_access_denied' using errcode='42501';end if;
   if child.version<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   update private.kids_profiles set status=p_data->>'status',version=version+1,updated_at=clock_timestamp() where id=p_id returning * into child;
  else
   if p_version<>0 or p_data->>'status'<>'active' then raise exception 'kids_version_conflict' using errcode='40001';end if;
   insert into private.kids_profiles(id,organization_id,unit_id,person_id,created_by) values(p_id,p_org,p_unit,person.id,actor) returning * into child;
  end if;
  child_id=child.id; result=jsonb_build_object('id',child.id,'version',child.version);
 else
  child_id=case when p_action in ('review','care') then p_id else (p_data->>'profileId')::uuid end;
  select * into child from private.kids_profiles where id=child_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  perform 1 from public.people where id=child.person_id and organization_id=p_org and unit_id=p_unit and status in ('active','pending') for share;
  if not found then raise exception 'kids_person_scope_changed' using errcode='42501';end if;
  if p_action='review' then
   if not exists(select 1 from public.people where id=child.person_id and organization_id=p_org and unit_id=p_unit and status='active') then raise exception 'kids_person_review_required' using errcode='42501';end if;
   if p_data<>'{}'::jsonb or child.version<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   update private.kids_profiles set review_status='approved',version=version+1,updated_at=clock_timestamp() where id=child.id returning * into child;
   result=jsonb_build_object('id',child.id,'version',child.version);
  elsif p_action='care' then
   if not(p_data ?& array['instructions','source']) or p_data-array['instructions','source']<>'{}'::jsonb or exists(select 1 from jsonb_each(p_data)e where jsonb_typeof(e.value)<>'string')
   or length(p_data->>'instructions')>3000 or length(btrim(p_data->>'source')) not between 3 and 300 then raise exception 'invalid_kids_input' using errcode='22023';end if;
   select * into care from private.kids_care where profile_id=child.id for update;
   if coalesce(care.version,0)<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   insert into private.kids_care(profile_id,organization_id,unit_id,instructions,source) values(child.id,p_org,p_unit,p_data->>'instructions',btrim(p_data->>'source'))
   on conflict(profile_id) do update set instructions=excluded.instructions,source=excluded.source,version=private.kids_care.version+1,updated_at=clock_timestamp() returning * into care;
   result=jsonb_build_object('id',child.id,'version',care.version);
  else
   if not(p_data ?& array['profileId','personId','relationship','verificationNote','canPickup','canEdit','isEmergency','status','validUntil'])
   or p_data-array['profileId','personId','relationship','verificationNote','canPickup','canEdit','isEmergency','status','validUntil']<>'{}'::jsonb
   or exists(select 1 from jsonb_each(p_data)e where case when e.key in ('canPickup','canEdit','isEmergency') then jsonb_typeof(e.value)<>'boolean' else jsonb_typeof(e.value)<>'string' end)
   or length(btrim(p_data->>'relationship')) not between 2 and 80 or p_data->>'status' not in ('pending','approved','revoked') then raise exception 'invalid_kids_input' using errcode='22023';end if;
   select * into person from public.people where id=(p_data->>'personId')::uuid and organization_id=p_org and unit_id=p_unit and status in ('active','pending') for share;
   if not found or person.id=child.person_id then raise exception 'invalid_guardian' using errcode='22023';end if;
   if person.birth_date is not null and person.birth_date>current_date-interval '18 years' then raise exception 'invalid_guardian' using errcode='22023';end if;
   next_status=p_data->>'status';
   if length(p_data->>'verificationNote')>500 or next_status='approved' and (not private.kids_allowed(p_org,p_unit,'approve') or person.status<>'active' or person.birth_date is null or length(btrim(p_data->>'verificationNote'))<10) then raise exception 'guardian_approval_denied' using errcode='42501';end if;
   select * into guardian from private.kids_guardians where id=p_id for update;
   if found and (guardian.organization_id<>p_org or guardian.unit_id<>p_unit or guardian.profile_id<>child.id or guardian.person_id<>person.id) then raise exception 'kids_access_denied' using errcode='42501';end if;
   if coalesce(guardian.version,0)<>p_version then raise exception 'kids_version_conflict' using errcode='40001';end if;
   if guardian.status='approved' and not private.kids_allowed(p_org,p_unit,'approve') and next_status<>'revoked' then raise exception 'guardian_approval_denied' using errcode='42501';end if;
   insert into private.kids_guardians(id,organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,can_edit,is_emergency,status,approved_by,approved_at,valid_until,created_by)
   values(p_id,p_org,p_unit,child.id,person.id,btrim(p_data->>'relationship'),p_data->>'verificationNote',(p_data->>'canPickup')::boolean,(p_data->>'canEdit')::boolean,(p_data->>'isEmergency')::boolean,next_status,case when next_status='approved' then actor end,case when next_status='approved' then clock_timestamp() end,nullif(p_data->>'validUntil','')::date,actor)
   on conflict(id) do update set relationship=excluded.relationship,verification_note=case when private.kids_allowed(p_org,p_unit,'approve') then excluded.verification_note else private.kids_guardians.verification_note end,can_pickup=excluded.can_pickup,can_edit=excluded.can_edit,is_emergency=excluded.is_emergency,status=excluded.status,approved_by=excluded.approved_by,approved_at=excluded.approved_at,valid_until=excluded.valid_until,version=private.kids_guardians.version+1,updated_at=clock_timestamp() returning * into guardian;
   result=jsonb_build_object('id',guardian.id,'version',guardian.version);
  end if;
 end if;
 insert into private.kids_history(organization_id,unit_id,profile_id,person_id,actor_id,action,changed_fields) values(p_org,p_unit,child_id,case when p_action in ('person','personReview') then p_id else child.person_id end,actor,'kids.'||p_action,fields);
 insert into private.kids_requests(organization_id,actor_id,request_id,fingerprint,result) values(p_org,actor,p_request,fingerprint,result);
 return result;
end $$;
revoke all on function private.kids_save(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.kids_save(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.kids_save(p_organization uuid,p_unit uuid,p_request uuid,p_action text,p_id uuid,p_version integer,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.kids_save(p_organization,p_unit,p_request,p_action,p_id,p_version,p_data); $$;
revoke all on function public.kids_save(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.kids_save(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

create function private.kids_choices(p_org uuid,p_unit uuid,p_search text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare items jsonb;
begin
 perform private.require_confirmed_self_service_email();
 if not coalesce(private.kids_allowed(p_org,p_unit),false) then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_search is null or length(btrim(p_search)) not between 2 and 80 then raise exception 'invalid_kids_input' using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.name,r.id),'[]'::jsonb) into items from
 (select id,full_name as name from public.people where organization_id=p_org and unit_id=p_unit and status in ('active','pending') and strpos(lower(full_name),lower(btrim(p_search)))>0 order by full_name,id limit 31)r;
 return jsonb_build_object('unitId',p_unit,'items',case when jsonb_array_length(items)>30 then items-30 else items end,'hasMore',jsonb_array_length(items)>30);
end $$;
revoke all on function private.kids_choices(uuid,uuid,text) from public,anon,service_role;
grant execute on function private.kids_choices(uuid,uuid,text) to authenticated;
create function public.kids_choices(p_organization uuid,p_unit uuid,p_search text) returns jsonb
language sql security invoker set search_path='' as $$select private.kids_choices(p_organization,p_unit,p_search);$$;
revoke all on function public.kids_choices(uuid,uuid,text) from public,anon,service_role;
grant execute on function public.kids_choices(uuid,uuid,text) to authenticated;
