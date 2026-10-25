set local lock_timeout='5s';
create table private.community_prayers(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 user_id uuid not null references auth.users(id),person_id uuid not null references public.people(id),nonce text not null check(length(nonce) between 10 and 100),
 category text not null check(category in('Espiritual','Família','Saúde','Trabalho','Finanças','Outros')),body text not null check(length(body) between 10 and 4000),allow_contact boolean not null default false,
 status text not null default 'pending' check(status in('pending','care','completed','cancelled')),reply text not null default '' check(length(reply)<=2000),version integer not null default 1,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),unique(organization_id,user_id,nonce),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create table private.community_testimonies(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 user_id uuid not null references auth.users(id),person_id uuid not null references public.people(id),nonce text not null check(length(nonce) between 10 and 100),
 title text not null check(length(title) between 2 and 160),category text not null check(category in('Espiritual','Família','Saúde','Trabalho','Finanças','Outros')),body text not null check(length(body) between 10 and 4000),
 consent boolean not null check(consent),show_name boolean not null default false,author_name text not null,
 status text not null default 'pending' check(status in('pending','published','rejected','withdrawn')),reason text not null default '' check(length(reason)<=2000),version integer not null default 1,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),unique(organization_id,user_id,nonce),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create table private.community_groups(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 name text not null check(length(name) between 2 and 160),description text not null default '' check(length(description)<=2000),kind text not null check(kind in('ministry','department')),
 active boolean not null default true,accepting boolean not null default true,version integer not null default 1,nonce text not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 unique(organization_id,created_by,nonce),unique(id,organization_id,unit_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create table private.community_participation(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,group_id uuid not null,
 user_id uuid not null references auth.users(id),person_id uuid not null references public.people(id),status text not null default 'pending' check(status in('pending','approved','rejected','left')),
 reason text not null default '' check(length(reason)<=2000),version integer not null default 1,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 unique(group_id,user_id),foreign key(group_id,organization_id,unit_id) references private.community_groups(id,organization_id,unit_id)
);
create table private.community_notes(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),nonce text not null,
 title text not null check(length(title) between 2 and 160),body text not null check(length(body) between 1 and 12000),archived boolean not null default false,version integer not null default 1,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),unique(organization_id,user_id,nonce)
);
create index community_prayers_scope on private.community_prayers(unit_id,organization_id,status,created_at,id);
create index community_prayers_user on private.community_prayers(user_id,organization_id,created_at,id);
create index community_prayers_person on private.community_prayers(person_id);
create index community_testimonies_scope on private.community_testimonies(unit_id,organization_id,status,created_at,id);
create index community_testimonies_user on private.community_testimonies(user_id,organization_id,created_at,id);
create index community_testimonies_person on private.community_testimonies(person_id);
create index community_groups_scope on private.community_groups(unit_id,organization_id,active,name,id);
create index community_groups_creator on private.community_groups(created_by);
create index community_participation_scope on private.community_participation(unit_id,organization_id,status,created_at,id);
create index community_participation_group on private.community_participation(group_id,organization_id,unit_id);
create index community_participation_user on private.community_participation(user_id,organization_id,created_at,id);
create index community_participation_person on private.community_participation(person_id);
create index community_notes_user on private.community_notes(user_id,organization_id,archived,updated_at,id);
alter table private.community_prayers enable row level security;
alter table private.community_testimonies enable row level security;
alter table private.community_groups enable row level security;
alter table private.community_participation enable row level security;
alter table private.community_notes enable row level security;
revoke all on private.community_prayers,private.community_testimonies,private.community_groups,private.community_participation,private.community_notes from public,anon,authenticated,service_role;

create function private.community_scope(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations o join public.organization_units u on u.organization_id=o.id where o.id=p_org and o.status in('active','trial') and u.id=p_unit and u.status='active');
$$;
revoke all on function private.community_scope(uuid,uuid) from public,anon,authenticated,service_role;
create function private.community_identity(p_org uuid,p_unit uuid,p_person boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare person uuid;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in('active','trial') for update;
 if not found then raise exception 'community_denied' using errcode='42501';end if;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active' for update;
 if not found or p_unit is not null and not private.community_scope(p_org,p_unit) then raise exception 'community_denied' using errcode='42501';end if;
 if p_person then
  if (select count(*) from public.people where organization_id=p_org and auth_user_id=auth.uid() and status='active')<>1 then raise exception 'community_identity_pending' using errcode='42501';end if;
  select id into person from public.people where organization_id=p_org and auth_user_id=auth.uid() and status='active' for share;
 end if;
 return person;
end $$;
revoke all on function private.community_identity(uuid,uuid,boolean) from public,anon,authenticated,service_role;

create function member_app_api.community_public(p_org uuid,p_unit uuid,p_kind text,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if p_offset is null or p_offset not between 0 and 100000 or p_kind is null or p_kind not in('testimonies','groups') then raise exception 'invalid_community' using errcode='22023';end if;
 if not private.community_scope(p_org,p_unit) then return jsonb_build_object('items','[]'::jsonb,'more',false);end if;
 if p_kind='testimonies' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select t.id,t.title,t.category,t.body,case when t.show_name then t.author_name else 'Membro da igreja' end author,t.updated_at from private.community_testimonies t where t.organization_id=p_org and t.unit_id=p_unit and t.status='published' and t.consent order by t.created_at desc,t.id limit 21 offset p_offset)q;
 else
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,name,description,kind,accepting from private.community_groups where organization_id=p_org and unit_id=p_unit and active order by created_at desc,id limit 21 offset p_offset)q;
 end if;
 return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
end $$;
revoke all on function member_app_api.community_public(uuid,uuid,text,integer) from public,service_role;
grant execute on function member_app_api.community_public(uuid,uuid,text,integer) to anon,authenticated;
create function public.member_community_public(p_org uuid,p_unit uuid,p_kind text,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.community_public(p_org,p_unit,p_kind,p_offset)$$;
revoke all on function public.member_community_public(uuid,uuid,text,integer) from public,service_role;
grant execute on function public.member_community_public(uuid,uuid,text,integer) to anon,authenticated;

create function private.member_community_self(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare person uuid;pr private.community_prayers;te private.community_testimonies;gr private.community_groups;pa private.community_participation;nt private.community_notes;rows jsonb;result_id uuid;v integer;
begin
 person:=private.community_identity(p_org,p_unit,p_action in('prayer.create','testimony.create','group.request'));
 if p_action is null or p_offset is null or p_offset not between 0 and 100000 or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_community' using errcode='22023';end if;
 if exists(select 1 from jsonb_each(p_data) j where j.key in('nonce','title','body','category','reply','reason','name','description','kind','status') and jsonb_typeof(j.value) is distinct from 'string') then raise exception 'invalid_community' using errcode='22023';end if;
 if p_action in('prayers','testimonies','groups','notes','archived') then
  if p_action='prayers' then select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,category,body,allow_contact,status,reply,version,created_at,updated_at from private.community_prayers where organization_id=p_org and unit_id=p_unit and user_id=auth.uid() order by created_at desc,id limit 21 offset p_offset)q;
  elsif p_action='testimonies' then select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,title,category,body,show_name,status,reason,version,created_at,updated_at from private.community_testimonies where organization_id=p_org and unit_id=p_unit and user_id=auth.uid() order by created_at desc,id limit 21 offset p_offset)q;
  elsif p_action='groups' then select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select a.id,a.group_id,g.name,g.active,a.status,a.reason,a.version,a.updated_at from private.community_participation a join private.community_groups g on g.id=a.group_id where a.organization_id=p_org and a.unit_id=p_unit and a.user_id=auth.uid() order by a.created_at desc,a.id limit 21 offset p_offset)q;
  else select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,title,body,archived,version,created_at,updated_at from private.community_notes where organization_id=p_org and user_id=auth.uid() and archived=(p_action='archived') order by created_at desc,id limit 21 offset p_offset)q;end if;
  return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
 end if;
 if p_action in('prayer.create','testimony.create','note.create') then
  if length(coalesce(p_data->>'nonce','')) not between 10 and 100 or p_data->>'nonce' !~ '^[a-zA-Z0-9_-]+$' then raise exception 'invalid_community' using errcode='22023';end if;
 end if;
 if p_action='prayer.create' then
  if p_unit is null or p_data-array['nonce','category','body','allowContact']<>'{}' or not(p_data ?& array['category','body','allowContact']) or jsonb_typeof(p_data->'allowContact')<>'boolean' then raise exception 'invalid_community' using errcode='22023';end if;
  insert into private.community_prayers(organization_id,unit_id,user_id,person_id,nonce,category,body,allow_contact) values(p_org,p_unit,auth.uid(),person,p_data->>'nonce',p_data->>'category',btrim(p_data->>'body'),(p_data->>'allowContact')::boolean) on conflict(organization_id,user_id,nonce) do nothing returning id,version into result_id,v;
  if result_id is null then select id,version into result_id,v from private.community_prayers where organization_id=p_org and user_id=auth.uid() and nonce=p_data->>'nonce';return jsonb_build_object('ok',true,'id',result_id,'version',v);end if;
 elsif p_action='prayer.cancel' then
  select * into pr from private.community_prayers where id=p_id and organization_id=p_org and user_id=auth.uid() for update;
  if not found then raise exception 'community_denied' using errcode='42501';end if;
  if pr.version is distinct from p_version or pr.status not in('pending','care') then raise exception 'community_changed' using errcode='40001';end if;
  update private.community_prayers set status='cancelled',allow_contact=false,version=version+1,updated_at=clock_timestamp() where id=pr.id returning id,version into result_id,v;
 elsif p_action='testimony.create' then
  if p_unit is null or p_data-array['nonce','title','body','category','consent','showName']<>'{}' or p_data->'consent' is distinct from 'true'::jsonb or jsonb_typeof(p_data->'showName') is distinct from 'boolean' then raise exception 'community_consent' using errcode='22023';end if;
  insert into private.community_testimonies(organization_id,unit_id,user_id,person_id,nonce,title,category,body,consent,show_name,author_name) select p_org,p_unit,auth.uid(),person,p_data->>'nonce',btrim(p_data->>'title'),p_data->>'category',btrim(p_data->>'body'),true,(p_data->>'showName')::boolean,full_name from public.people where id=person on conflict(organization_id,user_id,nonce) do nothing returning id,version into result_id,v;
  if result_id is null then select id,version into result_id,v from private.community_testimonies where organization_id=p_org and user_id=auth.uid() and nonce=p_data->>'nonce';return jsonb_build_object('ok',true,'id',result_id,'version',v);end if;
 elsif p_action='testimony.withdraw' then
  select * into te from private.community_testimonies where id=p_id and organization_id=p_org and user_id=auth.uid() for update;
  if not found then raise exception 'community_denied' using errcode='42501';end if;
  if te.version is distinct from p_version or te.status='withdrawn' then raise exception 'community_changed' using errcode='40001';end if;
  update private.community_testimonies set status='withdrawn',version=version+1,updated_at=clock_timestamp() where id=te.id returning id,version into result_id,v;
 elsif p_action='group.request' then
  select * into gr from private.community_groups where id=p_id and organization_id=p_org and unit_id=p_unit and active and accepting for update;
  if not found then raise exception 'community_group_closed' using errcode='40001';end if;
  select * into pa from private.community_participation where group_id=gr.id and user_id=auth.uid() for update;
  if pa.status in('pending','approved') then return jsonb_build_object('ok',true,'id',pa.id,'version',pa.version);end if;
  if pa.id is null then insert into private.community_participation(organization_id,unit_id,group_id,user_id,person_id) values(p_org,p_unit,gr.id,auth.uid(),person) returning id,version into result_id,v;
  else update private.community_participation set status='pending',person_id=person,reason='',version=version+1,updated_at=clock_timestamp() where id=pa.id returning id,version into result_id,v;end if;
 elsif p_action='group.leave' then
  select * into pa from private.community_participation where id=p_id and organization_id=p_org and user_id=auth.uid() for update;
  if not found then raise exception 'community_denied' using errcode='42501';end if;
  if pa.version is distinct from p_version or pa.status not in('pending','approved') then raise exception 'community_changed' using errcode='40001';end if;
  update private.community_participation set status='left',reason='',version=version+1,updated_at=clock_timestamp() where id=pa.id returning id,version into result_id,v;
 elsif p_action in('note.create','note.edit','note.archive','note.restore') then
  if p_action='note.create' then
   if p_data-array['nonce','title','body']<>'{}' then raise exception 'invalid_community' using errcode='22023';end if;
   insert into private.community_notes(organization_id,user_id,nonce,title,body) values(p_org,auth.uid(),p_data->>'nonce',btrim(p_data->>'title'),p_data->>'body') on conflict(organization_id,user_id,nonce) do nothing returning id,version into result_id,v;
   if result_id is null then select id,version into result_id,v from private.community_notes where organization_id=p_org and user_id=auth.uid() and nonce=p_data->>'nonce';end if;
  else
   select * into nt from private.community_notes where id=p_id and organization_id=p_org and user_id=auth.uid() for update;
   if not found then raise exception 'community_denied' using errcode='42501';end if;
   if nt.version is distinct from p_version then raise exception 'community_changed' using errcode='40001';end if;
   if p_action='note.edit' then
    if p_data-array['title','body']<>'{}' or not(p_data ?& array['title','body']) then raise exception 'invalid_community' using errcode='22023';end if;
    update private.community_notes set title=btrim(p_data->>'title'),body=p_data->>'body',version=version+1,updated_at=clock_timestamp() where id=nt.id returning id,version into result_id,v;
   else update private.community_notes set archived=(p_action='note.archive'),version=version+1,updated_at=clock_timestamp() where id=nt.id returning id,version into result_id,v;end if;
  end if;
  -- Notes never enter staff lists, notifications or content-bearing audit metadata.
  return jsonb_build_object('ok',true,'id',result_id,'version',v);
 else raise exception 'invalid_community' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.community.'||p_action,'community',result_id);
 return jsonb_build_object('ok',true,'id',result_id,'version',v);
end $$;
revoke all on function private.member_community_self(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function private.member_community_self(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function public.member_community_self(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.member_community_self(p_org,p_unit,p_action,p_id,p_version,p_data,p_offset)$$;
revoke all on function public.member_community_self(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function public.member_community_self(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;

create function private.member_community_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;pr private.community_prayers;te private.community_testimonies;gr private.community_groups;pa private.community_participation;result_id uuid;v integer;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) or p_unit is null then raise exception 'community_denied' using errcode='42501';end if;
 if p_action is null or p_offset is null or p_offset not between 0 and 100000 or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_community' using errcode='22023';end if;
 if exists(select 1 from jsonb_each(p_data) j where j.key in('nonce','title','body','category','reply','reason','name','description','kind','status') and jsonb_typeof(j.value) is distinct from 'string') then raise exception 'invalid_community' using errcode='22023';end if;
 if p_action in('prayers','testimonies','groups','participants') then
  if p_action='prayers' then select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select a.id,p.full_name name,case when a.allow_contact and a.status in('pending','care') then p.phone else null end phone,a.category,a.body,a.allow_contact,a.status,a.reply,a.version,a.created_at from private.community_prayers a join public.people p on p.id=a.person_id where a.organization_id=p_org and a.unit_id=p_unit order by a.created_at desc,a.id limit 21 offset p_offset)q;
  elsif p_action='testimonies' then select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,title,category,body,author_name name,show_name,consent,status,reason,version,created_at from private.community_testimonies where organization_id=p_org and unit_id=p_unit order by created_at desc,id limit 21 offset p_offset)q;
  elsif p_action='groups' then select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,name,description,kind,active,accepting,version from private.community_groups where organization_id=p_org and unit_id=p_unit order by created_at desc,id limit 21 offset p_offset)q;
  else select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select a.id,a.group_id,g.name group_name,p.full_name name,a.person_id,a.status,a.reason,a.version,a.created_at from private.community_participation a join private.community_groups g on g.id=a.group_id join public.people p on p.id=a.person_id where a.organization_id=p_org and a.unit_id=p_unit order by a.created_at desc,a.id limit 21 offset p_offset)q;end if;
  return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
 end if;
 if p_action='prayer.review' then
  select * into pr from private.community_prayers where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'community_denied' using errcode='42501';end if;
  if pr.version is distinct from p_version or pr.status='cancelled' then raise exception 'community_changed' using errcode='40001';end if;
  if p_data-array['status','reply']<>'{}' or p_data->>'status' not in('care','completed') or jsonb_typeof(p_data->'reply') is distinct from 'string' then raise exception 'invalid_community' using errcode='22023';end if;
  update private.community_prayers set status=p_data->>'status',reply=p_data->>'reply',version=version+1,updated_at=clock_timestamp() where id=pr.id returning id,version into result_id,v;
 elsif p_action='testimony.review' then
  select * into te from private.community_testimonies where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'community_denied' using errcode='42501';end if;
  if te.version is distinct from p_version or te.status='withdrawn' then raise exception 'community_changed' using errcode='40001';end if;
  if p_data-array['status','reason']<>'{}' or p_data->>'status' not in('published','rejected') or jsonb_typeof(p_data->'reason') is distinct from 'string' or p_data->>'status'='rejected' and length(btrim(p_data->>'reason'))<3 or not te.consent then raise exception 'invalid_community' using errcode='22023';end if;
  update private.community_testimonies set status=p_data->>'status',reason=p_data->>'reason',version=version+1,updated_at=clock_timestamp() where id=te.id returning id,version into result_id,v;
 elsif p_action in('group.create','group.edit') then
  if p_data-array['nonce','name','description','kind','active','accepting']<>'{}' or length(btrim(p_data->>'name')) not between 2 and 160 or length(p_data->>'description')>2000 or p_data->>'kind' not in('ministry','department') or jsonb_typeof(p_data->'active') is distinct from 'boolean' or jsonb_typeof(p_data->'accepting') is distinct from 'boolean' then raise exception 'invalid_community' using errcode='22023';end if;
  if p_action='group.create' then
   if length(coalesce(p_data->>'nonce','')) not between 10 and 100 then raise exception 'invalid_community' using errcode='22023';end if;
   insert into private.community_groups(organization_id,unit_id,name,description,kind,active,accepting,created_by,nonce) values(p_org,p_unit,btrim(p_data->>'name'),p_data->>'description',p_data->>'kind',(p_data->>'active')::boolean,(p_data->>'accepting')::boolean,auth.uid(),p_data->>'nonce') on conflict(organization_id,created_by,nonce) do nothing returning id,version into result_id,v;
   if result_id is null then select id,version into result_id,v from private.community_groups where organization_id=p_org and created_by=auth.uid() and nonce=p_data->>'nonce';return jsonb_build_object('ok',true,'id',result_id,'version',v);end if;
  else
   select * into gr from private.community_groups where id=p_id and organization_id=p_org and unit_id=p_unit for update;
   if not found then raise exception 'community_denied' using errcode='42501';end if;
   if gr.version is distinct from p_version then raise exception 'community_changed' using errcode='40001';end if;
   update private.community_groups set name=btrim(p_data->>'name'),description=p_data->>'description',kind=p_data->>'kind',active=(p_data->>'active')::boolean,accepting=(p_data->>'accepting')::boolean,version=version+1,updated_at=clock_timestamp() where id=gr.id returning id,version into result_id,v;
  end if;
 elsif p_action='participant.review' then
  select * into pa from private.community_participation where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'community_denied' using errcode='42501';end if;
  if pa.version is distinct from p_version or pa.status not in('pending','approved') then raise exception 'community_changed' using errcode='40001';end if;
  if p_data-array['status','reason']<>'{}' or p_data->>'status' not in('approved','rejected') or jsonb_typeof(p_data->'reason') is distinct from 'string' or p_data->>'status'='rejected' and length(btrim(p_data->>'reason'))<3 then raise exception 'invalid_community' using errcode='22023';end if;
  if p_data->>'status'='approved' and (not exists(select 1 from private.community_groups where id=pa.group_id and active) or not exists(select 1 from public.people p join public.organization_memberships m on m.user_id=pa.user_id and m.organization_id=p_org join auth.users u on u.id=m.user_id where p.id=pa.person_id and p.organization_id=p_org and p.auth_user_id=pa.user_id and p.status='active' and m.status='active' and u.deleted_at is null and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now()))) then raise exception 'community_identity_pending' using errcode='42501';end if;
  update private.community_participation set status=p_data->>'status',reason=p_data->>'reason',version=version+1,updated_at=clock_timestamp() where id=pa.id returning id,version into result_id,v;
 else raise exception 'invalid_community' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.community.'||p_action,'community',result_id);
 return jsonb_build_object('ok',true,'id',result_id,'version',v);
end $$;
revoke all on function private.member_community_admin(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function private.member_community_admin(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function public.member_community_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.member_community_admin(p_org,p_unit,p_action,p_id,p_version,p_data,p_offset)$$;
revoke all on function public.member_community_admin(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function public.member_community_admin(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;

create function private.member_inbox_before_community(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $
 select * from(
 select 'post:'||p.id as message_key,p.title,p.body,p.created_at as occurred_at,'content'::text as target,p.id as target_id from private.member_publications p
 join public.organization_units u on u.id=p.unit_id and u.organization_id=p.organization_id and u.status='active'
 where p.organization_id=p_org and p.unit_id=p_unit and p.published and p.created_at>now()-interval '90 days'
 union all
 select 'event:'||e.id||':'||e.version,e.title,case when e.status='cancelled' then 'Evento cancelado pela igreja.' else 'Programação publicada ou atualizada. Confira data e local.' end,e.updated_at,'agenda',e.id
 from private.church_app_events e where e.organization_id=p_org and e.unit_id=p_unit and e.status in('published','cancelled') and e.updated_at>now()-interval '90 days' and private.member_event_enabled(p_org,p_unit)
 union all
 select 'ticket:'||r.id||':'||r.version||':'||e.version,e.title,case when e.status='cancelled' then 'Evento cancelado. Seu ticket não permite entrada.' when r.status='cancelled' then 'Sua inscrição foi cancelada.' when r.checked_in_at is not null then 'Sua entrada foi confirmada.' else 'Sua inscrição gratuita está confirmada. Consulte seu ticket.' end,greatest(r.updated_at,e.updated_at),'ticket',r.id
 from private.church_app_registrations r join private.church_app_events e on e.id=r.event_id where r.organization_id=p_org and r.user_id=auth.uid()
 union all
 select 'profile:'||r.id||':'||r.status,'Revisão do cadastro',coalesce(r.reason,'Sua solicitação foi revisada.'),r.reviewed_at,'profile',r.id from private.member_profile_requests r where r.organization_id=p_org and r.user_id=auth.uid() and r.status<>'pending'
 union all
 select 'transfer:'||r.id||':'||r.status,'Transferência de igreja',case when r.status='approved' then 'Transferência aprovada. ' when r.status='rejected' then 'Transferência recusada. ' else 'Solicitação cancelada. ' end||r.reason,r.reviewed_at,'church',r.id from private.member_church_transfers r where r.organization_id=p_org and r.user_id=auth.uid() and r.status<>'pending'
 )q order by occurred_at desc nulls last,message_key limit 100;
$;
revoke all on function private.member_inbox_before_community(uuid,uuid) from public,anon,authenticated,service_role;


create or replace function private.member_inbox_rows(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $$
 select * from(
 select * from private.member_inbox_before_community(p_org,p_unit)
 union all select 'prayer:'||id||':'||version,'Pedido de oração atualizado',case status when 'care' then 'A equipe está acompanhando seu pedido.' when 'completed' then 'A equipe concluiu o acompanhamento.' else 'Pedido cancelado.' end,updated_at,'prayers',id from private.community_prayers where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 union all select 'testimony:'||id||':'||version,'Seu testemunho',case status when 'published' then 'Seu testemunho foi aprovado e publicado.' when 'rejected' then 'Sua publicação não foi aprovada. Consulte o motivo.' else 'Publicação retirada a seu pedido.' end,updated_at,'testimonies',id from private.community_testimonies where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 union all select 'participation:'||id||':'||version,'Participação em ministério',case status when 'approved' then 'Sua participação foi aprovada.' when 'rejected' then 'Solicitação revisada. Consulte o motivo.' else 'Sua participação foi encerrada.' end,updated_at,'groups',id from private.community_participation where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 )q order by occurred_at desc nulls last,message_key limit 100;
$$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated,service_role;
