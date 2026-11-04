set local lock_timeout='5s';
alter table private.programming_requests add column information_payload jsonb;
create table private.event_information(
 event_id uuid primary key references private.church_app_events(id),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 info jsonb not null default '{}',targets uuid[] not null,updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),check(cardinality(targets) between 1 and 200));
create index event_information_unit on private.event_information(unit_id,organization_id);
create index event_information_org on private.event_information(organization_id);
alter table private.event_information enable row level security;
revoke all on private.event_information from public,anon,authenticated,service_role;
create function private.event_manager(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) and private.member_event_enabled(p_org,p_unit) and exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active');$$;
revoke all on function private.event_manager(uuid,uuid) from public,anon,authenticated,service_role;
create function private.event_information_valid(d jsonb,e private.church_app_events) returns boolean language plpgsql set search_path='' as $$
declare x jsonb;z jsonb:=d->'venue';
begin
 if d is null or jsonb_typeof(d)<>'object' or octet_length(d::text)>80000 or d-array['venue','scope','targets','group','groupVersion','schedule','guests','contacts','gallery','team']<>'{}' or not(d ?& array['venue','scope','targets','group','groupVersion','schedule','guests','contacts','gallery','team']) then return false;end if;
 if jsonb_typeof(z)<>'object' or not(z ?& array['format','church','postal_code','street','number','complement','district','city','state','onlineUrl']) or z-array['format','church','postal_code','street','number','complement','district','city','state','onlineUrl']<>'{}' or z->>'format' not in('presential','online','hybrid') or exists(select 1 from jsonb_each(z)q where jsonb_typeof(q.value)<>'string' or length(q.value#>>'{}')>2000) then return false;end if;
 if coalesce(z->>'onlineUrl','')<>'' and not private.ministry_public_url(z->>'onlineUrl') or coalesce(z->>'postal_code','')<>'' and z->>'postal_code'!~'^[0-9]{5}-?[0-9]{3}$' or coalesce(z->>'state','')<>'' and z->>'state'!~'^[A-Z]{2}$' then return false;end if;
 if d->>'scope' not in('local','selected','all','group') or jsonb_typeof(d->'targets')<>'array' or jsonb_typeof(d->'schedule')<>'array' or jsonb_array_length(d->'schedule')>100 or jsonb_typeof(d->'guests')<>'array' or jsonb_array_length(d->'guests')>40 or jsonb_typeof(d->'gallery')<>'array' or jsonb_array_length(d->'gallery')>30 or jsonb_typeof(d->'team')<>'array' or jsonb_array_length(d->'team')>30 then return false;end if;
 for x in select value from jsonb_array_elements(d->'schedule') loop
  if x-array['id','title','starts','ends','location']<>'{}' or not(x ?& array['id','title','starts','ends','location']) or length(btrim(x->>'title')) not between 2 and 160 or length(x->>'location')>160 or (x->>'starts')::timestamptz<e.starts_at or (x->>'ends')::timestamptz>e.ends_at or (x->>'ends')::timestamptz<=(x->>'starts')::timestamptz then return false;end if;
 end loop;
 for x in select value from jsonb_array_elements(d->'guests') loop
  if x-array['id','name','role','bio','url','photo']<>'{}' or not(x ?& array['id','name','role','bio','url','photo']) or length(btrim(x->>'name')) not between 2 and 160 or length(x->>'role')>160 or length(x->>'bio')>3000 or (x->>'url'<>'' and not private.ministry_public_url(x->>'url')) or (x->>'photo'<>'' and not (private.ministry_public_url(x->>'photo') or x->>'photo'~'^/api/event-images/[0-9a-f-]{36}$')) then return false;end if;
 end loop;
 for x in select value from jsonb_array_elements(d->'gallery') loop
  if x-array['id','url','caption']<>'{}' or not(x ?& array['id','url','caption']) or not (private.ministry_public_url(x->>'url') or x->>'url'~'^/api/event-images/[0-9a-f-]{36}$') or length(x->>'caption')>200 then return false;end if;
 end loop;
 if jsonb_typeof(d->'contacts')<>'object' or not(d->'contacts' ?& array['phone','whatsapp','email','instagram','facebook','youtube','website']) or (d->'contacts')-array['phone','whatsapp','email','instagram','facebook','youtube','website']<>'{}' then return false;end if;
 for x in select value from jsonb_each(d->'contacts') loop if jsonb_typeof(x)<>'string' or length(x#>>'{}')>2000 then return false;end if;end loop;
 for x in select value from jsonb_each(d->'contacts') where key in('instagram','facebook','youtube','website') loop if x#>>'{}'<>'' and not private.ministry_public_url(x#>>'{}') then return false;end if;end loop;
 return true;
exception when others then return false;
end $$;
revoke all on function private.event_information_valid(jsonb,private.church_app_events) from public,anon,authenticated,service_role;
create function private.save_event_information(p_org uuid,p_unit uuid,p_event uuid,p_info jsonb) returns void language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;dest uuid[];old_dest uuid[];g private.publishing_groups;actor uuid;z jsonb:=p_info->'venue';
begin
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;
 if not found or not private.event_manager(p_org,p_unit) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if not private.event_information_valid(p_info,e) or e.status='published' and ((z->>'format' in('presential','hybrid') and (btrim(z->>'street')='' or btrim(z->>'number')='' or btrim(z->>'city')='' or btrim(z->>'state')='')) or (z->>'format' in('online','hybrid') and z->>'onlineUrl'='')) then raise exception 'invalid_event_information' using errcode='22023';end if;
 if z->>'church'<>'' and (not private.can_access_unit(p_org,(z->>'church')::uuid,array['read','manage','admin']::public.unit_access_level[]) or not exists(select 1 from public.organization_units where id=(z->>'church')::uuid and organization_id=p_org and status='active')) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_info->>'scope'='local' then dest:=array[p_unit];elsif p_info->>'scope'='all' then select array_agg(id order by id) into dest from public.organization_units where organization_id=p_org and private.event_manager(p_org,id);
 elsif p_info->>'scope'='group' then select * into g from private.publishing_groups where id=(p_info->>'group')::uuid and organization_id=p_org and active for share;if not found or g.version is distinct from (p_info->>'groupVersion')::integer then raise exception 'member_event_changed' using errcode='40001';end if;dest:=g.targets;
 else select array_agg(value::uuid order by value) into dest from jsonb_array_elements_text(p_info->'targets');end if;
 select targets into old_dest from private.event_information where event_id=p_event;
 perform 1 from public.organization_units where organization_id=p_org and id=any(coalesce(old_dest,'{}')||dest) order by id for share;
 if cardinality(dest) is null or cardinality(dest) not between 1 and 200 or cardinality(dest)<>(select count(distinct i) from unnest(dest)i) or exists(select 1 from unnest(coalesce(old_dest,'{}')||dest)i where not private.event_manager(p_org,i)) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 for actor in select value::uuid from jsonb_array_elements_text(p_info->'team') loop
  if not exists(select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id where m.organization_id=p_org and m.user_id=actor and m.status='active' and u.email_confirmed_at is not null and (m.default_unit_id=p_unit or m.role in('owner','admin','pastor') or exists(select 1 from public.membership_unit_access a where a.membership_id=m.id and a.unit_id=p_unit))) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 end loop;
 if exists(select 1 from (select e.cover_url uri union all select value#>>'{}' from jsonb_path_query(p_info,'$.gallery[*].url') q(value) union all select value#>>'{}' from jsonb_path_query(p_info,'$.guests[*].photo') q(value)) refs where uri like '/api/event-images/%' and not exists(select 1 from private.event_images a where a.id=substring(uri from 19)::uuid and a.organization_id=p_org and a.unit_id=p_unit and ready)) then raise exception 'invalid_event_image' using errcode='22023';end if;
 insert into private.event_information(event_id,organization_id,unit_id,info,targets) values(p_event,p_org,p_unit,p_info,dest) on conflict(event_id) do update set info=excluded.info,targets=excluded.targets,updated_at=clock_timestamp();
end $$;
revoke all on function private.save_event_information(uuid,uuid,uuid,jsonb) from public,anon,authenticated,service_role;
alter function private.programming_admin(uuid,uuid,text,uuid,integer,jsonb) rename to programming_admin_base_20261103;
revoke all on function private.programming_admin_base_20261103(uuid,uuid,text,uuid,integer,jsonb) from public,anon,authenticated,service_role;
create function private.programming_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;e private.church_app_events;i uuid;profile jsonb;before_ids uuid[];old_events jsonb;old_profile jsonb;anchor timestamptz;delta interval;
begin
 perform private.community_identity(p_org,p_unit,false);
 if p_action in('create','edit') and p_data ? 'information' then
  if p_action='create' then perform pg_advisory_xact_lock(hashtextextended(p_org::text||p_unit::text||auth.uid()::text||p_id::text,0));if exists(select 1 from private.programming_requests r where r.organization_id=p_org and r.unit_id=p_unit and r.actor_id=auth.uid() and r.request_id=p_id and r.information_payload is not null and r.information_payload is distinct from p_data) then raise exception 'member_event_changed' using errcode='40001';end if;select array_agg((value#>>'{}')::uuid) into before_ids from jsonb_array_elements(coalesce((select r.result->'ids' from private.programming_requests r where r.organization_id=p_org and r.unit_id=p_unit and r.actor_id=auth.uid() and r.request_id=p_id),'[]'));end if;
  if p_action='edit' then select jsonb_object_agg(id::text,jsonb_build_object('starts',starts_at,'information',(select info from private.event_information where event_id=e0.id))) into old_events from private.church_app_events e0 where organization_id=p_org and unit_id=p_unit;end if;
  anchor:=(p_data->>'startsLocal')::timestamp at time zone 'America/Sao_Paulo';
  result:=private.programming_admin_base_20261103(p_org,p_unit,p_action,p_id,p_version,(p_data-'information')||case when p_data->>'cover'~'^/api/event-images/[0-9a-f-]{36}$' then jsonb_build_object('cover','') else '{}'::jsonb end);
  for i in select value::uuid from jsonb_array_elements_text(result->'ids') loop
   if before_ids is not null then null;
   else
    select * into e from private.church_app_events where id=i;
    profile:=p_data->'information';
    if p_action='edit' then
     old_profile:=old_events->i::text->'information';
     if old_profile is not null and old_profile<>'null'::jsonb then
      profile:=profile||jsonb_build_object('schedule',old_profile->'schedule','guests',old_profile->'guests','contacts',old_profile->'contacts','gallery',old_profile->'gallery','team',old_profile->'team');
     end if;
     delta:=e.starts_at-(old_events->i::text->>'starts')::timestamptz;
    else delta:=e.starts_at-anchor;end if;
    profile:=jsonb_set(profile,'{schedule}',coalesce((select jsonb_agg(x||jsonb_build_object('starts',(x->>'starts')::timestamptz+delta,'ends',(x->>'ends')::timestamptz+delta)) from jsonb_array_elements(profile->'schedule')x),'[]'));
    if p_data->>'cover'~'^/api/event-images/[0-9a-f-]{36}$' then update private.church_app_events set cover_url=p_data->>'cover' where id=i;end if;
    perform private.save_event_information(p_org,p_unit,i,profile);
   end if;
  end loop;if p_action='create' then update private.programming_requests set information_payload=p_data where organization_id=p_org and unit_id=p_unit and actor_id=auth.uid() and request_id=p_id;end if;return result;
 end if;
 result:=private.programming_admin_base_20261103(p_org,p_unit,p_action,p_id,p_version,p_data);
 if p_action='detail' then return result||jsonb_build_object('information',(select info from private.event_information where event_id=p_id),'publicPath','/eventos/e-'||p_id::text);end if;
 if p_action='publish' then
  for i in select value::uuid from jsonb_array_elements_text(result->'ids') loop
   select * into e from private.church_app_events where id=i;select info into profile from private.event_information where event_id=i;
   if profile is not null then
    if profile->'venue'->>'format' in('presential','hybrid') and (length(btrim(profile->'venue'->>'street'))=0 or length(btrim(profile->'venue'->>'number'))=0 or length(btrim(profile->'venue'->>'city'))=0 or length(btrim(profile->'venue'->>'state'))=0) or profile->'venue'->>'format' in('online','hybrid') and coalesce(profile->'venue'->>'onlineUrl','')='' then raise exception 'invalid_event_information' using errcode='22023';end if;
    perform private.save_event_information(p_org,p_unit,i,profile);
   end if;
  end loop;
 end if;
 return result;
end $$;
revoke all on function private.programming_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.programming_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function private.event_information_admin(p_org uuid,p_unit uuid,p_action text,p_event uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;p private.event_information;manager boolean;result jsonb;
begin
 perform private.community_identity(p_org,p_unit,false);manager:=private.event_manager(p_org,p_unit);
 if p_action='choices' then
  if not manager then raise exception 'member_agenda_denied' using errcode='42501';end if;
  return jsonb_build_object('units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'address',u.address,'phone',u.phone,'email',u.email,'canPublish',private.event_manager(p_org,u.id)) order by u.name) from public.organization_units u where u.organization_id=p_org and u.status='active' and private.can_access_unit(p_org,u.id,array['read','manage','admin']::public.unit_access_level[])),'[]'),
   'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'targets',g.targets,'version',g.version)) from private.publishing_groups g where g.organization_id=p_org and active and not exists(select 1 from unnest(g.targets)t where not private.event_manager(p_org,t))),'[]'),
   'users',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',coalesce(person.full_name,'Usuário confirmado'))) from public.organization_memberships m join auth.users u on u.id=m.user_id left join public.people person on person.auth_user_id=m.user_id and person.organization_id=m.organization_id where m.organization_id=p_org and m.status='active' and u.email_confirmed_at is not null and (m.default_unit_id=p_unit or m.role in('owner','admin','pastor') or exists(select 1 from public.membership_unit_access a where a.membership_id=m.id and a.unit_id=p_unit))),'[]'));
 end if;
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;
 select * into p from private.event_information where event_id=p_event;
 if e.id is null or not manager and not (coalesce(p.info->'team','[]') ? auth.uid()::text) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_action='preview' then
  if not manager then raise exception 'member_agenda_denied' using errcode='42501';end if;
  return jsonb_build_object('preview',true,'event',jsonb_build_object('id',e.id,'title',e.title,'description',e.description,'starts_at',e.starts_at,'ends_at',e.ends_at,'location',e.location,'address',e.address,'cover_url',e.cover_url,'unit',e.unit_id),'information',p.info-'team'-'scope'-'targets'-'group'-'groupVersion','church',(select jsonb_build_object('name',o.name,'slug',o.slug,'primary_color',o.primary_color,'accent_color',o.accent_color,'unit_name',u.name,'logo',coalesce((select logo_png from private.church_branding where scope_id=u.id),(select logo_png from private.church_branding where scope_id=o.id))) from public.organizations o join public.organization_units u on u.organization_id=o.id where o.id=p_org and u.id=p_unit));
 end if;
 if p_action='read' then return jsonb_build_object('event',to_jsonb(e),'information',p.info,'publicPath','/eventos/e-'||p_event::text,'canPublish',manager);end if;
 if p_action<>'save' or p_version is distinct from e.version or e.status='cancelled' then raise exception 'member_event_changed' using errcode='40001';end if;
 if not manager and (p_data-'schedule'-'guests'-'contacts'-'gallery') is distinct from (p.info-'schedule'-'guests'-'contacts'-'gallery') then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if manager then perform private.save_event_information(p_org,p_unit,p_event,p_data);
 else if not private.event_information_valid(p_data,e) then raise exception 'invalid_event_information' using errcode='22023';end if;if exists(select 1 from (select value#>>'{}' uri from jsonb_path_query(p_data,'$.gallery[*].url') q(value) union all select value#>>'{}' from jsonb_path_query(p_data,'$.guests[*].photo') q(value)) refs where uri like '/api/event-images/%' and not exists(select 1 from private.event_images a where a.id=substring(uri from 19)::uuid and a.organization_id=p_org and a.unit_id=p_unit and ready)) then raise exception 'invalid_event_image' using errcode='22023';end if;update private.event_information set info=p_data,updated_at=clock_timestamp() where event_id=p_event;end if;
 update private.church_app_events set version=version+1,updated_at=clock_timestamp() where id=p_event;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'event.information.save','church_app_event',p_event::text);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_information_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.event_information_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.event_information_admin(p_org uuid,p_unit uuid,p_action text,p_event uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_information_admin(p_org,p_unit,p_action,p_event,p_version,p_data)$$;
revoke all on function public.event_information_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.event_information_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function member_app_api.event_page(p_event uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.church_app_events;d jsonb;
begin
 select * into e from private.church_app_events where id=p_event and status='published';
 if e.id is null or not private.member_event_enabled(e.organization_id,e.unit_id) then return null;end if;
 select info-'team'-'group'-'groupVersion'-'targets'-'scope' into d from private.event_information where event_id=e.id;
 return jsonb_build_object('event',jsonb_build_object('id',e.id,'title',e.title,'description',e.description,'starts_at',e.starts_at,'ends_at',e.ends_at,'location',e.location,'address',e.address,'cover_url',e.cover_url,'unit',e.unit_id),'information',d,
 'church',(select jsonb_build_object('name',o.name,'slug',o.slug,'primary_color',o.primary_color,'accent_color',o.accent_color,'unit_name',u.name,'logo',coalesce((select logo_png from private.church_branding where scope_id=u.id),(select logo_png from private.church_branding where scope_id=o.id))) from public.organizations o join public.organization_units u on u.organization_id=o.id where o.id=e.organization_id and u.id=e.unit_id));
end $$;
revoke all on function member_app_api.event_page(uuid) from public,service_role;
grant execute on function member_app_api.event_page(uuid) to anon,authenticated;
create function public.member_event_page(p_event uuid) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.event_page(p_event)$$;
revoke all on function public.member_event_page(uuid) from public,service_role;
grant execute on function public.member_event_page(uuid) to anon,authenticated;
-- Event image files remain private; the public proxy only releases images referenced by a published event.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('vinha-event-images','vinha-event-images',false,5242880,array['image/jpeg','image/png']) on conflict(id) do nothing;
create table private.event_images(id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,path text not null unique,mime text not null check(mime in('image/jpeg','image/png')),ready boolean not null default false,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id));
create index event_images_unit on private.event_images(unit_id,organization_id);
create index event_images_org on private.event_images(organization_id);
create index event_images_creator on private.event_images(created_by);
alter table private.event_images enable row level security;
revoke all on private.event_images from public,anon,authenticated,service_role;
create function private.event_image_command(p_org uuid,p_unit uuid,p_id uuid,p_action text,p_mime text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.event_images;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.event_manager(p_org,p_unit) or p_action not in('prepare','finish') then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_action='prepare' then
  if p_mime not in('image/png','image/jpeg') then raise exception 'invalid_event_image' using errcode='22023';end if;
  insert into private.event_images(id,organization_id,unit_id,path,mime,created_by) values(p_id,p_org,p_unit,p_org::text||'/'||p_unit::text||'/'||p_id::text,p_mime,auth.uid());
 else update private.event_images set ready=true where id=p_id and organization_id=p_org and unit_id=p_unit and created_by=auth.uid();if not found then raise exception 'member_agenda_denied' using errcode='42501';end if;end if;
 select * into a from private.event_images where id=p_id and organization_id=p_org and unit_id=p_unit;
 return jsonb_build_object('path',a.path,'ok',true);
end $$;
revoke all on function private.event_image_command(uuid,uuid,uuid,text,text) from public,anon,service_role;
grant execute on function private.event_image_command(uuid,uuid,uuid,text,text) to authenticated;
create function public.event_image_command(p_org uuid,p_unit uuid,p_id uuid,p_action text,p_mime text default '') returns jsonb language sql security invoker set search_path='' as $$select private.event_image_command(p_org,p_unit,p_id,p_action,p_mime)$$;
revoke all on function public.event_image_command(uuid,uuid,uuid,text,text) from public,anon,service_role;
grant execute on function public.event_image_command(uuid,uuid,uuid,text,text) to authenticated;
create function member_app_api.event_image(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a private.event_images;uri text:='/api/event-images/'||p_id::text;
begin
 select * into a from private.event_images where id=p_id and ready;if not found then return null;end if;
 if not private.event_manager(a.organization_id,a.unit_id) and not exists(select 1 from private.church_app_events e left join private.event_information p on p.event_id=e.id where e.organization_id=a.organization_id and e.unit_id=a.unit_id and (e.status='published' or auth.uid() is not null and p.info->'team' ? auth.uid()::text and private.can_access_unit(e.organization_id,e.unit_id,array['read','manage','admin']::public.unit_access_level[])) and private.member_event_enabled(e.organization_id,e.unit_id) and (e.cover_url=uri or position('"'||uri||'"' in coalesce(p.info::text,''))>0)) then return null;end if;
 return jsonb_build_object('path',a.path,'mime',a.mime);
end $$;
revoke all on function member_app_api.event_image(uuid) from public,service_role;
grant execute on function member_app_api.event_image(uuid) to anon,authenticated;
create function public.member_event_image(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.event_image(p_id)$$;
revoke all on function public.member_event_image(uuid) from public,service_role;
grant execute on function public.member_event_image(uuid) to anon,authenticated;

create or replace function public.programming_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.programming_admin(p_org,p_unit,p_action,p_id,p_version,p_data)$$;

create function private.event_publication_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare d jsonb;z jsonb;
begin
 if new.status='published' and old.status is distinct from new.status then
  select info into d from private.event_information where event_id=new.id;z:=d->'venue';
  if d is not null and ((z->>'format' in('presential','hybrid') and (btrim(z->>'street')='' or btrim(z->>'number')='' or btrim(z->>'city')='' or btrim(z->>'state')='')) or (z->>'format' in('online','hybrid') and z->>'onlineUrl'='')) then raise exception 'invalid_event_information' using errcode='22023';end if;
  if d is not null then perform private.save_event_information(new.organization_id,new.unit_id,new.id,d);end if;
 end if;return new;
end $$;
revoke all on function private.event_publication_guard() from public,anon,authenticated,service_role;
create trigger event_publication_ready before update of status on private.church_app_events for each row execute function private.event_publication_guard();

create or replace function member_app_api.agenda(p_org uuid,p_unit uuid,p_past boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_event_enabled(p_org,p_unit) then return jsonb_build_object('unitId',p_unit,'available',false,'items','[]'::jsonb);end if;
 return jsonb_build_object('unitId',p_unit,'available',true,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from(
  select e.id,e.title,e.description,e.kind,e.starts_at,e.ends_at,e.location,e.address,e.capacity,e.status,e.version,(e.unit_id<>p_unit) as shared,'/eventos/e-'||e.id::text as public_path,coalesce(price.amount,0)::text as price_cents,
  greatest(0,e.capacity-(select count(*) from private.church_app_registrations r where r.event_id=e.id and r.status='confirmed')-(select count(*) from private.member_event_orders o where o.event_id=e.id and o.state='holding' and o.expires_at>now())) as remaining
  from private.church_app_events e left join private.member_event_prices price on price.event_id=e.id where e.organization_id=p_org and (e.unit_id=p_unit or e.status='published' and exists(select 1 from private.event_information info where info.event_id=e.id and p_unit=any(info.targets)) and private.member_event_enabled(p_org,e.unit_id)) and e.status in('published','cancelled')
  and case when p_past then e.ends_at<now() and e.ends_at>now()-interval '1 year' else e.ends_at>=now() end order by e.starts_at limit 100)x),'[]'));
end $$;
