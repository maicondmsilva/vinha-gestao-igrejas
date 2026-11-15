-- Kids · melhorias da escala e das repetições:
--  1. Disponibilidade: cada voluntário marca no app os dias em que não pode servir; a escala automática pula.
--  2. Revezamento: equipe A/B/C… por repetição (rotation_groups); quem não tem letra serve sempre.
--  3. Aviso na véspera para quem serve, com "Confirmo" ou "Não posso".
--  4. Lembretes às famílias: reservas abertas e "hoje tem Kids" para quem reservou.
--  5. Abertura automática no horário quando cada sala tem a equipe mínima.
--  6. Relatório por repetição: crianças, equipe e ocupação das últimas sessões.

alter table private.kids_team add column if not exists rotation smallint check(rotation between 1 and 6);
alter table private.kids_session_series add column if not exists rotation_groups smallint not null default 1 check(rotation_groups between 1 and 6);
alter table private.kids_session_series add column if not exists auto_open boolean not null default false;
alter table private.kids_assignments add column if not exists confirmed_at timestamptz;
alter table private.kids_assignments add column if not exists declined_at timestamptz;

create table if not exists private.kids_team_unavailable(
 team_id uuid not null references private.kids_team(id) on delete cascade,
 day date not null,
 reason text not null default '' check(length(reason)<=120),
 created_at timestamptz not null default now(),
 primary key(team_id,day)
);
alter table private.kids_team_unavailable enable row level security;
revoke all on private.kids_team_unavailable from public,anon,authenticated;

-- Quantas vezes a repetição já aconteceu antes da data (para saber qual equipe do revezamento serve).
create or replace function private.kids_series_index(s private.kids_session_series, d date) returns integer
language sql stable set search_path to '' as $$
 select count(*)::int from generate_series(s.valid_from,d-1,interval '1 day') g where private.kids_series_matches(s,g::date)
$$;
revoke all on function private.kids_series_index(private.kids_session_series,date) from public,anon,authenticated;

create or replace function private.kids_series_run(p_series uuid default null) returns integer
language plpgsql security definer set search_path to '' as $function$
declare s private.kids_session_series; d date; tz text; st timestamptz; sid uuid; rm jsonb; gid uuid; t private.kids_team; made integer:=0; room_row private.kids_rooms; class_row private.kids_classes; turn integer;
begin
 for s in select * from private.kids_session_series where active and (p_series is null or id=p_series) loop
  tz:=private.unit_timezone(s.unit_id);
  for d in select g::date from generate_series((now() at time zone tz)::date,(now() at time zone tz)::date+ceil(s.open_before_hours/24.0)::int+1,interval '1 day') g loop
   continue when not private.kids_series_matches(s,d);
   st:=(d+s.starts_time) at time zone tz;
   continue when st<=now() or now()<st-make_interval(hours=>s.open_before_hours);
   sid:=md5('kids-series:'||s.id::text||':'||d::text)::uuid;
   continue when exists(select 1 from private.kids_sessions where id=sid);
   insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,created_by,series_id,bookable_from)
    values(sid,s.organization_id,s.unit_id,s.name,st,st+make_interval(mins=>s.duration_minutes),s.created_by,s.id,st-make_interval(hours=>s.open_before_hours));
   made:=made+1;
   for rm in select value from jsonb_array_elements(s.rooms) loop
    select * into room_row from private.kids_rooms where id=nullif(rm->>'roomId','')::uuid and unit_id=s.unit_id and active;
    select * into class_row from private.kids_classes where id=nullif(rm->>'classId','')::uuid and unit_id=s.unit_id and active;
    continue when room_row.id is null or class_row.id is null;
    gid:=md5('kids-series-room:'||sid::text||':'||room_row.id::text||':'||class_row.id::text)::uuid;
    insert into private.kids_session_rooms(id,organization_id,unit_id,session_id,room_id,class_id,capacity,min_staff)
     values(gid,s.organization_id,s.unit_id,sid,room_row.id,class_row.id,least(room_row.capacity,greatest(1,coalesce((rm->>'capacity')::int,room_row.capacity))),greatest(0,coalesce((rm->>'minStaff')::int,1)))
     on conflict do nothing;
   end loop;
   if s.auto_team then
    turn:=case when s.rotation_groups>1 then (private.kids_series_index(s,d) % s.rotation_groups)+1 end;
    for t in select * from private.kids_team where unit_id=s.unit_id and active loop
     -- Revezamento: quem tem letra só serve na vez dela; sem letra, serve sempre.
     continue when turn is not null and t.rotation is not null and t.rotation<>turn;
     -- Indisponível nesta data.
     continue when exists(select 1 from private.kids_team_unavailable u where u.team_id=t.id and u.day=d);
     continue when exists(select 1 from private.kids_assignments x join private.kids_sessions y on y.id=x.session_id where x.member_id=t.member_id and x.active and y.status in('draft','open') and y.starts_at<st+make_interval(mins=>s.duration_minutes) and y.ends_at>st);
     if t.role in('supervisor','reception') then gid:=null;
     else select sr.id into gid from private.kids_session_rooms sr where sr.session_id=sid and (t.class_id is null or sr.class_id=t.class_id) order by (sr.class_id=t.class_id) desc nulls last limit 1;
      continue when gid is null;
     end if;
     insert into private.kids_assignments(id,organization_id,unit_id,session_id,group_id,person_id,member_id,role,can_care,active)
      values(md5('kids-series-staff:'||sid::text||':'||t.member_id::text)::uuid,s.organization_id,s.unit_id,sid,gid,t.person_id,t.member_id,t.role,t.can_care,true) on conflict do nothing;
    end loop;
   end if;
  end loop;
 end loop;
 return made;
end $function$;
revoke all on function private.kids_series_run(uuid) from public,anon,authenticated;

-- Abre sozinha (até 30 min antes) as sessões das repetições com abertura automática, se cada sala tem a equipe mínima
-- e a sala não está em outra sessão aberta no mesmo horário.
create or replace function private.kids_series_autoopen() returns integer
language plpgsql security definer set search_path to '' as $function$
declare s private.kids_sessions; opened integer:=0;
begin
 for s in select k.* from private.kids_sessions k join private.kids_session_series x on x.id=k.series_id
  where k.status='draft' and x.auto_open and k.starts_at<=now()+interval '30 minutes' and k.ends_at>now() for update of k skip locked loop
  continue when not exists(select 1 from private.kids_session_rooms where session_id=s.id);
  continue when exists(select 1 from private.kids_session_rooms g join private.kids_rooms r on r.id=g.room_id join private.kids_classes c on c.id=g.class_id
   where g.session_id=s.id and (not r.active or not c.active or g.capacity>r.capacity or private.kids_op_staff_count(s.organization_id,s.unit_id,s.id,g.id)<g.min_staff));
  continue when exists(select 1 from private.kids_session_rooms x join private.kids_session_rooms y on y.room_id=x.room_id and y.session_id<>s.id join private.kids_sessions o on o.id=y.session_id
   where x.session_id=s.id and o.status='open' and o.starts_at<s.ends_at and o.ends_at>s.starts_at);
  update private.kids_sessions set status='open',version=version+1 where id=s.id;
  opened:=opened+1;
 end loop;
 return opened;
end $function$;
revoke all on function private.kids_series_autoopen() from public,anon,authenticated;

do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.unschedule(jobid) from cron.job where jobname='kids-series-run';
  perform cron.schedule('kids-series-run','*/15 * * * *','select private.kids_series_run(); select private.kids_series_autoopen()');
 end if;
end $$;

-- Configuração: revezamento, abertura automática e relatório.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_setup(uuid,uuid,text,jsonb)'::regprocedure);
 if position('''rotation'',k.rotation' in d)=0 then
  d:=replace(d,'''canCare'',k.can_care,''active'',k.active,''version'',k.version) order by p.full_name)','''canCare'',k.can_care,''active'',k.active,''version'',k.version,''rotation'',k.rotation,
   ''unavailable'',coalesce((select jsonb_agg(u.day order by u.day) from private.kids_team_unavailable u where u.team_id=k.id and u.day>=current_date),''[]''::jsonb)) order by p.full_name)');
  d:=replace(d,'''autoTeam'',x.auto_team,''active'',x.active,''version'',x.version,','''autoTeam'',x.auto_team,''active'',x.active,''version'',x.version,''rotationGroups'',x.rotation_groups,''autoOpen'',x.auto_open,');
  d:=replace(d,'update private.kids_team set role=p_data->>''role'',class_id=nullif(p_data->>''classId'','''')::uuid,can_care=(p_data->>''canCare'')::boolean,active=(p_data->>''active'')::boolean,version=version+1 where id=t.id returning version into v;',
   'update private.kids_team set role=p_data->>''role'',class_id=nullif(p_data->>''classId'','''')::uuid,can_care=(p_data->>''canCare'')::boolean,active=(p_data->>''active'')::boolean,
    rotation=case when p_data ? ''rotation'' then nullif(p_data->>''rotation'','''')::smallint else rotation end,version=version+1 where id=t.id returning version into v;');
  if position('''rotation'',k.rotation' in d)=0 or position('''rotationGroups'',x.rotation_groups' in d)=0 or position('rotation=case when p_data ? ''rotation''' in d)=0 then raise exception 'kids_setup: trechos não encontrados';end if;
  d:=replace(d,' elsif p_action=''series_delete'' then',' elsif p_action=''series_options'' then
  update private.kids_session_series set rotation_groups=least(6,greatest(1,coalesce(nullif(p_data->>''rotationGroups'','''')::int,rotation_groups))),auto_open=coalesce((p_data->>''autoOpen'')::boolean,auto_open),version=version+1
   where id=nullif(p_data->>''id'','''')::uuid and unit_id=p_unit;
  return jsonb_build_object(''ok'',true);
 elsif p_action=''report'' then
  return jsonb_build_object(''items'',coalesce((select jsonb_agg(jsonb_build_object(''id'',s.id,''series'',x.name,''startsAt'',s.starts_at,''status'',s.status,
    ''children'',(select count(*) from private.kids_attendance a where a.session_id=s.id),
    ''reserved'',(select count(*) from private.kids_member_reservations r where r.session_id=s.id and r.status in(''reserved'',''checked_in'')),
    ''capacity'',(select coalesce(sum(g.capacity),0) from private.kids_session_rooms g where g.session_id=s.id),
    ''staff'',(select count(*) from private.kids_assignments a where a.session_id=s.id and a.active),
    ''confirmed'',(select count(*) from private.kids_assignments a where a.session_id=s.id and a.active and a.confirmed_at is not null)) order by s.starts_at desc)
   from (select * from private.kids_sessions where unit_id=p_unit and series_id is not null and starts_at>now()-interval ''90 days'' and starts_at<now()+interval ''14 days'' order by starts_at desc limit 40) s
   join private.kids_session_series x on x.id=s.series_id),''[]''::jsonb));
 elsif p_action=''series_delete'' then');
  execute d;
 end if;
end $$;

-- Voluntário: minhas escalas do Kids, confirmar ou recusar, e dias em que não posso servir.
create or replace function private.kids_volunteer(p_org uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); a private.kids_assignments; t private.kids_team; d date;
begin
 if uid is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'kids_invalid' using errcode='22023';end if;
 if p_action='mine' then
  return jsonb_build_object(
   'team',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'unit',u.name,'role',k.role,'className',coalesce(c.name,''),
     'unavailable',coalesce((select jsonb_agg(x.day order by x.day) from private.kids_team_unavailable x where x.team_id=k.id and x.day>=current_date),'[]'::jsonb)))
    from private.kids_team k join public.organization_memberships m on m.id=k.member_id join public.organization_units u on u.id=k.unit_id left join private.kids_classes c on c.id=k.class_id
    where k.organization_id=p_org and m.user_id=uid and k.active),'[]'::jsonb),
   'upcoming',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'session',s.name,'startsAt',s.starts_at,'endsAt',s.ends_at,'role',x.role,'room',coalesce(r.name,''),'unit',u.name,
     'confirmed',x.confirmed_at is not null,'declined',x.declined_at is not null) order by s.starts_at)
    from private.kids_assignments x join private.kids_sessions s on s.id=x.session_id join public.organization_memberships m on m.id=x.member_id join public.organization_units u on u.id=s.unit_id
     left join private.kids_session_rooms g on g.id=x.group_id left join private.kids_rooms r on r.id=g.room_id
    where x.organization_id=p_org and m.user_id=uid and s.status in('draft','open') and s.ends_at>now() and s.starts_at<now()+interval '30 days' and (x.active or x.declined_at is not null)),'[]'::jsonb));
 elsif p_action in('confirm','decline') then
  select x.* into a from private.kids_assignments x join public.organization_memberships m on m.id=x.member_id join private.kids_sessions s on s.id=x.session_id
   where x.id=nullif(p_data->>'id','')::uuid and x.organization_id=p_org and m.user_id=uid and s.status in('draft','open') and s.ends_at>now() for update of x;
  if a.id is null then raise exception 'kids_access_denied' using errcode='42501';end if;
  if p_action='confirm' then update private.kids_assignments set confirmed_at=clock_timestamp(),declined_at=null,active=true,version=version+1 where id=a.id;
  else update private.kids_assignments set declined_at=clock_timestamp(),confirmed_at=null,active=false,version=version+1 where id=a.id;end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,'kids.assignment_'||p_action,'kids_assignment',a.id::text,jsonb_build_object('session',a.session_id));
  return jsonb_build_object('ok',true);
 elsif p_action in('unavailable','available') then
  if coalesce(p_data->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'kids_invalid' using errcode='22023';end if;
  d:=(p_data->>'date')::date;
  if d<current_date or d>current_date+400 then raise exception 'kids_invalid' using errcode='22023';end if;
  select k.* into t from private.kids_team k join public.organization_memberships m on m.id=k.member_id where k.id=nullif(p_data->>'team','')::uuid and k.organization_id=p_org and m.user_id=uid;
  if t.id is null then raise exception 'kids_access_denied' using errcode='42501';end if;
  if p_action='unavailable' then insert into private.kids_team_unavailable(team_id,day,reason) values(t.id,d,left(btrim(coalesce(p_data->>'reason','')),120)) on conflict(team_id,day) do update set reason=excluded.reason;
  else delete from private.kids_team_unavailable where team_id=t.id and day=d;end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'kids_invalid' using errcode='22023';
end $function$;
revoke all on function private.kids_volunteer(uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.kids_volunteer(p_org uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.kids_volunteer(p_org,p_action,p_data) $$;
revoke all on function public.kids_volunteer(uuid,text,jsonb) from public,anon;
grant execute on function public.kids_volunteer(uuid,text,jsonb) to authenticated;

-- Caixa de notificações: véspera para quem serve, reservas abertas e "hoje tem Kids" para as famílias.
do $$ begin
 if to_regprocedure('private.member_inbox_before_kids_reminders(uuid,uuid)') is null then
  alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_kids_reminders;
 end if;
end $$;
create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from private.member_inbox_before_kids_reminders(p_org,p_unit)
  union all
  -- Quem serve: a partir de 36 h antes.
  select 'kids-serve:'||x.id::text,
   case when (s.starts_at at time zone private.unit_timezone(s.unit_id))::date=(now() at time zone private.unit_timezone(s.unit_id))::date then 'Você serve hoje no Kids' else 'Você serve no Kids em breve' end,
   s.name||' · '||to_char(s.starts_at at time zone private.unit_timezone(s.unit_id),'DD/MM HH24:MI')||coalesce(' · '||r.name,'')||case when x.confirmed_at is null then '. Toque para confirmar.' else '. Presença confirmada.' end,
   greatest(s.starts_at-interval '36 hours',s.created_at),'kidsTeam'::text,x.id
  from private.kids_assignments x join private.kids_sessions s on s.id=x.session_id join public.organization_memberships m on m.id=x.member_id
   left join private.kids_session_rooms g on g.id=x.group_id left join private.kids_rooms r on r.id=g.room_id
  where x.organization_id=p_org and m.user_id=auth.uid() and x.active and s.status in('draft','open') and s.starts_at>now() and s.starts_at<now()+interval '36 hours'
  union all
  -- Famílias com criança no Kids desta igreja: reservas abertas.
  select 'kids-open:'||s.id::text,'Reservas abertas no Kids',
   s.name||' · '||to_char(s.starts_at at time zone private.unit_timezone(s.unit_id),'DD/MM HH24:MI')||'. Reserve a vaga da sua criança pelo app.',
   coalesce(s.bookable_from,s.created_at),'kids'::text,s.id
  from private.kids_sessions s
  where s.organization_id=p_org and s.unit_id=p_unit and s.series_id is not null and s.starts_at>now() and s.status in('draft','open') and coalesce(s.bookable_from,now())<=now()
   and exists(select 1 from private.kids_guardians kg join public.people gp on gp.id=kg.person_id join private.kids_profiles kp on kp.id=kg.profile_id
    where gp.auth_user_id=auth.uid() and kg.status='approved' and kp.organization_id=p_org and kp.unit_id=p_unit)
  union all
  -- Quem reservou: no dia.
  select 'kids-today:'||r.id::text,'Hoje tem Kids',
   split_part(c.full_name,' ',1)||' tem vaga reservada em '||s.name||' às '||to_char(s.starts_at at time zone private.unit_timezone(s.unit_id),'HH24:MI')||coalesce(' · '||rm.name,'')||'.',
   date_trunc('day',now() at time zone private.unit_timezone(s.unit_id)) at time zone private.unit_timezone(s.unit_id),'kids'::text,r.id
  from private.kids_member_reservations r join private.kids_sessions s on s.id=r.session_id join private.kids_profiles kp on kp.id=r.profile_id join public.people c on c.id=kp.person_id
   left join private.kids_session_rooms g on g.id=r.group_id left join private.kids_rooms rm on rm.id=g.room_id
  where r.organization_id=p_org and r.user_id=auth.uid() and r.status='reserved' and s.ends_at>now()
   and (s.starts_at at time zone private.unit_timezone(s.unit_id))::date=(now() at time zone private.unit_timezone(s.unit_id))::date
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;
