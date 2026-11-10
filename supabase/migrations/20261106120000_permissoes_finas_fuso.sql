begin;
set local lock_timeout='5s';
-- Etapa 3 · PR 2: permissões finas para agenda, entrada, publicação e push (secretaria e liderança),
-- e fuso horário por igreja e unidade nas funções de Programação e Comunicação.
-- Regras antigas continuam valendo: as concessões só acrescentam acesso, e quem não tem concessão vê o mesmo de antes.

-- ── Fuso horário ─────────────────────────────────────────────────────────────
-- unit_id nulo = padrão do ministério; unidade sem linha própria herda o do ministério; sem nada, Brasília.
create table private.church_timezones(
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid references public.organization_units(id) on delete cascade,
 timezone text not null check(timezone ~ '^[A-Za-z]+(/[A-Za-z0-9_+-]+){1,2}$'),
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default clock_timestamp(),
 unique nulls not distinct(organization_id,unit_id)
);
create index church_timezones_unit on private.church_timezones(unit_id);
create index church_timezones_updated_by on private.church_timezones(updated_by);
alter table private.church_timezones enable row level security;
revoke all on private.church_timezones from public,anon,authenticated,service_role;

create function private.unit_timezone(p_unit uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce(
  (select t.timezone from private.church_timezones t where t.unit_id=p_unit),
  (select t.timezone from private.church_timezones t join public.organization_units u on u.organization_id=t.organization_id where u.id=p_unit and t.unit_id is null),
  'America/Sao_Paulo');
$$;
revoke all on function private.unit_timezone(uuid) from public,anon,authenticated,service_role;
-- Fuso não é dado sensível; o painel e os apps leem para mostrar e interpretar horários da igreja.
create function public.unit_timezone(p_unit uuid) returns text language sql stable security definer set search_path='' as $$select private.unit_timezone(p_unit)$$;
revoke all on function public.unit_timezone(uuid) from public;
grant execute on function public.unit_timezone(uuid) to anon,authenticated,service_role;

create function private.timezone_valid(p_tz text) returns boolean language sql stable set search_path='' as $$
 select p_tz ~ '^[A-Za-z]+(/[A-Za-z0-9_+-]+){1,2}$' and exists(select 1 from pg_catalog.pg_timezone_names where name=p_tz);
$$;
revoke all on function private.timezone_valid(text) from public,anon,authenticated,service_role;

-- ── Concessões ───────────────────────────────────────────────────────────────
create table private.staff_grants(
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 scope text not null check(scope in('agenda','checkin','publishing','push')),
 granted_by uuid references auth.users(id),
 granted_at timestamptz not null default clock_timestamp(),
 primary key(organization_id,user_id,unit_id,scope)
);
create index staff_grants_user on private.staff_grants(user_id);
create index staff_grants_unit on private.staff_grants(unit_id);
create index staff_grants_granted_by on private.staff_grants(granted_by);
alter table private.staff_grants enable row level security;
revoke all on private.staff_grants from public,anon,authenticated,service_role;

-- Concessão vale para secretaria e liderança ativas, em igreja ativa, com acesso de leitura à unidade.
create function private.staff_grant(p_org uuid,p_unit uuid,p_scope text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from private.staff_grants g
  join public.organization_memberships m on m.organization_id=g.organization_id and m.user_id=g.user_id and m.status='active' and m.role in('secretary','leader')
  join public.organizations o on o.id=g.organization_id and o.status in('active','trial')
  join public.organization_units u on u.id=g.unit_id and u.organization_id=g.organization_id and u.status='active'
  where g.organization_id=p_org and g.unit_id=p_unit and g.user_id=auth.uid() and g.scope=p_scope)
 and private.can_access_unit(p_org,p_unit,array['read','manage','admin']::public.unit_access_level[]);
$$;
revoke all on function private.staff_grant(uuid,uuid,text) from public,anon,authenticated,service_role;

-- Agenda: a regra anterior (responsável, administração e pastor com acesso de gestão) fica em event_manager_strict;
-- event_manager passa a aceitar também a concessão de agenda. Configuração financeira continua só na regra estrita.
create function private.event_manager_strict(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) and private.member_event_enabled(p_org,p_unit) and exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active');
$$;
revoke all on function private.event_manager_strict(uuid,uuid) from public,anon,authenticated,service_role;
create or replace function private.event_manager(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.event_manager_strict(p_org,p_unit) or private.staff_grant(p_org,p_unit,'agenda') and private.member_event_enabled(p_org,p_unit);
$$;
-- Entrada (QR de ingressos, inscrições e retiradas): quem gere a agenda ou quem recebeu a concessão de entrada.
create function private.checkin_operator(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.event_manager(p_org,p_unit) or private.staff_grant(p_org,p_unit,'checkin') and private.member_event_enabled(p_org,p_unit);
$$;
revoke all on function private.checkin_operator(uuid,uuid) from public,anon,authenticated,service_role;

-- Publicação: regra anterior ou concessão de publicação; o módulo da unidade continua exigido.
create or replace function private.publisher_unit(p_org uuid,p_unit uuid,p_kind text default '') returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_units u where u.id=p_unit and u.organization_id=p_org and u.status='active'
 and (private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or u.communication_autonomy and private.has_organization_role(p_org,array['secretary','leader']::public.membership_role[]) and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[])
  or private.staff_grant(p_org,p_unit,'publishing'))
 and (p_kind in('','category') or private.ministry_module_public(p_org,p_unit,case when p_kind in('channel','live') then 'broadcasts' else 'communication' end)));
$$;
-- Push: regra anterior das publicações (sem concessão de publicação) ou concessão própria de push.
create function private.push_unit(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_units u where u.id=p_unit and u.organization_id=p_org and u.status='active'
 and (private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or u.communication_autonomy and private.has_organization_role(p_org,array['secretary','leader']::public.membership_role[]) and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[])
  or private.staff_grant(p_org,p_unit,'push')));
$$;
revoke all on function private.push_unit(uuid,uuid) from public,anon,authenticated,service_role;
create function private.communication_viewer(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.publisher_unit(p_org,p_unit,'') or private.push_unit(p_org,p_unit);
$$;
revoke all on function private.communication_viewer(uuid,uuid) from public,anon,authenticated,service_role;

-- ── Ajustes nas funções existentes (troca exata de trechos; falha se o texto esperado não existir) ──
-- p_expected: número exato de ocorrências; nulo = pelo menos uma.
create function pg_temp.patch(p_fn regprocedure,p_old text,p_new text,p_expected integer default 1) returns void language plpgsql as $$
declare d text:=pg_get_functiondef(p_fn);n integer:=(length(d)-length(replace(d,p_old,'')))/greatest(length(p_old),1);
begin
 if n<>coalesce(p_expected,greatest(n,1)) then raise exception 'patch %: esperado % ocorrência(s) de [%], encontrado %',p_fn,p_expected,p_old,n;end if;
 execute replace(d,p_old,p_new);
end $$;

-- Configuração financeira de eventos continua só com a regra estrita.
do $$
declare f regprocedure;
begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname in('commerce_receivers','commerce_receiving_purpose','event_checkout_review') and pg_get_functiondef(p.oid) like '%private.event_manager(%'
 loop perform pg_temp.patch(f,'private.event_manager(','private.event_manager_strict(',null);end loop;
end $$;

-- Agenda: concessão de agenda edita; concessão de entrada lê a lista, os inscritos e faz check-in.
select pg_temp.patch('private.member_agenda_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,
 'not private.has_organization_role(p_org,array[''owner'',''admin'',''pastor'']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array[''manage'',''admin'']::public.unit_access_level[])',
 'not (private.event_manager(p_org,p_unit) or p_action in(''list'',''attendees'',''checkin'') and private.checkin_operator(p_org,p_unit))');
select pg_temp.patch('private.programming_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,
 'begin
 perform private.community_identity(p_org,p_unit,false);
',
 'begin
 perform private.community_identity(p_org,p_unit,false);
 -- Quem só faz a entrada lê a agenda e confirma presença; criar e editar exige a gestão da agenda.
 if p_action not in(''list'',''calendar'',''detail'',''attendees'',''categories'',''checkin'') and not private.event_manager(p_org,p_unit) then raise exception ''member_agenda_denied'' using errcode=''42501'';end if;
');
select pg_temp.patch('private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,
 'if not private.event_manager(p_org,p_unit) then raise exception ''event_ticket_denied''',
 'if not (private.event_manager(p_org,p_unit) or p_action=''checkin'' and private.checkin_operator(p_org,p_unit)) then raise exception ''event_ticket_denied''');

-- Push e métricas usam as regras próprias.
select pg_temp.patch('private.push_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,'private.publisher_unit(','private.push_unit(',null);
select pg_temp.patch('private.push_engine(text,jsonb)'::regprocedure,'private.publisher_unit(','private.push_unit(',null);
select pg_temp.patch('public.push_automation(uuid,uuid,text,integer,jsonb)'::regprocedure,'private.publisher_unit(','private.push_unit(',null);
select pg_temp.patch('public.communication_metrics(uuid,uuid,integer)'::regprocedure,'private.publisher_unit(','private.communication_viewer(',null);

-- Horários interpretados no fuso da unidade.
select pg_temp.patch('private.member_agenda_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',2);
select pg_temp.patch('private.programming_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',1);
select pg_temp.patch('private.programming_admin_base_20261103(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',7);
select pg_temp.patch('private.event_insights(uuid,uuid,uuid,text,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',2);
select pg_temp.patch('private.commerce_event_save(uuid,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(e.unit_id)',1);
select pg_temp.patch('private.push_audience(uuid,uuid[],jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(d.unit_id)',1);

-- Aniversários: o dia é o do fuso da sede de cada ministério.
create or replace function private.push_birthdays() returns integer language plpgsql security definer set search_path='' as $$
declare made integer;
begin
 insert into private.push_campaigns(organization_id,owner_unit,title,body,link,audience,targets,source,source_key,status,send_at,next_run_at)
 select a.organization_id,hq.id,a.birthday_title,a.birthday_body,'{"screen":"inbox"}','{"birthdayToday":true}',units.ids,'birthday',
  'birthday:'||to_char((now() at time zone private.unit_timezone(hq.id))::date,'YYYY-MM-DD'),'scheduled',clock_timestamp(),clock_timestamp()
 from private.push_automations a
 join public.organizations o on o.id=a.organization_id and o.status in('active','trial')
 cross join lateral(select array_agg(u.id order by u.id) ids from public.organization_units u where u.organization_id=a.organization_id and u.status='active') units
 cross join lateral(select u.id from public.organization_units u where u.organization_id=a.organization_id and u.status='active' order by (u.parent_unit_id is null) desc,u.created_at limit 1) hq
 where a.birthdays and cardinality(units.ids) between 1 and 200
 on conflict(organization_id,source,source_key) do nothing;
 get diagnostics made=row_count;
 return made;
end $$;
revoke all on function private.push_birthdays() from public,anon,authenticated,service_role;

-- ── Painel e apps: o que cada pessoa pode fazer, concessões e fuso ───────────
create function private.staff_units_of(p_org uuid,p_user uuid) returns table(unit_id uuid) language sql stable security definer set search_path='' as $$
 with recursive m as(select id,role from public.organization_memberships where organization_id=p_org and user_id=p_user and status='active'),
 tree as(select a.unit_id,a.include_children from public.membership_unit_access a join m on m.id=a.membership_id
  union select c.id,true from public.organization_units c join tree t on c.parent_unit_id=t.unit_id and t.include_children)
 -- Mesmo critério de private.can_access_unit, para outra pessoa: acesso direto à unidade ou a uma ancestral que inclui as filhas.
 select u.id from public.organization_units u where u.organization_id=p_org and u.status='active'
  and (exists(select 1 from m where m.role in('owner','admin','pastor')) or u.id in(select unit_id from tree));
$$;
revoke all on function private.staff_units_of(uuid,uuid) from public,anon,authenticated,service_role;

create function private.staff_access(p_org uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();target public.organization_memberships;scopes text[];tz text;unit uuid;
begin
 if actor is null or not exists(select 1 from public.organization_memberships where organization_id=p_org and user_id=actor and status='active')
  or not exists(select 1 from public.organizations where id=p_org and status in('active','trial')) then raise exception 'staff_access_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_staff_access' using errcode='22023';end if;
 if p_action='mine' then
  return jsonb_build_object('units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'timezone',private.unit_timezone(u.id),
    'agenda',private.event_manager(p_org,u.id),'checkin',private.checkin_operator(p_org,u.id),'publishing',private.publisher_unit(p_org,u.id,''),'push',private.push_unit(p_org,u.id)) order by u.name)
   from public.organization_units u where u.organization_id=p_org and u.status='active' and private.can_access_unit(p_org,u.id,array['read','manage','admin']::public.unit_access_level[])),'[]'));
 end if;
 if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'staff_access_denied' using errcode='42501';end if;
 if p_action='grant' then
  if p_data-array['user','unit','scopes']<>'{}'::jsonb or coalesce(p_data->>'user','') !~ '^[0-9a-f-]{36}$' or coalesce(p_data->>'unit','') !~ '^[0-9a-f-]{36}$'
   or jsonb_typeof(p_data->'scopes')<>'array' or exists(select 1 from jsonb_array_elements(p_data->'scopes') s where jsonb_typeof(s)<>'string' or s#>>'{}' not in('agenda','checkin','publishing','push')) then raise exception 'invalid_staff_access' using errcode='22023';end if;
  perform 1 from public.organizations where id=p_org for no key update;
  select * into target from public.organization_memberships where organization_id=p_org and user_id=(p_data->>'user')::uuid and status='active' for share;
  unit:=(p_data->>'unit')::uuid;
  if not found or target.role not in('secretary','leader') then raise exception 'staff_access_role' using errcode='22023';end if;
  if unit not in(select unit_id from private.staff_units_of(p_org,target.user_id)) then raise exception 'staff_access_unit' using errcode='22023';end if;
  select coalesce(array_agg(distinct s order by s),'{}') into scopes from jsonb_array_elements_text(p_data->'scopes') s;
  delete from private.staff_grants g where g.organization_id=p_org and g.user_id=target.user_id and g.unit_id=unit and g.scope<>all(scopes);
  insert into private.staff_grants(organization_id,user_id,unit_id,scope,granted_by) select p_org,target.user_id,unit,s,actor from unnest(scopes) s on conflict do nothing;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'staff.grants.set','organization_membership',target.id::text,jsonb_build_object('unit',unit,'scopes',to_jsonb(scopes)));
 elsif p_action='timezone' then
  if p_data-array['unit','timezone']<>'{}'::jsonb or nullif(p_data->>'unit','') is not null and p_data->>'unit' !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_staff_access' using errcode='22023';end if;
  unit:=nullif(p_data->>'unit','')::uuid;tz:=nullif(p_data->>'timezone','');
  if unit is not null and not exists(select 1 from public.organization_units where id=unit and organization_id=p_org and status='active') then raise exception 'staff_access_unit' using errcode='22023';end if;
  if tz is not null and not private.timezone_valid(tz) then raise exception 'invalid_timezone' using errcode='22023';end if;
  perform 1 from public.organizations where id=p_org for no key update;
  delete from private.church_timezones where organization_id=p_org and unit_id is not distinct from unit;
  if tz is not null then insert into private.church_timezones(organization_id,unit_id,timezone,updated_by) values(p_org,unit,tz,actor);end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'church.timezone.set','organization_unit',coalesce(unit::text,p_org::text),jsonb_build_object('timezone',tz));
 elsif p_action<>'list' then raise exception 'invalid_staff_access' using errcode='22023';
 end if;
 return jsonb_build_object('ok',true,
  'timezone',coalesce((select timezone from private.church_timezones where organization_id=p_org and unit_id is null),'America/Sao_Paulo'),
  'units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'timezone',private.unit_timezone(u.id),'ownTimezone',(select timezone from private.church_timezones t where t.unit_id=u.id),'autonomy',u.communication_autonomy) order by (u.parent_unit_id is null) desc,u.name)
   from public.organization_units u where u.organization_id=p_org and u.status='active'),'[]'),
  'team',coalesce((select jsonb_agg(jsonb_build_object('user',m.user_id,'role',m.role,
    'name',coalesce((select p.full_name from public.people p where p.organization_id=p_org and p.auth_user_id=m.user_id order by (p.status='active') desc limit 1),nullif(au.raw_user_meta_data->>'full_name',''),split_part(au.email,'@',1)),
    'email',au.email,
    'units',coalesce((select jsonb_agg(x.unit_id) from private.staff_units_of(p_org,m.user_id) x),'[]'),
    'grants',coalesce((select jsonb_object_agg(g.unit_id::text,g.s) from(select unit_id,jsonb_agg(scope order by scope) s from private.staff_grants where organization_id=p_org and user_id=m.user_id group by unit_id) g),'{}')) order by au.email)
   from public.organization_memberships m join auth.users au on au.id=m.user_id
   where m.organization_id=p_org and m.status='active' and m.role in('secretary','leader')),'[]'));
end $$;
revoke all on function private.staff_access(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.staff_access(p_org uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.staff_access(p_org,p_action,p_data)$$;
revoke all on function public.staff_access(uuid,text,jsonb) from public,anon;
grant execute on function public.staff_access(uuid,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
