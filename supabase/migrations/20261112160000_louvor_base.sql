-- Louvor · Etapa L1 (docs/PLANO-ESCALAS-LOUVOR-2026-11-12.md).
-- Repertório da igreja (músicas com tom, BPM, letra e cifra, links e etiquetas) e repertório de
-- cada culto, ligado ao culto da Escala (private.scale_services). O tom do dia é guardado por
-- música; a transposição da cifra é feita na tela a partir do tom original.
-- Acesso: dono/administrador/pastor com gestão na igreja, ou permissões concedidas em
-- Configurações › Usuários e permissões (Louvor › Repertório e Louvor › Repertório do culto,
-- com limite opcional por equipe de escala). Módulo contratado: worship.

create table private.worship_songs(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 title text not null check(length(btrim(title)) between 1 and 160),
 artist text not null default '' check(length(artist)<=160),
 original_key text not null default '' check(original_key ~ '^([A-G](#|b)?m?)?$'),
 bpm integer check(bpm between 20 and 300),
 time_signature text not null default '' check(time_signature in('','2/4','3/4','4/4','6/8','12/8')),
 chart text not null default '' check(length(chart)<=20000),
 links jsonb not null default '{}' check(jsonb_typeof(links)='object' and octet_length(links::text)<=3000),
 tags text[] not null default '{}' check(cardinality(tags)<=12),
 status text not null default 'active' check(status in('active','rehearsal','archived')),
 notes text not null default '' check(length(notes)<=1000),
 version integer not null default 1 check(version>0),
 created_by uuid not null,
 created_at timestamptz not null default now(),
 updated_by uuid not null,
 updated_at timestamptz not null default now()
);
create index worship_songs_unit on private.worship_songs(organization_id,unit_id,status);
create unique index worship_songs_unique on private.worship_songs(unit_id,lower(btrim(title)),lower(btrim(artist))) where status<>'archived';
alter table private.worship_songs enable row level security;
revoke all on private.worship_songs from public,anon,authenticated,service_role;

create table private.worship_setlists(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 service_id uuid not null unique references private.scale_services(id) on delete cascade,
 status text not null default 'draft' check(status in('draft','published')),
 notes text not null default '' check(length(notes)<=2000),
 version integer not null default 1 check(version>0),
 updated_by uuid not null,
 updated_at timestamptz not null default now()
);
alter table private.worship_setlists enable row level security;
revoke all on private.worship_setlists from public,anon,authenticated,service_role;

create table private.worship_setlist_items(
 setlist_id uuid not null references private.worship_setlists(id) on delete cascade,
 position integer not null check(position between 1 and 40),
 song_id uuid not null references private.worship_songs(id),
 song_key text not null default '' check(song_key ~ '^([A-G](#|b)?m?)?$'),
 minister_person_id uuid references public.people(id) on delete set null,
 notes text not null default '' check(length(notes)<=500),
 primary key(setlist_id,position)
);
create index worship_setlist_items_song on private.worship_setlist_items(song_id);
alter table private.worship_setlist_items enable row level security;
revoke all on private.worship_setlist_items from public,anon,authenticated,service_role;

-- Permissões no catálogo e modelo pronto.
insert into private.permission_catalog(code,module,area,label,actions,group_kinds,position,owner_only) values
 ('worship.songs','worship','Louvor','Repertório (músicas e cifras)',array['view','create','edit','delete'],'{}',65,false),
 ('worship.setlists','worship','Louvor','Repertório do culto',array['view','create','edit','approve'],array['scale_team'],66,false);
insert into private.permission_templates values
 ('lider_louvor','Líder de louvor','Repertório, cifras e o repertório de cada culto; vê as escalas.',
  '{"worship.songs":["view","create","edit"],"worship.setlists":["view","create","edit","approve"],"scales.schedules":["view"],"scales.teams":["view"]}');
update private.permission_templates set items=items||'{"worship.songs":["view"],"worship.setlists":["view","approve"]}' where code='pastor';

-- Regra única do Louvor. p_teams: equipes de escala do culto (limite por grupo).
create function private.worship_can(p_org uuid,p_unit uuid,p_permission text,p_action text,p_teams uuid[] default null) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.unit_module_contracted(p_org,p_unit,'worship')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'))
 and ((private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[])
   and private.can_access_unit(p_org,p_unit,case when p_action='view' then array['read','manage','admin'] else array['manage','admin'] end::public.unit_access_level[]))
  or private.can_in(p_org,p_unit,p_permission,p_action,p_teams))
$$;
revoke all on function private.worship_can(uuid,uuid,text,text,uuid[]) from public,anon,authenticated,service_role;

create function private.worship_service_teams(p_service uuid) returns uuid[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(distinct team_id),'{}') from private.scale_positions where service_id=p_service
$$;
revoke all on function private.worship_service_teams(uuid) from public,anon,authenticated,service_role;

create function private.worship_clean_tags(p jsonb) returns text[]
language sql immutable set search_path='' as $$
 select coalesce(array_agg(distinct t order by t),'{}') from (select lower(btrim(x)) t from jsonb_array_elements_text(coalesce(p,'[]')) x) s where length(t) between 1 and 30
$$;

-- Repertório.
create function private.worship_songs(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s private.worship_songs;v_id uuid;v_version integer;v_page integer:=greatest(coalesce((p_data->>'page')::integer,1),1);v_q text:=lower(btrim(coalesce(p_data->>'search','')));
 v_status text:=coalesce(nullif(p_data->>'status',''),'current');v_tag text:=lower(btrim(coalesce(p_data->>'tag','')));items jsonb;total integer;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_song' using errcode='22023';end if;
 if p_action in('list','detail') then
  if not private.worship_can(p_org,p_unit,'worship.songs','view') then raise exception 'worship_access_denied' using errcode='42501';end if;
 end if;
 if p_action='list' then
  with base as (
   select w.*,(select max(sv.starts_at) from private.worship_setlist_items i join private.worship_setlists ls on ls.id=i.setlist_id join private.scale_services sv on sv.id=ls.service_id
     where i.song_id=w.id and ls.status='published' and sv.status<>'cancelled' and sv.starts_at<=now()) last_played,
    (select count(*) from private.worship_setlist_items i join private.worship_setlists ls on ls.id=i.setlist_id join private.scale_services sv on sv.id=ls.service_id
     where i.song_id=w.id and ls.status='published' and sv.status<>'cancelled' and sv.starts_at<=now()) times_played
   from private.worship_songs w where w.organization_id=p_org and w.unit_id=p_unit
    and (v_status='all' or v_status='current' and w.status<>'archived' or w.status=v_status)
    and (v_q='' or lower(w.title) like '%'||v_q||'%' or lower(w.artist) like '%'||v_q||'%')
    and (v_tag='' or v_tag=any(w.tags))
    and (coalesce(p_data->>'key','')='' or w.original_key=p_data->>'key'))
  select count(*)::integer,coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'artist',artist,'original_key',original_key,'bpm',bpm,'time_signature',time_signature,'tags',tags,'status',status,'version',version,'last_played',last_played,'times_played',times_played,'has_chart',chart<>'') order by lower(title)) filter (where rn between (v_page-1)*30+1 and v_page*30),'[]')
  into total,items from (select b.*,row_number() over(order by lower(b.title),b.id) rn from base b) x;
  return jsonb_build_object('items',items,'total',total,'page',v_page,'pageSize',30,
   'tags',(select coalesce(jsonb_agg(distinct t order by t),'[]') from private.worship_songs w,unnest(w.tags) t where w.organization_id=p_org and w.unit_id=p_unit and w.status<>'archived'),
   'canCreate',private.worship_can(p_org,p_unit,'worship.songs','create'),'canEdit',private.worship_can(p_org,p_unit,'worship.songs','edit'),'canDelete',private.worship_can(p_org,p_unit,'worship.songs','delete'));
 end if;
 v_id:=nullif(p_data->>'id','')::uuid;
 if v_id is null then raise exception 'invalid_song' using errcode='22023';end if;
 if p_action='detail' then
  select * into s from private.worship_songs where id=v_id and organization_id=p_org and unit_id=p_unit;
  if not found then raise exception 'song_not_found' using errcode='42501';end if;
  return to_jsonb(s)-'organization_id'||jsonb_build_object('history',(select coalesce(jsonb_agg(jsonb_build_object('service',sv.title,'date',sv.starts_at,'key',i.song_key) order by sv.starts_at desc),'[]') from (
    select i.* from private.worship_setlist_items i join private.worship_setlists l on l.id=i.setlist_id join private.scale_services sv on sv.id=l.service_id
    where i.song_id=s.id and l.status='published' and sv.status<>'cancelled' order by sv.starts_at desc limit 12) i
   join private.worship_setlists l on l.id=i.setlist_id join private.scale_services sv on sv.id=l.service_id),
   'canEdit',private.worship_can(p_org,p_unit,'worship.songs','edit'));
 end if;
 v_version:=coalesce((p_data->>'version')::integer,0);
 select * into s from private.worship_songs where id=v_id for update;
 if found and (s.organization_id<>p_org or s.unit_id<>p_unit) then raise exception 'song_not_found' using errcode='42501';end if;
 if p_action='save' then
  if not private.worship_can(p_org,p_unit,'worship.songs',case when s.id is null then 'create' else 'edit' end) then raise exception 'worship_access_denied' using errcode='42501';end if;
  if s.id is not null and s.version<>v_version then
   if s.version=v_version+1 and s.updated_by=auth.uid() and s.title=btrim(p_data->>'title') then return jsonb_build_object('ok',true,'id',s.id,'version',s.version);end if;
   raise exception 'song_version_conflict' using errcode='40001';
  end if;
  if s.id is null and v_version<>0 then raise exception 'song_version_conflict' using errcode='40001';end if;
  if coalesce(p_data->>'status','active') not in('active','rehearsal','archived') then raise exception 'invalid_song' using errcode='22023';end if;
  if s.id is null then
   insert into private.worship_songs(id,organization_id,unit_id,title,artist,original_key,bpm,time_signature,chart,links,tags,status,notes,created_by,updated_by)
   values(v_id,p_org,p_unit,btrim(p_data->>'title'),btrim(coalesce(p_data->>'artist','')),coalesce(p_data->>'originalKey',''),nullif(p_data->>'bpm','')::integer,coalesce(p_data->>'timeSignature',''),
    coalesce(p_data->>'chart',''),coalesce(p_data->'links','{}'),private.worship_clean_tags(p_data->'tags'),coalesce(p_data->>'status','active'),coalesce(p_data->>'notes',''),auth.uid(),auth.uid())
   returning * into s;
  else
   update private.worship_songs set title=btrim(p_data->>'title'),artist=btrim(coalesce(p_data->>'artist','')),original_key=coalesce(p_data->>'originalKey',''),bpm=nullif(p_data->>'bpm','')::integer,
    time_signature=coalesce(p_data->>'timeSignature',''),chart=coalesce(p_data->>'chart',''),links=coalesce(p_data->'links','{}'),tags=private.worship_clean_tags(p_data->'tags'),
    status=coalesce(p_data->>'status','active'),notes=coalesce(p_data->>'notes',''),version=version+1,updated_by=auth.uid(),updated_at=now() where id=s.id returning * into s;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'worship.song.saved','worship_song',s.id,jsonb_build_object('title',s.title,'status',s.status));
  return jsonb_build_object('ok',true,'id',s.id,'version',s.version);
 elsif p_action='delete' then
  if s.id is null then return jsonb_build_object('ok',true,'id',v_id);end if;
  if not private.worship_can(p_org,p_unit,'worship.songs','delete') then raise exception 'worship_access_denied' using errcode='42501';end if;
  if s.version<>v_version then raise exception 'song_version_conflict' using errcode='40001';end if;
  if exists(select 1 from private.worship_setlist_items where song_id=s.id) then raise exception 'song_in_use' using errcode='23503';end if;
  delete from private.worship_songs where id=s.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'worship.song.deleted','worship_song',s.id,jsonb_build_object('title',s.title));
  return jsonb_build_object('ok',true,'id',s.id);
 end if;
 raise exception 'invalid_song' using errcode='22023';
end $$;

-- Repertório do culto.
create function private.worship_setlists(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sv private.scale_services;l private.worship_setlists;teams uuid[];v_from timestamptz;v_to timestamptz;it jsonb;n integer:=0;song private.worship_songs;prev uuid[]:='{}';
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_setlist' using errcode='22023';end if;
 if p_action='services' then
  if not private.worship_can(p_org,p_unit,'worship.setlists','view') then raise exception 'worship_access_denied' using errcode='42501';end if;
  v_from:=coalesce(nullif(p_data->>'from','')::date,current_date-7)::timestamptz;v_to:=coalesce(nullif(p_data->>'to','')::date,current_date+60)::timestamptz+interval '1 day';
  if v_to-v_from>interval '400 days' then raise exception 'invalid_setlist' using errcode='22023';end if;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'starts_at',s.starts_at,'status',s.status,
    'setlist',ws.status,'songs',(select count(*) from private.worship_setlist_items i where i.setlist_id=ws.id),
    'canEdit',private.worship_can(p_org,p_unit,'worship.setlists','edit',private.worship_service_teams(s.id))) order by s.starts_at),'[]')
   from private.scale_services s left join private.worship_setlists ws on ws.service_id=s.id
   where s.organization_id=p_org and s.unit_id=p_unit and s.status<>'cancelled' and s.starts_at>=v_from and s.starts_at<v_to
    and private.worship_can(p_org,p_unit,'worship.setlists','view',private.worship_service_teams(s.id))));
 end if;
 select * into sv from private.scale_services where id=nullif(p_data->>'service','')::uuid and organization_id=p_org and unit_id=p_unit;
 if not found then raise exception 'service_not_found' using errcode='42501';end if;
 teams:=private.worship_service_teams(sv.id);
 if p_action='get' then
  if not private.worship_can(p_org,p_unit,'worship.setlists','view',teams) then raise exception 'worship_access_denied' using errcode='42501';end if;
  select * into l from private.worship_setlists where service_id=sv.id;
  return jsonb_build_object('service',jsonb_build_object('id',sv.id,'title',sv.title,'starts_at',sv.starts_at,'arrival_at',sv.arrival_at,'location',sv.location,'status',sv.status),
   'setlist',case when l.id is null then null else jsonb_build_object('id',l.id,'status',l.status,'notes',l.notes,'version',l.version,'updated_at',l.updated_at) end,
   'items',(select coalesce(jsonb_agg(jsonb_build_object('position',i.position,'song',i.song_id,'title',w.title,'artist',w.artist,'original_key',w.original_key,'key',i.song_key,'bpm',w.bpm,
     'minister',i.minister_person_id,'minister_name',p.full_name,'notes',i.notes,'has_chart',w.chart<>'') order by i.position),'[]')
    from private.worship_setlist_items i join private.worship_songs w on w.id=i.song_id left join public.people p on p.id=i.minister_person_id where i.setlist_id=l.id),
   'team',(select coalesce(jsonb_agg(jsonb_build_object('person',p.id,'name',p.full_name,'role',r.name,'team',t.name) order by t.name,r.name,p.full_name),'[]')
    from private.scale_positions sp join private.scale_members m on m.id=sp.member_id join public.people p on p.id=m.person_id
    join private.scale_roles r on r.id=sp.role_id join private.scale_teams t on t.id=sp.team_id where sp.service_id=sv.id),
   'canEdit',private.worship_can(p_org,p_unit,'worship.setlists','edit',teams),'canPublish',private.worship_can(p_org,p_unit,'worship.setlists','approve',teams));
 end if;
 select * into l from private.worship_setlists where service_id=sv.id for update;
 if p_action='save' then
  if not private.worship_can(p_org,p_unit,'worship.setlists',case when l.id is null then 'create' else 'edit' end,teams) then raise exception 'worship_access_denied' using errcode='42501';end if;
  if sv.status='cancelled' then raise exception 'service_cancelled' using errcode='22023';end if;
  if coalesce((p_data->>'version')::integer,0)<>coalesce(l.version,0) then raise exception 'setlist_version_conflict' using errcode='40001';end if;
  if jsonb_typeof(coalesce(p_data->'items','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'items','[]'))>40 then raise exception 'invalid_setlist' using errcode='22023';end if;
  if l.id is null then
   insert into private.worship_setlists(organization_id,unit_id,service_id,notes,updated_by) values(p_org,p_unit,sv.id,coalesce(p_data->>'notes',''),auth.uid()) returning * into l;
  else
   update private.worship_setlists set notes=coalesce(p_data->>'notes',''),version=version+1,updated_by=auth.uid(),updated_at=now(),status=case when status='published' and coalesce((p_data->>'keepPublished')::boolean,true) then 'published' else 'draft' end where id=l.id returning * into l;
  end if;
  select coalesce(array_agg(song_id),'{}') into prev from private.worship_setlist_items where setlist_id=l.id;
  delete from private.worship_setlist_items where setlist_id=l.id;
  for it in select * from jsonb_array_elements(coalesce(p_data->'items','[]')) loop
   n:=n+1;
   select * into song from private.worship_songs where id=nullif(it->>'song','')::uuid and organization_id=p_org and unit_id=p_unit;
   if not found or song.status='archived' and not song.id=any(prev) then raise exception 'invalid_setlist_song' using errcode='22023';end if;
   if nullif(it->>'minister','') is not null and not exists(select 1 from public.people where id=(it->>'minister')::uuid and organization_id=p_org and status<>'rejected') then raise exception 'invalid_setlist_minister' using errcode='22023';end if;
   insert into private.worship_setlist_items(setlist_id,position,song_id,song_key,minister_person_id,notes) values(l.id,n,song.id,coalesce(nullif(it->>'key',''),song.original_key),nullif(it->>'minister','')::uuid,coalesce(it->>'notes',''));
  end loop;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'worship.setlist.saved','worship_setlist',l.id,jsonb_build_object('service',sv.id,'songs',n));
  return jsonb_build_object('ok',true,'id',l.id,'version',l.version,'status',l.status);
 elsif p_action in('publish','unpublish') then
  if l.id is null then raise exception 'setlist_not_found' using errcode='22023';end if;
  if not private.worship_can(p_org,p_unit,'worship.setlists','approve',teams) then raise exception 'worship_access_denied' using errcode='42501';end if;
  if coalesce((p_data->>'version')::integer,0)<>l.version then raise exception 'setlist_version_conflict' using errcode='40001';end if;
  if p_action='publish' and not exists(select 1 from private.worship_setlist_items where setlist_id=l.id) then raise exception 'setlist_empty' using errcode='22023';end if;
  update private.worship_setlists set status=case when p_action='publish' then 'published' else 'draft' end,version=version+1,updated_by=auth.uid(),updated_at=now() where id=l.id returning * into l;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'worship.setlist.'||p_action||'ed','worship_setlist',l.id,jsonb_build_object('service',sv.id));
  return jsonb_build_object('ok',true,'id',l.id,'version',l.version,'status',l.status);
 end if;
 raise exception 'invalid_setlist' using errcode='22023';
end $$;

do $grants$
declare f text;
begin
 foreach f in array array['worship_songs','worship_setlists'] loop
  execute format('revoke all on function private.%s(uuid,uuid,text,jsonb) from public,anon,service_role',f);
  execute format('grant execute on function private.%s(uuid,uuid,text,jsonb) to authenticated',f);
  execute format('create function public.%1$s(p_org uuid,p_unit uuid,p_action text,p_data jsonb default ''{}'') returns jsonb language sql security invoker set search_path='''' as $f$ select private.%1$s(p_org,p_unit,p_action,p_data) $f$',f);
  execute format('revoke all on function public.%s(uuid,uuid,text,jsonb) from public,anon,service_role',f);
  execute format('grant execute on function public.%s(uuid,uuid,text,jsonb) to authenticated',f);
 end loop;
end $grants$;
revoke all on function private.worship_clean_tags(jsonb) from public,anon,authenticated,service_role;
