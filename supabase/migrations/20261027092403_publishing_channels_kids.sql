set local lock_timeout='5s';
create table private.publishing_groups(
 id uuid primary key,organization_id uuid not null references public.organizations(id),owner_unit uuid not null,
 title text not null check(length(btrim(title)) between 2 and 100),targets uuid[] not null check(cardinality(targets) between 1 and 200 and array_position(targets,null) is null),
 active boolean not null default true,version integer not null default 1,created_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 foreign key(owner_unit,organization_id) references public.organization_units(id,organization_id),unique(id,organization_id)
);
create index publishing_groups_owner on private.publishing_groups(owner_unit,organization_id);
create index publishing_groups_org on private.publishing_groups(organization_id);
create index publishing_groups_actor on private.publishing_groups(created_by);
create table private.publishing_items(
 id uuid primary key,organization_id uuid not null references public.organizations(id),owner_unit uuid not null,
 kind text not null check(kind in('notice','video','live','channel','category','banner','file')),title text not null check(length(btrim(title)) between 2 and 160),body text not null default '' check(length(body)<=4000),
 source text not null default '' check(length(source)<=2000),poster text not null default '' check(length(poster)<=2000),provider text not null default '' check(provider in('','youtube','vimeo','hls')),
 category_id uuid,channel_id uuid,group_id uuid,group_version integer,scope text not null check(scope in('local','selected','all','group')),
 targets uuid[] not null check(cardinality(targets) between 1 and 200 and array_position(targets,null) is null),
 starts_at timestamptz,ends_at timestamptz,download_allowed boolean not null default false,share_allowed boolean not null default true,
 status text not null default 'draft' check(status in('draft','published','archived')),live_state text not null default 'scheduled' check(live_state in('scheduled','live','ended')),
 version integer not null default 1,created_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 foreign key(owner_unit,organization_id) references public.organization_units(id,organization_id),unique(id,organization_id),
 foreign key(category_id,organization_id) references private.publishing_items(id,organization_id),foreign key(channel_id,organization_id) references private.publishing_items(id,organization_id),
 foreign key(group_id,organization_id) references private.publishing_groups(id,organization_id),check(ends_at is null or starts_at is null or ends_at>starts_at)
);
create index publishing_items_scope on private.publishing_items(organization_id,kind,status,updated_at desc,id);
create index publishing_items_owner on private.publishing_items(owner_unit,organization_id);
create index publishing_items_category on private.publishing_items(category_id,organization_id);
create index publishing_items_channel on private.publishing_items(channel_id,organization_id);
create index publishing_items_group on private.publishing_items(group_id,organization_id);
create index publishing_items_actor on private.publishing_items(created_by);
alter table private.publishing_groups enable row level security;
alter table private.publishing_items enable row level security;
revoke all on private.publishing_groups,private.publishing_items from public,anon,authenticated,service_role;
alter table private.ministry_media add column publishing_id uuid references private.publishing_items(id),add unique(publishing_id,unit_id);
alter table private.member_publications add column publishing_id uuid references private.publishing_items(id),add column publishing_revision integer,add unique(publishing_id,unit_id);

create function private.publisher_unit(p_org uuid,p_unit uuid,p_kind text default '') returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_units u where u.id=p_unit and u.organization_id=p_org and u.status='active'
 and (private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or u.communication_autonomy and private.has_organization_role(p_org,array['secretary','leader']::public.membership_role[]) and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]))
 and (p_kind in('','category') or private.ministry_module_public(p_org,p_unit,case when p_kind in('channel','live') then 'broadcasts' else 'communication' end)));
$$;
revoke all on function private.publisher_unit(uuid,uuid,text) from public,anon,authenticated,service_role;

-- Canonical rows remain the consumers' single read path. A managed projection may not be edited independently.
create function private.guard_publishing_projection() returns trigger language plpgsql security definer set search_path='' as $$
declare i private.publishing_items;expected boolean;
begin
 if tg_op='UPDATE' and old.publishing_id is not null and new.publishing_id is distinct from old.publishing_id then raise exception 'publishing_managed_projection' using errcode='42501';end if;
 if new.publishing_id is null then return new;end if;
 select * into i from private.publishing_items where id=new.publishing_id and organization_id=new.organization_id;
 if not found then raise exception 'publishing_managed_projection' using errcode='42501';end if;
 expected:=new.unit_id=any(i.targets);
 if tg_table_name='ministry_media' then
  if new.version<>i.version or new.status<>(case when expected and i.kind in('video','live') then i.status else 'archived' end)
   or expected and i.kind in('video','live') and (new.kind<>i.kind or new.title<>i.title or new.description<>i.body or new.source<>i.source or new.poster<>i.poster or new.live_state<>i.live_state or new.starts_at is distinct from i.starts_at or new.ends_at is distinct from i.ends_at or new.download_allowed<>i.download_allowed) then raise exception 'publishing_managed_projection' using errcode='42501';end if;
 else
  if new.publishing_revision is distinct from i.version or new.published is distinct from (expected and i.kind in('notice','banner','file') and i.status='published') or expected and i.kind in('notice','banner','file') and (new.title<>i.title or new.body<>i.body or new.url<>i.source) then raise exception 'publishing_managed_projection' using errcode='42501';end if;
 end if;
 return new;
end $$;
revoke all on function private.guard_publishing_projection() from public,anon,authenticated,service_role;
create trigger publishing_media_guard before insert or update on private.ministry_media for each row execute function private.guard_publishing_projection();
create trigger publishing_post_guard before insert or update on private.member_publications for each row execute function private.guard_publishing_projection();
create function private.sync_publishing_item() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update private.ministry_media set status='archived',version=new.version,updated_at=now() where publishing_id=new.id and (not(unit_id=any(new.targets)) or new.kind not in('video','live'));
 update private.member_publications set published=false,publishing_revision=new.version where publishing_id=new.id and (not(unit_id=any(new.targets)) or new.kind not in('notice','banner','file'));
 if new.kind in('video','live') then
  insert into private.ministry_media(id,organization_id,unit_id,kind,title,description,source,poster,status,live_state,starts_at,ends_at,download_allowed,version,created_by,publishing_id)
  select extensions.gen_random_uuid(),new.organization_id,u,new.kind,new.title,new.body,new.source,new.poster,new.status,new.live_state,new.starts_at,new.ends_at,new.download_allowed,new.version,new.created_by,new.id from unnest(new.targets)u
  on conflict(publishing_id,unit_id) do update set kind=excluded.kind,title=excluded.title,description=excluded.description,source=excluded.source,poster=excluded.poster,status=excluded.status,live_state=excluded.live_state,starts_at=excluded.starts_at,ends_at=excluded.ends_at,download_allowed=excluded.download_allowed,version=excluded.version,updated_at=now();
 elsif new.kind in('notice','banner','file') then
  insert into private.member_publications(organization_id,unit_id,kind,title,body,url,published,publishing_id,publishing_revision)
  select new.organization_id,u,'notice',new.title,new.body,new.source,new.status='published',new.id,new.version from unnest(new.targets)u
  on conflict(publishing_id,unit_id) do update set title=excluded.title,body=excluded.body,url=excluded.url,published=excluded.published,publishing_revision=excluded.publishing_revision;
 end if;
 return new;
end $$;
revoke all on function private.sync_publishing_item() from public,anon,authenticated,service_role;
create trigger publishing_sync after insert or update on private.publishing_items for each row execute function private.sync_publishing_item();

create function private.publishing_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare item private.publishing_items;g private.publishing_groups;dest uuid[];old_dest uuid[];kind_name text;source_url text;scope_name text;cat uuid;channel uuid;group_id uuid;group_version integer;page_no integer;page_size integer;query_text text;state text;eligible uuid[];
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.publisher_unit(p_org,p_unit) then raise exception 'publishing_denied' using errcode='42501';end if;
 if p_action<>'list' then
  perform pg_advisory_xact_lock(hashtextextended('vinha-publishing:'||coalesce(p_id::text,''),0));
  perform 1 from public.membership_unit_access a join public.organization_memberships m on m.id=a.membership_id where m.organization_id=p_org and m.user_id=auth.uid() order by a.unit_id for share of a;
 end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>22000 then raise exception 'invalid_publishing' using errcode='22023';end if;
 select coalesce(array_agg(u.id order by u.id),'{}') into eligible from public.organization_units u where u.organization_id=p_org and private.publisher_unit(p_org,u.id);
 if p_action='list' then
  if p_data-array['kind','search','status','page','size']<>'{}' then raise exception 'invalid_publishing' using errcode='22023';end if;
  kind_name:=coalesce(p_data->>'kind','notice');query_text:=coalesce(p_data->>'search','');state:=coalesce(p_data->>'status','');page_no:=coalesce((p_data->>'page')::integer,1);page_size:=coalesce((p_data->>'size')::integer,20);
  if kind_name not in('notice','video','live','channel','category','banner','file') or state not in('','draft','published','archived') or length(query_text)>120 or page_no not between 1 and 100000 or page_size not between 1 and 100 then raise exception 'invalid_publishing' using errcode='22023';end if;
  if not private.publisher_unit(p_org,p_unit,kind_name) then raise exception 'publishing_denied' using errcode='42501';end if;
  return (with visible as(select i.*,(i.targets<@eligible) can_manage from private.publishing_items i where i.organization_id=p_org and (p_unit=any(i.targets) or i.owner_unit=p_unit and i.targets<@eligible) and (i.targets<@eligible or i.status='published') and i.kind=kind_name and (state='' or i.status=state) and position(lower(query_text) in lower(i.title))>0),paged as(select * from visible order by updated_at desc,id limit page_size offset (page_no-1)*page_size)
   select jsonb_build_object('items',coalesce((select jsonb_agg((to_jsonb(p)-array['targets','group_id','group_version'])||jsonb_build_object('targets',case when p.can_manage then to_jsonb(p.targets) else to_jsonb(array(select unnest(p.targets) intersect select unnest(eligible))) end,'group_id',case when p.can_manage then p.group_id else null end,'group_version',case when p.can_manage then p.group_version else null end) order by p.updated_at desc,p.id) from paged p),'[]'),'total',(select count(*) from visible),
    'units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'communication',private.publisher_unit(p_org,u.id,'notice'),'broadcasts',private.publisher_unit(p_org,u.id,'live')) order by u.name) from public.organization_units u where u.id=any(eligible)),'[]'),
    'groups',coalesce((select jsonb_agg(to_jsonb(gr) order by gr.title) from private.publishing_groups gr where gr.organization_id=p_org and gr.targets<@eligible),'[]'),
    'categories',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'title',i.title,'targets',array(select unnest(i.targets) intersect select unnest(eligible))) order by i.title) from private.publishing_items i where i.organization_id=p_org and i.kind='category' and i.status='published' and i.targets&&eligible),'[]'),
    'channels',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'title',i.title,'targets',array(select unnest(i.targets) intersect select unnest(eligible)),'source',i.source,'provider',i.provider) order by i.title) from private.publishing_items i where i.organization_id=p_org and i.kind='channel' and i.status='published' and i.targets&&eligible),'[]')));
 end if;
 if p_id is null or p_version is null or p_version<0 then raise exception 'invalid_publishing' using errcode='22023';end if;
 if p_action='group' then
  if p_data-array['title','targets','active']<>'{}' or not(p_data ?& array['title','targets','active']) or length(btrim(p_data->>'title')) not between 2 and 100 or jsonb_typeof(p_data->'active')<>'boolean' or jsonb_typeof(p_data->'targets')<>'array' then raise exception 'invalid_publishing' using errcode='22023';end if;
  select coalesce(array_agg(x::uuid order by x),'{}') into dest from jsonb_array_elements_text(p_data->'targets') x;
  select * into g from private.publishing_groups where id=p_id for update;
  if found and (g.organization_id<>p_org or not(g.targets<@eligible)) then raise exception 'publishing_denied' using errcode='42501';end if;
  if coalesce(g.version,0)<>p_version then raise exception 'publishing_changed' using errcode='40001';end if;
  if not(dest<@eligible) or cardinality(dest) not between 1 and 200 or cardinality(dest)<>(select count(distinct x) from unnest(dest)x) then raise exception 'publishing_denied' using errcode='42501';end if;
  insert into private.publishing_groups(id,organization_id,owner_unit,title,targets,active,created_by) values(p_id,p_org,p_unit,btrim(p_data->>'title'),dest,(p_data->>'active')::boolean,auth.uid()) on conflict(id) do update set title=excluded.title,targets=excluded.targets,active=excluded.active,version=publishing_groups.version+1,updated_at=now();
 else
  if p_action not in('save','publish','archive','live','end') then raise exception 'invalid_publishing' using errcode='22023';end if;
  select * into item from private.publishing_items where id=p_id for update;
  if found and (item.organization_id<>p_org or not(item.targets<@eligible)) then raise exception 'publishing_denied' using errcode='42501';end if;
  if coalesce(item.version,0)<>p_version then raise exception 'publishing_changed' using errcode='40001';end if;
  old_dest:=coalesce(item.targets,'{}');
  if p_action='save' then
   if p_data-array['kind','title','body','source','poster','category','channel','scope','targets','group','groupVersion','provider','starts','ends','download','share']<>'{}' or not(p_data ?& array['kind','title','body','source','poster','category','channel','scope','targets','group','groupVersion','provider','starts','ends','download','share']) then raise exception 'invalid_publishing' using errcode='22023';end if;
   kind_name:=p_data->>'kind';scope_name:=p_data->>'scope';source_url:=p_data->>'source';cat:=nullif(p_data->>'category','')::uuid;channel:=nullif(p_data->>'channel','')::uuid;
   if kind_name not in('notice','video','live','channel','category','banner','file') or item.id is not null and item.kind<>kind_name or length(btrim(p_data->>'title')) not between 2 and 160 or length(p_data->>'body')>4000 or scope_name not in('local','selected','all','group') or jsonb_typeof(p_data->'targets')<>'array' or jsonb_typeof(p_data->'download')<>'boolean' or jsonb_typeof(p_data->'share')<>'boolean' or (p_data->>'poster'<>'' and not private.ministry_public_url(p_data->>'poster')) then raise exception 'invalid_publishing' using errcode='22023';end if;
   if kind_name<>'category' and (source_url<>'' or kind_name<>'notice') and not private.ministry_public_url(source_url) or kind_name='category' and source_url<>'' then raise exception 'invalid_publishing' using errcode='22023';end if;
   if kind_name='channel' and (p_data->>'provider' not in('youtube','vimeo','hls') or p_data->>'provider'='youtube' and source_url!~'^https://(www\.)?youtube.com/(channel/UC[A-Za-z0-9_-]{22}|@[A-Za-z0-9._-]{3,80})/?$' or p_data->>'provider'='hls' and source_url!~*'\.m3u8(\?[^[:space:]]*)?$') then raise exception 'invalid_publishing' using errcode='22023';end if;
   if kind_name in('video','live') and source_url!~*'(^https://(www\.)?(youtube\.com/(watch\?v=[a-zA-Z0-9_-]{11}|embed/[a-zA-Z0-9_-]{11}|live/[a-zA-Z0-9_-]{11})|youtu\.be/[a-zA-Z0-9_-]{11}|vimeo\.com/[0-9]+)([?&][^[:space:]]*)?$|^https://[^[:space:]]+\.(mp4|m3u8)(\?[^[:space:]]*)?$)' or (p_data->>'download')::boolean and (kind_name<>'video' or source_url!~*'\.mp4(\?[^[:space:]]*)?$') then raise exception 'invalid_publishing' using errcode='22023';end if;
   if kind_name='live' and (nullif(p_data->>'starts','') is null or nullif(p_data->>'ends','') is null) or nullif(p_data->>'ends','')::timestamptz<=nullif(p_data->>'starts','')::timestamptz then raise exception 'invalid_publishing' using errcode='22023';end if;
   if scope_name='local' then dest:=array[p_unit];elsif scope_name='all' then select coalesce(array_agg(u.id order by u.id),'{}') into dest from public.organization_units u where u.organization_id=p_org and private.publisher_unit(p_org,u.id,kind_name);
   elsif scope_name='group' then group_id:=nullif(p_data->>'group','')::uuid;group_version:=(p_data->>'groupVersion')::integer;select * into g from private.publishing_groups where id=group_id and organization_id=p_org and active for share;if not found or g.version is distinct from group_version or not(g.targets<@eligible) then raise exception 'publishing_changed' using errcode='40001';end if;dest:=g.targets;
   else select coalesce(array_agg(x::uuid order by x),'{}') into dest from jsonb_array_elements_text(p_data->'targets') x;end if;
  else kind_name:=item.kind;dest:=item.targets;group_id:=item.group_id;group_version:=item.group_version;cat:=item.category_id;channel:=item.channel_id;
   if item.id is null or p_data<>'{}' then raise exception 'invalid_publishing' using errcode='22023';end if;
  end if;
  perform 1 from public.organization_units where organization_id=p_org and id=any(old_dest||dest) order by id for share;
  if cardinality(dest) not between 1 and 200 or cardinality(dest)<>(select count(distinct x) from unnest(dest)x) or exists(select 1 from unnest(old_dest||dest)u where not private.publisher_unit(p_org,u,kind_name)) then raise exception 'publishing_denied' using errcode='42501';end if;
  if p_action in('save','archive') and kind_name in('category','channel') and exists(select 1 from private.publishing_items ch where ch.organization_id=p_org and ch.status='published' and (ch.category_id=p_id or ch.channel_id=p_id)) then raise exception 'publishing_changed' using errcode='40001';end if;
  if group_id is not null then perform 1 from private.publishing_groups where id=group_id and organization_id=p_org for share;end if;
  if p_action='publish' and group_id is not null and not exists(select 1 from private.publishing_groups where id=group_id and organization_id=p_org and active and version=group_version and targets=dest) then raise exception 'publishing_changed' using errcode='40001';end if;
  perform 1 from private.publishing_items where organization_id=p_org and id in(cat,channel) order by id for share;
  if cat=p_id or channel=p_id then raise exception 'invalid_publishing' using errcode='22023';end if;
  if cat is not null and not exists(select 1 from private.publishing_items where id=cat and organization_id=p_org and kind='category' and status='published' and dest<@targets) or channel is not null and (kind_name<>'live' or not exists(select 1 from private.publishing_items where id=channel and organization_id=p_org and kind='channel' and status='published' and dest<@targets)) then raise exception 'invalid_publishing' using errcode='22023';end if;
  if p_action='save' then
   insert into private.publishing_items(id,organization_id,owner_unit,kind,title,body,source,poster,provider,category_id,channel_id,group_id,group_version,scope,targets,starts_at,ends_at,download_allowed,share_allowed,created_by)
   values(p_id,p_org,p_unit,kind_name,btrim(p_data->>'title'),p_data->>'body',source_url,p_data->>'poster',p_data->>'provider',cat,channel,group_id,group_version,scope_name,dest,nullif(p_data->>'starts','')::timestamptz,nullif(p_data->>'ends','')::timestamptz,(p_data->>'download')::boolean,(p_data->>'share')::boolean,auth.uid())
   on conflict(id) do update set title=excluded.title,body=excluded.body,source=excluded.source,poster=excluded.poster,provider=excluded.provider,category_id=excluded.category_id,channel_id=excluded.channel_id,group_id=excluded.group_id,group_version=excluded.group_version,scope=excluded.scope,targets=excluded.targets,starts_at=excluded.starts_at,ends_at=excluded.ends_at,download_allowed=excluded.download_allowed,share_allowed=excluded.share_allowed,status='draft',live_state='scheduled',version=publishing_items.version+1,updated_at=now();
  else
   if p_action in('live','end') and (kind_name<>'live' or item.status<>'published') then raise exception 'invalid_publishing' using errcode='22023';end if;
   update private.publishing_items set status=case p_action when 'publish' then 'published' when 'archive' then 'archived' else status end,live_state=case p_action when 'live' then 'live' when 'end' then 'ended' else live_state end,version=version+1,updated_at=now() where id=p_id;
  end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'publishing.'||p_action,'publishing',p_id::text,jsonb_build_object('unit',p_unit));
 return jsonb_build_object('ok',true,'id',p_id);
end $$;
revoke all on function private.publishing_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.publishing_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.publishing_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.publishing_admin(p_org,p_unit,p_action,p_id,p_version,p_data)$$;
revoke all on function public.publishing_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.publishing_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;

create function member_app_api.publishing_catalog(p_org uuid,p_unit uuid,p_kind text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_kind not in('channel','category','banner') then raise exception 'invalid_publishing' using errcode='22023';end if;
 if not private.ministry_module_public(p_org,p_unit,case when p_kind='channel' then 'broadcasts' else 'communication' end) then return jsonb_build_object('items','[]'::jsonb);end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q)) from(select id,title,body,source,poster,share_allowed from private.publishing_items where organization_id=p_org and p_unit=any(targets) and kind=p_kind and status='published' order by updated_at desc limit 100)q),'[]'));
end $$;
revoke all on function member_app_api.publishing_catalog(uuid,uuid,text) from public,service_role;
grant execute on function member_app_api.publishing_catalog(uuid,uuid,text) to anon,authenticated;
create function public.member_publishing_catalog(p_org uuid,p_unit uuid,p_kind text) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.publishing_catalog(p_org,p_unit,p_kind)$$;
revoke all on function public.member_publishing_catalog(uuid,uuid,text) from public,service_role;
grant execute on function public.member_publishing_catalog(uuid,uuid,text) to anon,authenticated;

create function private.kids_desk(p_org uuid,p_unit uuid,p_session uuid default null,p_view text default 'reports',p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare page_no integer;query_text text;state text;from_day date;to_day date;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.kids_op_allowed(p_org,p_unit,p_session,'read') or p_session is not null and not exists(select 1 from private.kids_sessions where id=p_session and organization_id=p_org and unit_id=p_unit) then raise exception 'kids_desk_denied' using errcode='42501';end if;
 if p_view not in('notes','reports') or jsonb_typeof(p_data) is distinct from 'object' or p_data-array['page','search','status','from','to']<>'{}' then raise exception 'invalid_kids_desk' using errcode='22023';end if;
 page_no:=coalesce((p_data->>'page')::integer,1);query_text:=coalesce(p_data->>'search','');state:=coalesce(p_data->>'status','');from_day:=coalesce((p_data->>'from')::date,(now() at time zone 'America/Sao_Paulo')::date-30);to_day:=coalesce((p_data->>'to')::date,(now() at time zone 'America/Sao_Paulo')::date+1);
 if page_no not between 1 and 100000 or length(query_text)>100 or state not in('','open','resolved') or to_day<=from_day or to_day-from_day>366 then raise exception 'invalid_kids_desk' using errcode='22023';end if;
 if p_view='notes' then
  if not exists(select 1 from private.kids_session_rooms g where g.organization_id=p_org and g.unit_id=p_unit and (p_session is null or g.session_id=p_session) and private.kids_op_allowed(p_org,p_unit,g.session_id,'accept',g.id)) and not private.kids_op_allowed(p_org,p_unit,p_session,'supervise') then raise exception 'kids_desk_denied' using errcode='42501';end if;
  return (with visible as(select n.id,n.attendance_id,n.kind,n.body,n.status,n.resolution,n.version,n.created_at,n.resolved_at,child.full_name child,room.name room,s.name session,private.kids_op_allowed(p_org,p_unit,a.session_id,'supervise',a.group_id) can_resolve
   from private.kids_operational_notes n join private.kids_attendance a on a.id=n.attendance_id join private.kids_profiles k on k.id=a.profile_id join public.people child on child.id=k.person_id join private.kids_session_rooms g on g.id=a.group_id join private.kids_rooms room on room.id=g.room_id join private.kids_sessions s on s.id=a.session_id
   where n.organization_id=p_org and n.unit_id=p_unit and (p_session is null or a.session_id=p_session) and private.kids_op_allowed(p_org,p_unit,a.session_id,'accept',a.group_id) and (state='' or n.status=state) and position(lower(query_text) in lower(child.full_name))>0 and n.created_at>=from_day::timestamp at time zone 'America/Sao_Paulo' and n.created_at<to_day::timestamp at time zone 'America/Sao_Paulo'),paged as(select * from visible order by created_at desc,id limit 20 offset (page_no-1)*20)
   select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id) from paged p),'[]'),'total',(select count(*) from visible)));
 end if;
 return (with rooms as(select g.id,s.name session,r.name room,c.name class,g.capacity,count(a.id) entries,count(a.id) filter(where a.status='present') present,count(a.id) filter(where a.status='out') departed
   from private.kids_session_rooms g join private.kids_sessions s on s.id=g.session_id join private.kids_rooms r on r.id=g.room_id join private.kids_classes c on c.id=g.class_id left join private.kids_attendance a on a.group_id=g.id and a.checked_in_at>=from_day::timestamp at time zone 'America/Sao_Paulo' and a.checked_in_at<to_day::timestamp at time zone 'America/Sao_Paulo'
   where g.organization_id=p_org and g.unit_id=p_unit and (p_session is null or g.session_id=p_session) and private.kids_op_allowed(p_org,p_unit,g.session_id,'read',g.id)
    and (s.starts_at<to_day::timestamp at time zone 'America/Sao_Paulo' and s.ends_at>=from_day::timestamp at time zone 'America/Sao_Paulo')
   group by g.id,s.name,r.name,c.name,g.capacity),paged as(select * from rooms order by session,room,id limit 20 offset (page_no-1)*20)
   select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.session,p.room,p.id) from paged p),'[]'),'total',(select count(*) from rooms),'summary',jsonb_build_object('entries',coalesce((select sum(entries) from rooms),0),'present',coalesce((select sum(present) from rooms),0),'departed',coalesce((select sum(departed) from rooms),0))));
end $$;
revoke all on function private.kids_desk(uuid,uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.kids_desk(uuid,uuid,uuid,text,jsonb) to authenticated;
create function public.kids_desk(p_org uuid,p_unit uuid,p_session uuid default null,p_view text default 'reports',p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.kids_desk(p_org,p_unit,p_session,p_view,p_data)$$;
revoke all on function public.kids_desk(uuid,uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.kids_desk(uuid,uuid,uuid,text,jsonb) to authenticated;
