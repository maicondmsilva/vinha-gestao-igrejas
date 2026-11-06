begin;
set local lock_timeout='5s';
-- Etapa 3 · PR 3: Kids pronto para o modo estação do Vinha Equipe e no fuso de cada igreja.
-- Estação = tablet ou celular da recepção registrado pela coordenação; desativar encerra o login daquele aparelho.

create function pg_temp.patch(p_fn regprocedure,p_old text,p_new text,p_expected integer default 1) returns void language plpgsql as $$
declare d text:=pg_get_functiondef(p_fn);n integer:=(length(d)-length(replace(d,p_old,'')))/greatest(length(p_old),1);
begin
 if n<>coalesce(p_expected,greatest(n,1)) then raise exception 'patch %: esperado % ocorrência(s) de [%], encontrado %',p_fn,p_expected,p_old,n;end if;
 execute replace(d,p_old,p_new);
end $$;

-- ── Fuso da igreja nas operações Kids ───────────────────────────────────────
select pg_temp.patch('private.kids_desk(uuid,uuid,uuid,text,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',8);
select pg_temp.patch('private.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',4);
select pg_temp.patch('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',1);
select pg_temp.patch('private.kids_op_guardian(uuid,uuid,uuid,uuid)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',1);
select pg_temp.patch('private.kids_admission_choices(uuid,uuid,uuid,text)'::regprocedure,'''America/Sao_Paulo''','private.unit_timezone(p_unit)',1);

-- ── Sessão encerrada não opera Kids ─────────────────────────────────────────
-- Tokens de acesso duram até uma hora; quando a sessão é apagada (estação desativada, saída em todos os aparelhos),
-- o Kids recusa na hora. Chamadas sem session_id (servidor) seguem as demais regras.
create function private.session_alive() returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(auth.jwt()->>'session_id','')='' or exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()));
$$;
revoke all on function private.session_alive() from public,anon,authenticated,service_role;
select pg_temp.patch('private.kids_op_allowed(uuid,uuid,uuid,text,uuid)'::regprocedure,' select auth.uid() is not null',' select auth.uid() is not null and private.session_alive()');
select pg_temp.patch('private.kids_allowed(uuid,uuid,text)'::regprocedure,' select auth.uid() is not null',' select auth.uid() is not null and private.session_alive()');

-- ── Estações ────────────────────────────────────────────────────────────────
create table private.kids_stations(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 60),
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null,
 platform text not null check(platform in('android','ios','web','other')),
 created_at timestamptz not null default clock_timestamp(),
 last_seen_at timestamptz not null default clock_timestamp(),
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id)
);
create index kids_stations_unit on private.kids_stations(organization_id,unit_id,revoked_at);
create index kids_stations_user on private.kids_stations(user_id);
create index kids_stations_revoked_by on private.kids_stations(revoked_by);
create unique index kids_stations_session on private.kids_stations(session_id) where revoked_at is null;
alter table private.kids_stations enable row level security;
revoke all on private.kids_stations from public,anon,authenticated,service_role;

-- Quem coordena o Kids da igreja ou supervisiona uma sessão aberta ou em preparação.
create function private.kids_station_manager(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.kids_op_allowed(p_org,p_unit,null,'configure') or exists(select 1 from private.kids_sessions s where s.organization_id=p_org and s.unit_id=p_unit and s.status in('draft','open') and private.kids_op_allowed(p_org,p_unit,s.id,'supervise'));
$$;
revoke all on function private.kids_station_manager(uuid,uuid) from public,anon,authenticated,service_role;
-- Quem pode usar o Kids da igreja (coordenação, leitura administrativa ou equipe escalada).
create function private.kids_any(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.kids_op_allowed(p_org,p_unit,null,'configure') or private.kids_allowed(p_org,p_unit,'read') or exists(select 1 from private.kids_sessions s where s.organization_id=p_org and s.unit_id=p_unit and s.status in('draft','open') and private.kids_op_allowed(p_org,p_unit,s.id));
$$;
revoke all on function private.kids_any(uuid,uuid) from public,anon,authenticated,service_role;

create function private.kids_station(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();sid uuid;st private.kids_stations;
begin
 if actor is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'kids_station_denied' using errcode='42501';end if;
 sid:=nullif(auth.jwt()->>'session_id','')::uuid;
 if p_action='register' then
  if p_data-array['name','platform']<>'{}'::jsonb or length(btrim(coalesce(p_data->>'name',''))) not between 2 and 60 or coalesce(p_data->>'platform','') not in('android','ios','web','other') then raise exception 'invalid_kids_station' using errcode='22023';end if;
  if sid is null or not private.kids_station_manager(p_org,p_unit) then raise exception 'kids_station_denied' using errcode='42501';end if;
  perform 1 from public.organization_units where id=p_unit and organization_id=p_org for no key update;
  if (select count(*) from private.kids_stations where organization_id=p_org and unit_id=p_unit and revoked_at is null)>=50 then raise exception 'kids_station_limit' using errcode='22023';end if;
  -- Re-registering from the same login replaces the old record (renamed tablet, reinstalled app).
  update private.kids_stations set revoked_at=clock_timestamp(),revoked_by=actor where session_id=sid and revoked_at is null;
  insert into private.kids_stations(organization_id,unit_id,name,user_id,session_id,platform) values(p_org,p_unit,btrim(p_data->>'name'),actor,sid,p_data->>'platform') returning * into st;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'kids.station.registered','kids_station',st.id::text,jsonb_build_object('unit',p_unit,'name',st.name,'platform',st.platform));
  return jsonb_build_object('ok',true,'id',st.id,'name',st.name,'unit',st.unit_id);
 elsif p_action='heartbeat' then
  select * into st from private.kids_stations where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found or st.user_id<>actor or st.session_id is distinct from sid then raise exception 'kids_station_denied' using errcode='42501';end if;
  if st.revoked_at is not null then raise exception 'kids_station_revoked' using errcode='42501';end if;
  if not private.kids_any(p_org,p_unit) then raise exception 'kids_station_denied' using errcode='42501';end if;
  update private.kids_stations set last_seen_at=clock_timestamp() where id=st.id;
  return jsonb_build_object('ok',true,'id',st.id,'name',st.name,'active',true);
 end if;
 if not private.kids_station_manager(p_org,p_unit) then raise exception 'kids_station_denied' using errcode='42501';end if;
 if p_action='revoke' then
  select * into st from private.kids_stations where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_station_denied' using errcode='42501';end if;
  if st.revoked_at is null then
   update private.kids_stations set revoked_at=clock_timestamp(),revoked_by=actor where id=st.id;
   -- Ends that device's login: refresh tokens go with the session and Kids refuses the remaining access token.
   delete from auth.sessions where id=st.session_id and user_id=st.user_id;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'kids.station.revoked','kids_station',st.id::text,jsonb_build_object('unit',p_unit,'name',st.name));
  end if;
 elsif p_action<>'list' or p_data<>'{}'::jsonb then raise exception 'invalid_kids_station' using errcode='22023';
 end if;
 return jsonb_build_object('ok',true,'timezone',private.unit_timezone(p_unit),'items',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'name',k.name,'platform',k.platform,
   'user',coalesce((select p.full_name from public.people p where p.organization_id=p_org and p.auth_user_id=k.user_id order by (p.status='active') desc limit 1),split_part(u.email,'@',1)),
   'createdAt',k.created_at,'lastSeenAt',k.last_seen_at,'revokedAt',k.revoked_at,'mine',k.session_id=sid) order by k.revoked_at is not null,k.last_seen_at desc)
  from private.kids_stations k join auth.users u on u.id=k.user_id
  where k.organization_id=p_org and k.unit_id=p_unit and (k.revoked_at is null or k.revoked_at>now()-interval '30 days')),'[]'));
end $$;
revoke all on function private.kids_station(uuid,uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
create function public.kids_station(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.kids_station(p_org,p_unit,p_action,p_id,p_data)$$;
revoke all on function public.kids_station(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.kids_station(uuid,uuid,text,uuid,jsonb) to authenticated;

-- O Vinha Equipe também sabe onde a pessoa pode usar o Kids.
select pg_temp.patch('private.staff_access(uuid,text,jsonb)'::regprocedure,
 '''push'',private.push_unit(p_org,u.id)) order by u.name)',
 '''push'',private.push_unit(p_org,u.id),''kids'',private.kids_any(p_org,u.id),''kidsStations'',private.kids_station_manager(p_org,u.id)) order by u.name)');

notify pgrst,'reload schema';
commit;
