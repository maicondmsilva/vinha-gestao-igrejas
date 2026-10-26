set local lock_timeout='5s';
create table private.ministry_app_openings(
 organization_id uuid primary key references public.organizations(id),kind text not null default 'none' check(kind in('none','image','video')),
 url text not null default '' check(length(url)<=2000),title text not null default '' check(length(title)<=160),seconds integer not null default 5 check(seconds between 1 and 15),
 version integer not null default 1,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create index ministry_app_openings_actor on private.ministry_app_openings(updated_by);
create table private.ministry_media(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 kind text not null check(kind in('video','live')),title text not null check(length(btrim(title)) between 2 and 160),description text not null default '' check(length(description)<=4000),
 source text not null check(length(source) between 10 and 2000),poster text not null default '' check(length(poster)<=2000),
 status text not null default 'draft' check(status in('draft','published','archived')),live_state text not null default 'scheduled' check(live_state in('scheduled','live','ended')),
 starts_at timestamptz,ends_at timestamptz,download_allowed boolean not null default false,
 version integer not null default 1,created_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 unique(id,organization_id,unit_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),check(ends_at is null or starts_at is not null and ends_at>starts_at)
);
create index ministry_media_scope on private.ministry_media(organization_id,unit_id,status,updated_at desc,id);
create index ministry_media_unit on private.ministry_media(unit_id,organization_id);
create index ministry_media_actor on private.ministry_media(created_by);
alter table private.ministry_media add unique(id,organization_id);
create table private.ministry_media_progress(
 organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),media_id uuid not null,
 media_version integer not null,position_seconds integer not null default 0 check(position_seconds between 0 and 864000),favorite boolean not null default false,
 updated_at timestamptz not null default now(),primary key(user_id,media_id),foreign key(media_id,organization_id) references private.ministry_media(id,organization_id)
);
-- A composite candidate key keeps private progress in the same ministry.
create index ministry_media_progress_org on private.ministry_media_progress(organization_id);
create index ministry_media_progress_media on private.ministry_media_progress(media_id,organization_id);
create table private.ministry_media_watchers(
 media_id uuid not null references private.ministry_media(id),user_id uuid not null references auth.users(id),seen_at timestamptz not null default now(),primary key(media_id,user_id)
);
create index ministry_media_watchers_user on private.ministry_media_watchers(user_id);
alter table private.ministry_app_openings enable row level security;
alter table private.ministry_media enable row level security;
alter table private.ministry_media_progress enable row level security;
alter table private.ministry_media_watchers enable row level security;
revoke all on private.ministry_app_openings,private.ministry_media,private.ministry_media_progress,private.ministry_media_watchers from public,anon,authenticated,service_role;

create function private.ministry_module_public(p_org uuid,p_unit uuid,p_module text) returns boolean language sql stable security definer set search_path='' as $$
 select private.community_scope(p_org,p_unit) and exists(select 1 from public.saas_module_catalog where code=p_module)
 and not exists(select 1 from public.saas_unit_contracts c where c.organization_id=p_org and c.unit_id=p_unit and c.status<>'draft' and not(c.status='active' and case when c.module_decisions?p_module then c.module_decisions->p_module='true'::jsonb else exists(select 1 from public.saas_plan_modules pm where pm.plan_id=c.plan_id and pm.module_code=p_module and included) end));
$$;
revoke all on function private.ministry_module_public(uuid,uuid,text) from public,anon,authenticated,service_role;
create function private.ministry_public_url(value text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(length(value) between 10 and 2000 and value~'^https://[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}(/[^[:space:]]*)?$' and value!~'[<>"\\]' and value!~'^https://[^/]*@',false);
$$;
revoke all on function private.ministry_public_url(text) from public,anon,authenticated,service_role;

create function member_app_api.media(p_org uuid,p_unit uuid,p_kind text default 'video',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_kind not in('video','live') or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_media' using errcode='22023';end if;
 if not private.ministry_module_public(p_org,p_unit,case when p_kind='live' then 'broadcasts' else 'communication' end) then return jsonb_build_object('items','[]'::jsonb,'available',false);end if;
 return jsonb_build_object('available',true,'items',coalesce((select jsonb_agg(to_jsonb(q)) from(select id,unit_id,kind,title,description,source,poster,live_state,starts_at,ends_at,download_allowed,version from private.ministry_media where organization_id=p_org and unit_id=p_unit and kind=p_kind and status='published' order by case live_state when 'live' then 0 when 'scheduled' then 1 else 2 end,updated_at desc,id limit 20 offset p_offset)q),'[]'));
end $$;
revoke all on function member_app_api.media(uuid,uuid,text,integer) from public,service_role;
grant execute on function member_app_api.media(uuid,uuid,text,integer) to anon,authenticated;
create function public.member_media(p_org uuid,p_unit uuid,p_kind text default 'video',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select member_app_api.media(p_org,p_unit,p_kind,p_offset)$$;
revoke all on function public.member_media(uuid,uuid,text,integer) from public,service_role;
grant execute on function public.member_media(uuid,uuid,text,integer) to anon,authenticated;
create function member_app_api.opening(p_org uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('kind',a.kind,'url',a.url,'title',a.title,'seconds',a.seconds,'version',a.version) from private.ministry_app_openings a join public.organizations o on o.id=a.organization_id where o.id=p_org and o.status in('active','trial')),jsonb_build_object('kind','none','url','','title','','seconds',5,'version',0));
$$;
revoke all on function member_app_api.opening(uuid) from public,service_role;
grant execute on function member_app_api.opening(uuid) to anon,authenticated;
create function public.member_app_opening(p_org uuid) returns jsonb language sql security invoker set search_path='' as $$select member_app_api.opening(p_org)$$;
revoke all on function public.member_app_opening(uuid) from public,service_role;
grant execute on function public.member_app_opening(uuid) to anon,authenticated;

create function private.ministry_media_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare item private.ministry_media;opening private.ministry_app_openings;module text;v_kind text;new_id uuid;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'media_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>12000 then raise exception 'invalid_media' using errcode='22023';end if;
 if p_action='list' then
  return jsonb_build_object('opening',member_app_api.opening(p_org),'canOpening',private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]),'items',coalesce((select jsonb_agg(to_jsonb(q)) from(select m.*,(select count(*) from private.ministry_media_watchers w where w.media_id=m.id and w.seen_at>now()-interval '2 minutes') as connected_accounts from private.ministry_media m where m.organization_id=p_org and m.unit_id=p_unit and private.ministry_module_public(p_org,p_unit,case when m.kind='live' then 'broadcasts' else 'communication' end) order by m.updated_at desc limit 100)q),'[]'));
 elsif p_action='opening' then
  if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'media_denied' using errcode='42501';end if;
  if p_data-array['kind','url','title','seconds']<>'{}' or p_data->>'kind' not in('none','image','video') or length(coalesce(p_data->>'title',''))>160 or (p_data->>'seconds')::integer not between 1 and 15 or p_data->>'kind'<>'none' and not private.ministry_public_url(p_data->>'url') then raise exception 'invalid_media' using errcode='22023';end if;
  if p_data->>'kind'='video' and p_data->>'url' !~* '\.mp4(\?[^[:space:]]*)?$' then raise exception 'invalid_media' using errcode='22023';end if;
  select * into opening from private.ministry_app_openings where organization_id=p_org for update;
  if coalesce(opening.version,0) is distinct from p_version then raise exception 'media_changed' using errcode='40001';end if;
  insert into private.ministry_app_openings(organization_id,kind,url,title,seconds,updated_by) values(p_org,p_data->>'kind',case when p_data->>'kind'='none' then '' else p_data->>'url' end,coalesce(p_data->>'title',''),(p_data->>'seconds')::integer,auth.uid()) on conflict(organization_id) do update set kind=excluded.kind,url=excluded.url,title=excluded.title,seconds=excluded.seconds,version=ministry_app_openings.version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where ministry_app_openings.version=p_version;
  if not found then raise exception 'media_changed' using errcode='40001';end if;new_id:=p_org;
 else
  if p_action not in('save','publish','archive','live','end') or p_id is null then raise exception 'invalid_media' using errcode='22023';end if;
  select * into item from private.ministry_media where id=p_id for update;
  if found and (item.organization_id<>p_org or item.unit_id<>p_unit) then raise exception 'media_denied' using errcode='42501';end if;
  if coalesce(item.version,0) is distinct from p_version then raise exception 'media_changed' using errcode='40001';end if;
  v_kind:=case when p_action='save' then p_data->>'kind' else item.kind end;module:=case when v_kind='live' then 'broadcasts' else 'communication' end;
  if not private.ministry_module_public(p_org,p_unit,module) then raise exception 'media_denied' using errcode='42501';end if;
  if p_action='save' then
   if p_data-array['kind','title','description','source','poster','starts','ends','download']<>'{}' or v_kind not in('video','live') or not private.ministry_public_url(p_data->>'source') or length(btrim(coalesce(p_data->>'title',''))) not between 2 and 160 or length(coalesce(p_data->>'description',''))>4000 or coalesce(p_data->>'poster','')<>'' and not private.ministry_public_url(p_data->>'poster') or jsonb_typeof(p_data->'download') is distinct from 'boolean' then raise exception 'invalid_media' using errcode='22023';end if;
   if (p_data->>'download')::boolean and (v_kind<>'video' or p_data->>'source'!~* '\.mp4(\?[^[:space:]]*)?$') then raise exception 'invalid_media' using errcode='22023';end if;
   insert into private.ministry_media(id,organization_id,unit_id,kind,title,description,source,poster,starts_at,ends_at,download_allowed,created_by) values(p_id,p_org,p_unit,v_kind,btrim(p_data->>'title'),coalesce(p_data->>'description',''),p_data->>'source',coalesce(p_data->>'poster',''),nullif(p_data->>'starts','')::timestamptz,nullif(p_data->>'ends','')::timestamptz,(p_data->>'download')::boolean,auth.uid()) on conflict(id) do update set kind=excluded.kind,title=excluded.title,description=excluded.description,source=excluded.source,poster=excluded.poster,starts_at=excluded.starts_at,ends_at=excluded.ends_at,download_allowed=excluded.download_allowed,version=ministry_media.version+1,updated_at=clock_timestamp() where ministry_media.version=p_version;
   if not found then raise exception 'media_changed' using errcode='40001';end if;
  else
   if item.id is null or p_data<>'{}' then raise exception 'invalid_media' using errcode='22023';end if;
   if p_action in('live','end') and (item.kind<>'live' or item.status<>'published') then raise exception 'invalid_media' using errcode='22023';end if;
   update private.ministry_media set status=case p_action when 'publish' then 'published' when 'archive' then 'archived' else status end,live_state=case p_action when 'live' then 'live' when 'end' then 'ended' else live_state end,version=version+1,updated_at=clock_timestamp() where id=p_id;
  end if;new_id:=p_id;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'media.'||p_action,'ministry_media',new_id::text,jsonb_build_object('unit',p_unit));return jsonb_build_object('ok',true,'id',new_id);
end $$;
revoke all on function private.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.ministry_media_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.ministry_media_admin(p_org,p_unit,p_action,p_id,p_version,p_data)$$;
revoke all on function public.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;

create function private.member_media_self(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare item private.ministry_media;
begin
 perform private.community_identity(p_org,p_unit,false);
 if p_action='history' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q)) from(select p.media_id,p.favorite,case when p.media_version=m.version then p.position_seconds else 0 end as position_seconds from private.ministry_media_progress p join private.ministry_media m on m.id=p.media_id where p.organization_id=p_org and p.user_id=auth.uid() and m.unit_id=p_unit and m.status='published' and private.ministry_module_public(p_org,p_unit,case when m.kind='live' then 'broadcasts' else 'communication' end) order by p.updated_at desc limit 100)q),'[]'));end if;
 select * into item from private.ministry_media where id=p_id and organization_id=p_org and unit_id=p_unit and status='published' for share;
 if not found or not private.ministry_module_public(p_org,p_unit,case when item.kind='live' then 'broadcasts' else 'communication' end) then raise exception 'media_denied' using errcode='42501';end if;
 if p_action='download' then
  if not item.download_allowed or item.kind<>'video' then raise exception 'media_denied' using errcode='42501';end if;
  return jsonb_build_object('ok',true,'source',item.source,'version',item.version);
 elsif p_action='watch' then
  insert into private.ministry_media_watchers(media_id,user_id) values(item.id,auth.uid()) on conflict(media_id,user_id) do update set seen_at=clock_timestamp();
 elsif p_action='progress' then
  if p_data-array['position','favorite','version']<>'{}' or (p_data->>'version')::integer is distinct from item.version or (p_data->>'position')::integer not between 0 and 864000 or jsonb_typeof(p_data->'favorite') is distinct from 'boolean' then raise exception 'media_changed' using errcode='40001';end if;
  insert into private.ministry_media_progress(organization_id,user_id,media_id,media_version,position_seconds,favorite) values(p_org,auth.uid(),item.id,item.version,(p_data->>'position')::integer,(p_data->>'favorite')::boolean) on conflict(user_id,media_id) do update set media_version=excluded.media_version,position_seconds=excluded.position_seconds,favorite=excluded.favorite,updated_at=clock_timestamp();
 else raise exception 'invalid_media' using errcode='22023';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.member_media_self(uuid,uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function private.member_media_self(uuid,uuid,text,uuid,jsonb) to authenticated;
create function public.member_media_self(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_media_self(p_org,p_unit,p_action,p_id,p_data)$$;
revoke all on function public.member_media_self(uuid,uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function public.member_media_self(uuid,uuid,text,uuid,jsonb) to authenticated;

-- Confidential operational records never enter the public publication feed.
create table private.kids_operational_notes(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,attendance_id uuid not null,
 kind text not null check(kind in('occurrence','call')),body text not null check(length(btrim(body)) between 5 and 2000),
 status text not null default 'open' check(status in('open','resolved')),resolution text not null default '' check(length(resolution)<=2000),
 version integer not null default 1,created_by uuid not null references auth.users(id),resolved_by uuid references auth.users(id),created_at timestamptz not null default now(),resolved_at timestamptz,
 foreign key(attendance_id,organization_id,unit_id) references private.kids_attendance(id,organization_id,unit_id)
);
create index kids_operational_notes_scope on private.kids_operational_notes(organization_id,unit_id,attendance_id,created_at desc);
create index kids_operational_notes_attendance on private.kids_operational_notes(attendance_id,organization_id,unit_id);
create index kids_operational_notes_creator on private.kids_operational_notes(created_by);
create index kids_operational_notes_resolver on private.kids_operational_notes(resolved_by);
alter table private.kids_operational_notes enable row level security;
revoke all on private.kids_operational_notes from public,anon,authenticated,service_role;
create function private.kids_notes(p_org uuid,p_unit uuid,p_attendance uuid,p_action text default 'list',p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.kids_attendance;n private.kids_operational_notes;
begin
 perform private.community_identity(p_org,p_unit,false);
 select * into a from private.kids_attendance where id=p_attendance and organization_id=p_org and unit_id=p_unit for share;
 if not found or not private.kids_op_allowed(p_org,p_unit,a.session_id,'accept',a.group_id) then raise exception 'kids_notes_denied' using errcode='42501';end if;
 if p_action='list' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q)) from(select id,kind,body,status,resolution,version,created_at,resolved_at from private.kids_operational_notes where organization_id=p_org and unit_id=p_unit and attendance_id=p_attendance order by created_at desc limit 100)q),'[]'));end if;
 if p_id is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>10000 then raise exception 'invalid_kids_note' using errcode='22023';end if;
 if p_action='create' then
  if p_version is distinct from 0 or p_data-array['kind','body']<>'{}' or coalesce(p_data->>'kind','') not in('occurrence','call') or length(btrim(coalesce(p_data->>'body',''))) not between 5 and 2000 then raise exception 'invalid_kids_note' using errcode='22023';end if;
  insert into private.kids_operational_notes(id,organization_id,unit_id,attendance_id,kind,body,created_by) values(p_id,p_org,p_unit,p_attendance,p_data->>'kind',btrim(p_data->>'body'),auth.uid()) on conflict(id) do nothing;
  select * into n from private.kids_operational_notes where id=p_id;
  if n.organization_id<>p_org or n.unit_id<>p_unit or n.attendance_id<>p_attendance or n.created_by<>auth.uid() or n.kind<>p_data->>'kind' or n.body<>btrim(p_data->>'body') then raise exception 'kids_note_conflict' using errcode='40001';end if;
 elsif p_action='resolve' then
  if not private.kids_op_allowed(p_org,p_unit,a.session_id,'supervise',a.group_id) then raise exception 'kids_notes_denied' using errcode='42501';end if;
  if p_data-array['resolution']<>'{}' or length(btrim(coalesce(p_data->>'resolution',''))) not between 5 and 2000 then raise exception 'invalid_kids_note' using errcode='22023';end if;
  select * into n from private.kids_operational_notes where id=p_id and organization_id=p_org and unit_id=p_unit and attendance_id=p_attendance for update;
  if not found or n.version is distinct from p_version or n.status<>'open' then raise exception 'kids_note_conflict' using errcode='40001';end if;
  update private.kids_operational_notes set status='resolved',resolution=btrim(p_data->>'resolution'),resolved_by=auth.uid(),resolved_at=clock_timestamp(),version=version+1 where id=p_id;
 else raise exception 'invalid_kids_note' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'kids.note.'||p_action,'kids_note',p_id::text,jsonb_build_object('unit',p_unit));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.kids_notes(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.kids_notes(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.kids_notes(p_org uuid,p_unit uuid,p_attendance uuid,p_action text default 'list',p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.kids_notes(p_org,p_unit,p_attendance,p_action,p_id,p_version,p_data)$$;
revoke all on function public.kids_notes(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.kids_notes(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

create table private.kids_class_materials(
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,title text not null check(length(btrim(title)) between 2 and 160),
 body text not null default '' check(length(body)<=8000),url text not null default '',active boolean not null default true,version integer not null default 1,
 created_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index kids_class_materials_scope on private.kids_class_materials(organization_id,unit_id,active,updated_at desc);
create index kids_class_materials_unit on private.kids_class_materials(unit_id,organization_id);
create index kids_class_materials_creator on private.kids_class_materials(created_by);
alter table private.kids_class_materials enable row level security;
revoke all on private.kids_class_materials from public,anon,authenticated,service_role;
create function private.kids_resources(p_org uuid,p_unit uuid,p_session uuid default null,p_action text default 'list',p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare item private.kids_class_materials;manager boolean;
begin
 perform private.community_identity(p_org,p_unit,false);
 manager:=private.kids_op_allowed(p_org,p_unit,p_session,'configure');
 if not private.kids_op_allowed(p_org,p_unit,p_session,'read') then raise exception 'kids_resources_denied' using errcode='42501';end if;
 if p_session is not null and not exists(select 1 from private.kids_sessions where id=p_session and organization_id=p_org and unit_id=p_unit) then raise exception 'kids_resources_denied' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('canManage',manager,'items',coalesce((select jsonb_agg(to_jsonb(q)) from(select id,title,body,url,active,version from private.kids_class_materials where organization_id=p_org and unit_id=p_unit and (active or manager) order by updated_at desc limit 100)q),'[]'),
  'attendance',coalesce((select jsonb_agg(to_jsonb(q)) from(select g.id,r.name as room,c.name as class,count(a.id) as entries,count(a.id) filter(where a.status='present') as present,count(a.id) filter(where a.status='out') as departed from private.kids_session_rooms g join private.kids_rooms r on r.id=g.room_id join private.kids_classes c on c.id=g.class_id left join private.kids_attendance a on a.group_id=g.id where g.organization_id=p_org and g.unit_id=p_unit and g.session_id=p_session and private.kids_op_allowed(p_org,p_unit,p_session,'read',g.id) group by g.id,r.name,c.name order by r.name)q),'[]'));
 end if;
 if not manager then raise exception 'kids_resources_denied' using errcode='42501';end if;
 if p_id is null or p_action not in('save','archive') or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'invalid_kids_material' using errcode='22023';end if;
 select * into item from private.kids_class_materials where id=p_id for update;
 if found and (item.organization_id<>p_org or item.unit_id<>p_unit) then raise exception 'kids_resources_denied' using errcode='42501';end if;
 if coalesce(item.version,0) is distinct from p_version then raise exception 'kids_material_changed' using errcode='40001';end if;
 if p_action='save' then
  if p_data-array['title','body','url']<>'{}' or length(btrim(coalesce(p_data->>'title',''))) not between 2 and 160 or length(coalesce(p_data->>'body',''))>8000 or coalesce(p_data->>'url','')<>'' and not private.ministry_public_url(p_data->>'url') then raise exception 'invalid_kids_material' using errcode='22023';end if;
  insert into private.kids_class_materials(id,organization_id,unit_id,title,body,url,created_by) values(p_id,p_org,p_unit,btrim(p_data->>'title'),coalesce(p_data->>'body',''),coalesce(p_data->>'url',''),auth.uid()) on conflict(id) do update set title=excluded.title,body=excluded.body,url=excluded.url,active=true,version=kids_class_materials.version+1,updated_at=clock_timestamp() where kids_class_materials.version=p_version;
  if not found then raise exception 'kids_material_changed' using errcode='40001';end if;
 else
  if item.id is null or p_data<>'{}' then raise exception 'invalid_kids_material' using errcode='22023';end if;
  update private.kids_class_materials set active=false,version=version+1,updated_at=clock_timestamp() where id=p_id;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'kids.material.'||p_action,'kids_material',p_id::text,jsonb_build_object('unit',p_unit));return jsonb_build_object('ok',true);
end $$;
revoke all on function private.kids_resources(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.kids_resources(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.kids_resources(p_org uuid,p_unit uuid,p_session uuid default null,p_action text default 'list',p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.kids_resources(p_org,p_unit,p_session,p_action,p_id,p_version,p_data)$$;
revoke all on function public.kids_resources(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.kids_resources(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

notify pgrst, 'reload schema';
