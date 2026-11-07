begin;
set local lock_timeout='5s';
-- Etapa 4 · PR 3: chat da comunidade no Supabase, com tempo real e moderação.
-- Substitui o chat antigo (Cloudflare D1, desativado). Regras:
-- * Só adultos (18+) com cadastro de pessoa ativo e e-mail confirmado conversam (proteção de crianças e adolescentes).
-- * Canais por igreja (todos os membros ou só equipe; envio livre ou só moderação) e conversas diretas entre adultos do mesmo ministério.
-- * Moderação: ocultar, silenciar, denúncias (3 denúncias ocultam), palavras bloqueadas, limite de envio.
-- * Tempo real por Broadcast privado: o aviso leva só o id; o conteúdo é sempre lido pelas funções abaixo.

create table private.chat_rooms(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid references public.organization_units(id) on delete cascade,
 kind text not null check(kind in('channel','direct')),
 name text not null default '' check(length(name)<=80),
 description text not null default '' check(length(description)<=280),
 audience text not null default 'members' check(audience in('members','staff')),
 posting text not null default 'all' check(posting in('all','moderators')),
 direct_key text unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 archived_at timestamptz,
 version integer not null default 1,
 check(kind='direct' and direct_key is not null and unit_id is null or kind='channel' and direct_key is null and unit_id is not null and length(btrim(name))>=2)
);
create index chat_rooms_org on private.chat_rooms(organization_id,unit_id) where archived_at is null;
create index chat_rooms_unit on private.chat_rooms(unit_id);
create index chat_rooms_created_by on private.chat_rooms(created_by);

create table private.chat_members(
 room_id uuid not null references private.chat_rooms(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null default 'member' check(role in('member','moderator')),
 muted_until timestamptz,
 muted_by uuid references auth.users(id),
 last_read_at timestamptz not null default '-infinity',
 joined_at timestamptz not null default clock_timestamp(),
 primary key(room_id,user_id)
);
create index chat_members_user on private.chat_members(user_id);
create index chat_members_muted_by on private.chat_members(muted_by);

create table private.chat_messages(
 id uuid primary key default extensions.gen_random_uuid(),
 room_id uuid not null references private.chat_rooms(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 client_id uuid not null,
 body text not null check(length(btrim(body)) between 1 and 2000),
 reply_to uuid references private.chat_messages(id) on delete set null,
 created_at timestamptz not null default clock_timestamp(),
 deleted_at timestamptz,
 hidden_at timestamptz,
 hidden_by uuid references auth.users(id),
 hidden_reason text check(hidden_reason is null or hidden_reason in('moderator','reports')),
 unique(room_id,user_id,client_id)
);
create index chat_messages_room on private.chat_messages(room_id,created_at desc);
create index chat_messages_user on private.chat_messages(user_id,created_at desc);
create index chat_messages_org on private.chat_messages(organization_id);
create index chat_messages_reply on private.chat_messages(reply_to);
create index chat_messages_hidden_by on private.chat_messages(hidden_by);

create table private.chat_reports(
 message_id uuid not null references private.chat_messages(id) on delete cascade,
 reporter uuid not null references auth.users(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 reason text not null check(reason in('ofensa','assedio','spam','golpe','outro')),
 created_at timestamptz not null default clock_timestamp(),
 resolved_at timestamptz,
 resolved_by uuid references auth.users(id),
 primary key(message_id,reporter)
);
create index chat_reports_open on private.chat_reports(organization_id,created_at) where resolved_at is null;
create index chat_reports_reporter on private.chat_reports(reporter);
create index chat_reports_resolved_by on private.chat_reports(resolved_by);

create table private.chat_settings(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 enabled boolean not null default true,
 blocked_words text[] not null default '{}' check(cardinality(blocked_words)<=200),
 version integer not null default 1,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default clock_timestamp()
);
create index chat_settings_updated_by on private.chat_settings(updated_by);

alter table private.chat_rooms enable row level security;
alter table private.chat_members enable row level security;
alter table private.chat_messages enable row level security;
alter table private.chat_reports enable row level security;
alter table private.chat_settings enable row level security;
revoke all on private.chat_rooms,private.chat_members,private.chat_messages,private.chat_reports,private.chat_settings from public,anon,authenticated,service_role;

-- ── Quem é quem ─────────────────────────────────────────────────────────────
-- Adulto com pessoa ativa vinculada ao login, no ministério.
create function private.chat_adult(p_org uuid,p_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id
  where m.organization_id=p_org and m.user_id=p_user and m.status='active' and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false))
 and (select count(*) from public.people p where p.organization_id=p_org and p.auth_user_id=p_user and p.status='active')=1
 and exists(select 1 from public.people p where p.organization_id=p_org and p.auth_user_id=p_user and p.status='active' and p.birth_date is not null and p.birth_date<=current_date-interval '18 years')
 and exists(select 1 from public.organizations o where o.id=p_org and o.status in('active','trial'))
 and coalesce((select enabled from private.chat_settings where organization_id=p_org),true);
$$;
create function private.chat_staff(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor','secretary','leader','finance']::public.membership_role[])
  and (p_unit is null or private.can_access_unit(p_org,p_unit,array['read','manage','admin']::public.unit_access_level[]));
$$;
create function private.chat_moderator(r private.chat_rooms) returns boolean language sql stable security definer set search_path='' as $$
 select r.kind='channel' and private.has_organization_role(r.organization_id,array['owner','admin','pastor','secretary']::public.membership_role[])
   and private.can_access_unit(r.organization_id,r.unit_id,array['read','manage','admin']::public.unit_access_level[])
  or r.kind='channel' and exists(select 1 from private.chat_members m where m.room_id=r.id and m.user_id=auth.uid() and m.role='moderator');
$$;
-- Moderação da igreja lê os canais mesmo sem cadastro de pessoa; conversar exige ser adulto.
create function private.chat_unit_moderator(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor','secretary']::public.membership_role[])
  and private.can_access_unit(p_org,p_unit,array['read','manage','admin']::public.unit_access_level[]);
$$;
create function private.chat_can_read(r private.chat_rooms) returns boolean language sql stable security definer set search_path='' as $$
 select r.archived_at is null and (private.chat_adult(r.organization_id) and case
  when r.kind='direct' then exists(select 1 from private.chat_members m where m.room_id=r.id and m.user_id=auth.uid())
  when r.audience='staff' then private.chat_staff(r.organization_id,r.unit_id)
  else private.community_scope(r.organization_id,r.unit_id) or private.chat_staff(r.organization_id,r.unit_id) end
  or r.kind='channel' and private.chat_unit_moderator(r.organization_id,r.unit_id));
$$;
revoke all on function private.chat_unit_moderator(uuid,uuid),private.chat_adult(uuid,uuid),private.chat_staff(uuid,uuid),private.chat_moderator(private.chat_rooms),private.chat_can_read(private.chat_rooms) from public,anon,authenticated,service_role;

-- Inscrição no canal de tempo real 'chat:<sala>' (Broadcast privado).
create function public.chat_listen(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select private.chat_can_read(r) from private.chat_rooms r where r.id=p_room),false);
$$;
revoke all on function public.chat_listen(uuid) from public,anon;
grant execute on function public.chat_listen(uuid) to authenticated;
do $$
begin
 if to_regclass('realtime.messages') is not null then
  execute $p$create policy vinha_chat_listen on realtime.messages for select to authenticated using (
   realtime.messages.extension='broadcast' and realtime.topic() ~ '^chat:[0-9a-f-]{36}$' and public.chat_listen(substr(realtime.topic(),6)::uuid))$p$;
 end if;
end $$;

-- Aviso de tempo real: só o id da mensagem e da sala.
create function private.chat_broadcast() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
  begin
   perform realtime.send(jsonb_build_object('id',new.id,'room',new.room_id,'op',lower(tg_op)),'chat','chat:'||new.room_id::text,true);
  exception when others then null;
  end;
 end if;
 return null;
end $$;
revoke all on function private.chat_broadcast() from public,anon,authenticated,service_role;
create trigger chat_messages_broadcast after insert or update on private.chat_messages for each row execute function private.chat_broadcast();

-- ── Leitura ─────────────────────────────────────────────────────────────────
create function private.chat_message_json(m private.chat_messages,moderator boolean) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',m.id,'room',m.room_id,'createdAt',m.created_at,'mine',m.user_id=auth.uid(),'replyTo',m.reply_to,
  'sender',coalesce((select regexp_replace(btrim(p.full_name),'^(\S+)(\s.*)?\s(\S)\S*$','\1 \3.')
    from public.people p where p.organization_id=m.organization_id and p.auth_user_id=m.user_id and p.status='active' limit 1),'Membro'),
  'senderId',case when moderator then m.user_id end,
  'state',case when m.deleted_at is not null then 'deleted' when m.hidden_at is not null then 'hidden' else 'visible' end,
  'body',case when m.deleted_at is not null then '' when m.hidden_at is not null and not moderator then '' else m.body end,
  'hiddenReason',case when moderator then m.hidden_reason end,
  'reports',case when moderator then (select count(*) from private.chat_reports r where r.message_id=m.id and r.resolved_at is null) end);
$$;
revoke all on function private.chat_message_json(private.chat_messages,boolean) from public,anon,authenticated,service_role;

-- ── Comandos ────────────────────────────────────────────────────────────────
create function private.chat(p_org uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();r private.chat_rooms;m private.chat_messages;mem private.chat_members;mod boolean;words text[];hit text;target uuid;k text;n integer;result jsonb;
begin
 if actor is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'chat_denied' using errcode='42501';end if;
 -- Conversar (enviar, denunciar, conversa direta) exige adulto; a moderação da igreja pode moderar sem cadastro de pessoa.
 if (p_action in('send','report','direct','people') or not private.has_organization_role(p_org,array['owner','admin','pastor','secretary']::public.membership_role[]))
  and not private.chat_adult(p_org) then raise exception 'chat_adult_only' using errcode='42501';end if;
 if p_data ? 'room' then
  if coalesce(p_data->>'room','') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  select * into r from private.chat_rooms where id=(p_data->>'room')::uuid and organization_id=p_org;
  if not found or not private.chat_can_read(r) then raise exception 'chat_denied' using errcode='42501';end if;
  mod:=private.chat_moderator(r);
 end if;

 if p_action='rooms' then
  return jsonb_build_object('rooms',coalesce((select jsonb_agg(x order by x->>'kind',x->>'last' desc nulls last) from(
   select jsonb_build_object('id',c.id,'kind',c.kind,'unit',c.unit_id,'audience',c.audience,'posting',c.posting,'description',c.description,'version',c.version,
    'name',case when c.kind='channel' then c.name else coalesce((select p.full_name from private.chat_members o join public.people p on p.organization_id=c.organization_id and p.auth_user_id=o.user_id and p.status='active' where o.room_id=c.id and o.user_id<>actor limit 1),'Conversa') end,
    'moderator',private.chat_moderator(c),
    'last',(select max(created_at) from private.chat_messages x where x.room_id=c.id),
    'unread',(select count(*) from private.chat_messages x where x.room_id=c.id and x.user_id<>actor and x.deleted_at is null and x.hidden_at is null
      and x.created_at>coalesce((select last_read_at from private.chat_members cm where cm.room_id=c.id and cm.user_id=actor),'-infinity'))) x
   from private.chat_rooms c where c.organization_id=p_org and private.chat_can_read(c) limit 200)q),'[]'));

 elsif p_action='messages' then
  if p_data-array['room','before']<>'{}'::jsonb or p_data ? 'before' and coalesce(p_data->>'before','')!~'^\d{4}-' then raise exception 'invalid_chat' using errcode='22023';end if;
  select coalesce(jsonb_agg(private.chat_message_json(x,mod) order by x.created_at),'[]') into result from(
   select * from private.chat_messages where room_id=r.id and (not p_data ? 'before' or created_at<(p_data->>'before')::timestamptz) order by created_at desc limit 50) x;
  if not p_data ? 'before' then
   insert into private.chat_members(room_id,user_id,last_read_at) values(r.id,actor,clock_timestamp())
    on conflict(room_id,user_id) do update set last_read_at=clock_timestamp();
  end if;
  return jsonb_build_object('room',r.id,'moderator',mod,'canPost',(r.posting='all' or mod) and not exists(select 1 from private.chat_members cm where cm.room_id=r.id and cm.user_id=actor and cm.muted_until>now()),
   'mutedUntil',(select muted_until from private.chat_members cm where cm.room_id=r.id and cm.user_id=actor and cm.muted_until>now()),'messages',result);

 elsif p_action='message' then
  if p_data-array['room','id']<>'{}'::jsonb or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  select * into m from private.chat_messages where id=(p_data->>'id')::uuid and room_id=r.id;
  if not found then raise exception 'chat_denied' using errcode='42501';end if;
  return private.chat_message_json(m,mod);

 elsif p_action='send' then
  if p_data-array['room','body','client','reply']<>'{}'::jsonb or coalesce(p_data->>'client','')!~'^[0-9a-f-]{36}$' or length(btrim(coalesce(p_data->>'body',''))) not between 1 and 2000
   or p_data ? 'reply' and coalesce(p_data->>'reply','')!~'^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  select * into m from private.chat_messages where room_id=r.id and user_id=actor and client_id=(p_data->>'client')::uuid;
  if found then return jsonb_build_object('ok',true,'message',private.chat_message_json(m,mod));end if;
  if r.posting='moderators' and not mod then raise exception 'chat_read_only' using errcode='42501';end if;
  if exists(select 1 from private.chat_members cm where cm.room_id=r.id and cm.user_id=actor and cm.muted_until>now()) then raise exception 'chat_muted' using errcode='42501';end if;
  if r.kind='direct' and exists(select 1 from private.chat_members o where o.room_id=r.id and o.user_id<>actor and not private.chat_adult(p_org,o.user_id)) then raise exception 'chat_direct_closed' using errcode='42501';end if;
  if (select count(*) from private.chat_messages where user_id=actor and organization_id=p_org and created_at>clock_timestamp()-interval '30 seconds')>=10 then raise exception 'chat_slow_down' using errcode='54000';end if;
  select blocked_words into words from private.chat_settings where organization_id=p_org;
  select w into hit from unnest(coalesce(words,'{}')) w where position(lower(w) in lower(p_data->>'body'))>0 limit 1;
  if hit is not null then raise exception 'chat_blocked_word' using errcode='22023';end if;
  if p_data ? 'reply' and not exists(select 1 from private.chat_messages x where x.id=(p_data->>'reply')::uuid and x.room_id=r.id) then raise exception 'invalid_chat' using errcode='22023';end if;
  insert into private.chat_members(room_id,user_id,last_read_at) values(r.id,actor,clock_timestamp()) on conflict(room_id,user_id) do update set last_read_at=clock_timestamp();
  insert into private.chat_messages(room_id,organization_id,user_id,client_id,body,reply_to) values(r.id,p_org,actor,(p_data->>'client')::uuid,btrim(p_data->>'body'),nullif(p_data->>'reply','')::uuid) returning * into m;
  return jsonb_build_object('ok',true,'message',private.chat_message_json(m,mod));

 elsif p_action='delete' then
  if p_data-array['room','id']<>'{}'::jsonb or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  update private.chat_messages set deleted_at=clock_timestamp() where id=(p_data->>'id')::uuid and room_id=r.id and user_id=actor and deleted_at is null returning * into m;
  if not found then raise exception 'chat_denied' using errcode='42501';end if;
  return jsonb_build_object('ok',true);

 elsif p_action='report' then
  if p_data-array['room','id','reason']<>'{}'::jsonb or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' or coalesce(p_data->>'reason','') not in('ofensa','assedio','spam','golpe','outro') then raise exception 'invalid_chat' using errcode='22023';end if;
  select * into m from private.chat_messages where id=(p_data->>'id')::uuid and room_id=r.id and deleted_at is null for update;
  if not found or m.user_id=actor then raise exception 'chat_denied' using errcode='42501';end if;
  insert into private.chat_reports(message_id,reporter,organization_id,reason) values(m.id,actor,p_org,p_data->>'reason') on conflict do nothing;
  select count(*) into n from private.chat_reports where message_id=m.id and resolved_at is null;
  if n>=3 and m.hidden_at is null then update private.chat_messages set hidden_at=clock_timestamp(),hidden_reason='reports' where id=m.id;end if;
  return jsonb_build_object('ok',true,'hidden',n>=3);

 elsif p_action='direct' then
  if p_data-array['person']<>'{}'::jsonb or coalesce(p_data->>'person','')!~'^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  select p.auth_user_id into target from public.people p where p.id=(p_data->>'person')::uuid and p.organization_id=p_org and p.status='active' and p.auth_user_id is not null;
  if target is null or target=actor or not private.chat_adult(p_org,target) then raise exception 'chat_direct_unavailable' using errcode='22023';end if;
  k:=p_org::text||':'||least(actor::text,target::text)||':'||greatest(actor::text,target::text);
  insert into private.chat_rooms(organization_id,kind,direct_key,created_by) values(p_org,'direct',k,actor) on conflict(direct_key) do nothing;
  select * into r from private.chat_rooms where direct_key=k;
  insert into private.chat_members(room_id,user_id) values(r.id,actor),(r.id,target) on conflict do nothing;
  update private.chat_rooms set archived_at=null where id=r.id and archived_at is not null;
  return jsonb_build_object('ok',true,'room',r.id);

 elsif p_action='people' then
  -- Adultos do ministério para iniciar conversa (nome e igreja apenas).
  if p_data-array['search']<>'{}'::jsonb or length(coalesce(p_data->>'search',''))>60 or length(btrim(coalesce(p_data->>'search','')))<2 then raise exception 'invalid_chat' using errcode='22023';end if;
  return jsonb_build_object('people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'unit',u.name) order by p.full_name) from(
   select p.* from public.people p where p.organization_id=p_org and p.status='active' and p.auth_user_id is not null and p.auth_user_id<>actor
    and p.full_name ilike '%'||replace(replace(replace(btrim(p_data->>'search'),'\','\\'),'%','\%'),'_','\_')||'%' and private.chat_adult(p_org,p.auth_user_id) order by p.full_name limit 20) p
   left join public.organization_units u on u.id=p.unit_id),'[]'));

 -- ── Moderação ──
 elsif p_action in('hide','unhide') then
  if not mod then raise exception 'chat_denied' using errcode='42501';end if;
  if p_data-array['room','id']<>'{}'::jsonb or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  update private.chat_messages set hidden_at=case when p_action='hide' then clock_timestamp() end,hidden_by=case when p_action='hide' then actor end,hidden_reason=case when p_action='hide' then 'moderator' end
   where id=(p_data->>'id')::uuid and room_id=r.id returning * into m;
  if not found then raise exception 'chat_denied' using errcode='42501';end if;
  update private.chat_reports set resolved_at=clock_timestamp(),resolved_by=actor where message_id=m.id and resolved_at is null;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'chat.message.'||p_action,'chat_message',m.id::text,jsonb_build_object('room',r.id));
  return jsonb_build_object('ok',true,'message',private.chat_message_json(m,true));

 elsif p_action='mute' then
  if not mod then raise exception 'chat_denied' using errcode='42501';end if;
  if p_data-array['room','user','minutes']<>'{}'::jsonb or coalesce(p_data->>'user','')!~'^[0-9a-f-]{36}$' or coalesce(p_data->>'minutes','')!~'^\d{1,5}$' or (p_data->>'minutes')::integer>43200 then raise exception 'invalid_chat' using errcode='22023';end if;
  target:=(p_data->>'user')::uuid;
  if target=actor or not exists(select 1 from private.chat_messages where room_id=r.id and user_id=target) and not exists(select 1 from private.chat_members where room_id=r.id and user_id=target) then raise exception 'chat_denied' using errcode='42501';end if;
  insert into private.chat_members(room_id,user_id,muted_until,muted_by) values(r.id,target,case when (p_data->>'minutes')::integer>0 then clock_timestamp()+make_interval(mins=>(p_data->>'minutes')::integer) end,actor)
   on conflict(room_id,user_id) do update set muted_until=excluded.muted_until,muted_by=actor;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'chat.member.mute','chat_room',r.id::text,jsonb_build_object('user',target,'minutes',(p_data->>'minutes')::integer));
  return jsonb_build_object('ok',true);

 elsif p_action='reports' then
  if p_data<>'{}'::jsonb then raise exception 'invalid_chat' using errcode='22023';end if;
  return jsonb_build_object('reports',coalesce((select jsonb_agg(x order by x->>'first') from(
   select jsonb_build_object('message',private.chat_message_json(msg,true),'roomName',c.name,'count',a.n,'reasons',a.reasons,'first',a.first) x
   from(select rep.message_id,count(*) n,jsonb_agg(distinct rep.reason) reasons,min(rep.created_at) first from private.chat_reports rep
     where rep.organization_id=p_org and rep.resolved_at is null group by rep.message_id) a
   join private.chat_messages msg on msg.id=a.message_id join private.chat_rooms c on c.id=msg.room_id
   where private.chat_moderator(c) order by a.first limit 100)q),'[]'));

 elsif p_action='resolve' then
  if p_data-array['room','id']<>'{}'::jsonb or not mod or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' then raise exception 'chat_denied' using errcode='42501';end if;
  update private.chat_reports set resolved_at=clock_timestamp(),resolved_by=actor where message_id=(p_data->>'id')::uuid and resolved_at is null
   and exists(select 1 from private.chat_messages x where x.id=message_id and x.room_id=r.id);
  update private.chat_messages set hidden_at=null,hidden_reason=null where id=(p_data->>'id')::uuid and room_id=r.id and hidden_reason='reports';
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'chat.report.kept','chat_message',p_data->>'id','{}');
  return jsonb_build_object('ok',true);

 elsif p_action='room_save' then
  if p_data-array['id','version','unit','name','description','audience','posting']<>'{}'::jsonb or coalesce(p_data->>'unit','')!~'^[0-9a-f-]{36}$'
   or length(btrim(coalesce(p_data->>'name',''))) not between 2 and 80 or length(coalesce(p_data->>'description',''))>280
   or coalesce(p_data->>'audience','') not in('members','staff') or coalesce(p_data->>'posting','') not in('all','moderators') then raise exception 'invalid_chat' using errcode='22023';end if;
  if not private.has_organization_role(p_org,array['owner','admin','pastor','secretary']::public.membership_role[]) or not private.can_access_unit(p_org,(p_data->>'unit')::uuid,array['manage','admin']::public.unit_access_level[]) then raise exception 'chat_denied' using errcode='42501';end if;
  if (p_data->>'id') is null then
   if (select count(*) from private.chat_rooms where organization_id=p_org and kind='channel' and archived_at is null)>=100 then raise exception 'chat_room_limit' using errcode='22023';end if;
   insert into private.chat_rooms(organization_id,unit_id,kind,name,description,audience,posting,created_by)
    values(p_org,(p_data->>'unit')::uuid,'channel',btrim(p_data->>'name'),btrim(coalesce(p_data->>'description','')),p_data->>'audience',p_data->>'posting',actor) returning * into r;
  else
   update private.chat_rooms set name=btrim(p_data->>'name'),description=btrim(coalesce(p_data->>'description','')),audience=p_data->>'audience',posting=p_data->>'posting',version=version+1
    where id=(p_data->>'id')::uuid and organization_id=p_org and kind='channel' and unit_id=(p_data->>'unit')::uuid and version=(p_data->>'version')::integer and archived_at is null returning * into r;
   if not found then raise exception 'chat_conflict' using errcode='40001';end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'chat.room.saved','chat_room',r.id::text,jsonb_build_object('name',r.name,'audience',r.audience,'posting',r.posting));
  return jsonb_build_object('ok',true,'id',r.id,'version',r.version);

 elsif p_action='room_archive' then
  if p_data-array['id']<>'{}'::jsonb or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' then raise exception 'invalid_chat' using errcode='22023';end if;
  update private.chat_rooms c set archived_at=clock_timestamp() where c.id=(p_data->>'id')::uuid and c.organization_id=p_org and c.kind='channel' and c.archived_at is null
   and private.has_organization_role(p_org,array['owner','admin','pastor','secretary']::public.membership_role[]) and private.can_access_unit(p_org,c.unit_id,array['manage','admin']::public.unit_access_level[]) returning * into r;
  if not found then raise exception 'chat_denied' using errcode='42501';end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'chat.room.archived','chat_room',r.id::text,'{}');
  return jsonb_build_object('ok',true);

 elsif p_action='settings' then
  if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'chat_denied' using errcode='42501';end if;
  insert into private.chat_settings(organization_id) values(p_org) on conflict do nothing;
  if p_data<>'{}'::jsonb then
   if p_data-array['enabled','blockedWords','version']<>'{}'::jsonb or jsonb_typeof(p_data->'enabled')<>'boolean' or jsonb_typeof(p_data->'blockedWords')<>'array' or jsonb_array_length(p_data->'blockedWords')>200
    or exists(select 1 from jsonb_array_elements(p_data->'blockedWords') w where jsonb_typeof(w)<>'string' or length(btrim(w#>>'{}')) not between 2 and 40) then raise exception 'invalid_chat' using errcode='22023';end if;
   update private.chat_settings set enabled=(p_data->>'enabled')::boolean,blocked_words=(select coalesce(array_agg(distinct lower(btrim(w))),'{}') from jsonb_array_elements_text(p_data->'blockedWords') w),
    version=version+1,updated_by=actor,updated_at=clock_timestamp() where organization_id=p_org and version=(p_data->>'version')::integer;
   if not found then raise exception 'chat_conflict' using errcode='40001';end if;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'chat.settings.saved','organization',p_org::text,jsonb_build_object('enabled',(p_data->>'enabled')::boolean));
  end if;
  return (select jsonb_build_object('enabled',enabled,'blockedWords',to_jsonb(blocked_words),'version',version) from private.chat_settings where organization_id=p_org);
 end if;
 raise exception 'invalid_chat' using errcode='22023';
end $$;
revoke all on function private.chat(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.chat(p_org uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.chat(p_org,p_action,p_data)$$;
revoke all on function public.chat(uuid,text,jsonb) from public,anon;
grant execute on function public.chat(uuid,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
