-- Kids · equipe fixa e sessões que se repetem.
--  · Equipe fixa (private.kids_team): monta a equipe do Kids sem precisar de sessão; cada pessoa pode ter uma turma
--    preferida. Depois é distribuída nas sessões (à mão ou automaticamente pelas repetições).
--  · Repetições (private.kids_session_series): todo dia, dias da semana (ex.: todo domingo), todo mês no dia X ou
--    no n-ésimo dia da semana (ex.: 1º sábado). A sessão é criada sozinha, com as salas e a equipe, "N horas antes"
--    (padrão 24 h), e desde esse momento as famílias já podem reservar a vaga pelo app.
--  · Sessão avulsa também pode abrir para reserva antes (bookable_from).

alter table private.kids_sessions add column if not exists series_id uuid;
alter table private.kids_sessions add column if not exists bookable_from timestamptz;

create table if not exists private.kids_team(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 person_id uuid not null references public.people(id) on delete cascade,
 member_id uuid not null references public.organization_memberships(id) on delete cascade,
 role text not null check(role in('supervisor','reception','teacher','assistant')),
 class_id uuid references private.kids_classes(id) on delete set null,
 can_care boolean not null default false check(not can_care or role in('teacher','supervisor')),
 active boolean not null default true,
 version integer not null default 1,
 created_by uuid,
 created_at timestamptz not null default now(),
 unique(unit_id,person_id)
);
alter table private.kids_team enable row level security;
revoke all on private.kids_team from public,anon,authenticated;

create table if not exists private.kids_session_series(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 100),
 rule text not null check(rule in('daily','weekly','monthly_day','monthly_week')),
 weekdays smallint[] not null default '{}' check(weekdays<@array[0,1,2,3,4,5,6]::smallint[]),
 month_day smallint check(month_day between 1 and 31),
 month_week smallint check(month_week between 1 and 5),
 starts_time time not null,
 duration_minutes integer not null check(duration_minutes between 15 and 720),
 valid_from date not null,
 valid_until date,
 open_before_hours integer not null default 24 check(open_before_hours between 1 and 336),
 rooms jsonb not null default '[]' check(jsonb_typeof(rooms)='array' and jsonb_array_length(rooms)<=30),
 auto_team boolean not null default true,
 skip_dates date[] not null default '{}',
 active boolean not null default true,
 version integer not null default 1,
 created_by uuid,
 created_at timestamptz not null default now(),
 check(valid_until is null or valid_until>=valid_from),
 check(rule<>'weekly' or cardinality(weekdays) between 1 and 7),
 check(rule<>'monthly_day' or month_day is not null),
 check(rule<>'monthly_week' or (month_week is not null and cardinality(weekdays)=1))
);
alter table private.kids_session_series enable row level security;
revoke all on private.kids_session_series from public,anon,authenticated;

-- A data cai na regra da repetição?
create or replace function private.kids_series_matches(s private.kids_session_series, d date) returns boolean
language sql immutable set search_path to '' as $$
 select d>=s.valid_from and (s.valid_until is null or d<=s.valid_until) and not d=any(s.skip_dates) and case s.rule
  when 'daily' then true
  when 'weekly' then extract(dow from d)::smallint=any(s.weekdays)
  when 'monthly_day' then extract(day from d)::int=least(s.month_day,extract(day from (date_trunc('month',d)+interval '1 month - 1 day'))::int)
  when 'monthly_week' then extract(dow from d)::smallint=s.weekdays[1] and ceil(extract(day from d)/7.0)::int=s.month_week
  else false end
$$;
revoke all on function private.kids_series_matches(private.kids_session_series,date) from public,anon,authenticated;

-- Próximas datas (para a prévia na tela).
create or replace function private.kids_series_next(s private.kids_session_series, p_count integer) returns date[]
language sql stable set search_path to '' as $$
 select coalesce(array_agg(d order by d),'{}') from (
  select g::date d from generate_series(greatest(s.valid_from,(now() at time zone private.unit_timezone(s.unit_id))::date),greatest(s.valid_from,(now() at time zone private.unit_timezone(s.unit_id))::date)+400,interval '1 day') g
  where private.kids_series_matches(s,g::date) limit p_count) x
$$;
revoke all on function private.kids_series_next(private.kids_session_series,integer) from public,anon,authenticated;

-- Cria as sessões que já entraram na janela "N horas antes". Idempotente: o id da sessão vem da repetição + data.
create or replace function private.kids_series_run(p_series uuid default null) returns integer
language plpgsql security definer set search_path to '' as $function$
declare s private.kids_session_series; d date; tz text; st timestamptz; sid uuid; rm jsonb; gid uuid; t private.kids_team; made integer:=0; room_row private.kids_rooms; class_row private.kids_classes;
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
    for t in select * from private.kids_team where unit_id=s.unit_id and active loop
     -- Sem sobrepor outra escala da mesma pessoa no mesmo horário.
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

-- Configuração do Kids sem sessão ativa: equipe fixa e repetições (Vinha Equipe e painel).
create or replace function private.kids_setup(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare person public.people; member public.organization_memberships; t private.kids_team; sr private.kids_session_series; v integer; rm jsonb; wd smallint[];
begin
 if auth.uid() is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'kids_invalid' using errcode='22023';end if;
 if not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org) or not private.kids_op_allowed(p_org,p_unit,null,'configure') then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_action='overview' then
  return jsonb_build_object(
   'rooms',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'location',r.location,'capacity',r.capacity,'active',r.active,'version',r.version) order by r.name) from private.kids_rooms r where r.unit_id=p_unit),'[]'::jsonb),
   'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'minMonths',c.min_months,'maxMonths',c.max_months,'active',c.active,'version',c.version) order by c.min_months) from private.kids_classes c where c.unit_id=p_unit),'[]'::jsonb),
   'team',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'personId',k.person_id,'name',p.full_name,'role',k.role,'classId',k.class_id,'canCare',k.can_care,'active',k.active,'version',k.version) order by p.full_name) from private.kids_team k join public.people p on p.id=k.person_id where k.unit_id=p_unit),'[]'::jsonb),
   'series',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'rule',x.rule,'weekdays',to_jsonb(x.weekdays),'monthDay',x.month_day,'monthWeek',x.month_week,'startsTime',to_char(x.starts_time,'HH24:MI'),
     'durationMinutes',x.duration_minutes,'validFrom',x.valid_from,'validUntil',x.valid_until,'openBeforeHours',x.open_before_hours,'rooms',x.rooms,'autoTeam',x.auto_team,'active',x.active,'version',x.version,
     'next',to_jsonb(private.kids_series_next(x,4))) order by x.name) from private.kids_session_series x where x.unit_id=p_unit),'[]'::jsonb),
   'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'startsAt',s.starts_at,'endsAt',s.ends_at,'status',s.status,'seriesId',s.series_id,'bookableFrom',s.bookable_from,'version',s.version,
     'rooms',(select count(*) from private.kids_session_rooms g where g.session_id=s.id),'staff',(select count(*) from private.kids_assignments a where a.session_id=s.id and a.active)) order by s.starts_at)
     from private.kids_sessions s where s.unit_id=p_unit and s.ends_at>now()-interval '12 hours' and s.status in('draft','open')),'[]'::jsonb));
 elsif p_action='team_save' then
  if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or p_data->>'role' not in('supervisor','reception','teacher','assistant') or jsonb_typeof(p_data->'canCare')<>'boolean' or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'kids_invalid' using errcode='22023';end if;
  if (p_data->>'canCare')::boolean and p_data->>'role' not in('teacher','supervisor') then raise exception 'kids_invalid' using errcode='22023';end if;
  if nullif(p_data->>'classId','') is not null and not exists(select 1 from private.kids_classes where id=(p_data->>'classId')::uuid and unit_id=p_unit) then raise exception 'kids_invalid' using errcode='22023';end if;
  select * into t from private.kids_team where id=(p_data->>'id')::uuid for update;
  if t.id is not null and (t.unit_id<>p_unit) then raise exception 'kids_access_denied' using errcode='42501';end if;
  if t.id is not null and t.version<>coalesce((p_data->>'version')::int,0) then raise exception 'kids_version_conflict' using errcode='40001';end if;
  if t.id is null then
   select * into person from public.people where id=nullif(p_data->>'personId','')::uuid and organization_id=p_org and status='active' and (birth_date is null or birth_date<=current_date-interval '18 years');
   select * into member from public.organization_memberships where user_id=person.auth_user_id and organization_id=p_org and status='active';
   if person.id is null or member.id is null then raise exception 'kids_staff_identity_required' using errcode='22023';end if;
   -- Quem entra na equipe passa a alcançar a igreja (leitura).
   insert into public.membership_unit_access(membership_id,organization_id,unit_id,access_level,include_children)
    select member.id,p_org,p_unit,'read',false where not exists(select 1 from public.membership_unit_access a where a.membership_id=member.id and a.unit_id=p_unit);
   insert into private.kids_team(id,organization_id,unit_id,person_id,member_id,role,class_id,can_care,active,created_by)
    values((p_data->>'id')::uuid,p_org,p_unit,person.id,member.id,p_data->>'role',nullif(p_data->>'classId','')::uuid,(p_data->>'canCare')::boolean,(p_data->>'active')::boolean,auth.uid())
    on conflict(unit_id,person_id) do update set role=excluded.role,class_id=excluded.class_id,can_care=excluded.can_care,active=true,version=private.kids_team.version+1 returning version into v;
  else
   update private.kids_team set role=p_data->>'role',class_id=nullif(p_data->>'classId','')::uuid,can_care=(p_data->>'canCare')::boolean,active=(p_data->>'active')::boolean,version=version+1 where id=t.id returning version into v;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'kids.team_saved','kids_team',(p_data->>'id'),jsonb_build_object('unit_id',p_unit,'role',p_data->>'role'));
  return jsonb_build_object('ok',true,'version',v);
 elsif p_action='people' then
  -- Adultos com conta ativa no ministério, para montar a equipe.
  if length(btrim(coalesce(p_data->>'q',''))) not between 2 and 80 then return jsonb_build_object('items','[]'::jsonb);end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.full_name)) from (
   select p.id,p.full_name from public.people p join public.organization_memberships m on m.user_id=p.auth_user_id and m.organization_id=p.organization_id and m.status='active'
   where p.organization_id=p_org and p.status='active' and (p.birth_date is null or p.birth_date<=current_date-interval '18 years')
    and p.full_name ilike '%'||replace(replace(btrim(p_data->>'q'),'%',''),'_','')||'%' order by p.full_name limit 20) x),'[]'::jsonb));
 elsif p_action='team_remove' then
  delete from private.kids_team where id=nullif(p_data->>'id','')::uuid and unit_id=p_unit;
  return jsonb_build_object('ok',true);
 elsif p_action='series_save' then
  if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or length(btrim(coalesce(p_data->>'name',''))) not between 2 and 100 or p_data->>'rule' not in('daily','weekly','monthly_day','monthly_week')
   or coalesce(p_data->>'startsTime','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or coalesce(p_data->>'validFrom','') !~ '^\d{4}-\d{2}-\d{2}$' or jsonb_typeof(p_data->'rooms')<>'array'
   or jsonb_typeof(p_data->'weekdays')<>'array' or jsonb_typeof(p_data->'autoTeam')<>'boolean' or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'kids_invalid' using errcode='22023';end if;
  for rm in select value from jsonb_array_elements(p_data->'rooms') loop
   if not exists(select 1 from private.kids_rooms where id=nullif(rm->>'roomId','')::uuid and unit_id=p_unit) or not exists(select 1 from private.kids_classes where id=nullif(rm->>'classId','')::uuid and unit_id=p_unit) then raise exception 'kids_invalid' using errcode='22023';end if;
  end loop;
  select coalesce(array_agg(distinct x::smallint),'{}') into wd from jsonb_array_elements_text(p_data->'weekdays') x;
  select * into sr from private.kids_session_series where id=(p_data->>'id')::uuid for update;
  if sr.id is not null and sr.unit_id<>p_unit then raise exception 'kids_access_denied' using errcode='42501';end if;
  if sr.id is not null and sr.version<>coalesce((p_data->>'version')::int,0) then raise exception 'kids_version_conflict' using errcode='40001';end if;
  begin
   insert into private.kids_session_series(id,organization_id,unit_id,name,rule,weekdays,month_day,month_week,starts_time,duration_minutes,valid_from,valid_until,open_before_hours,rooms,auto_team,active,created_by)
   values((p_data->>'id')::uuid,p_org,p_unit,btrim(p_data->>'name'),p_data->>'rule',wd,nullif(p_data->>'monthDay','')::smallint,nullif(p_data->>'monthWeek','')::smallint,(p_data->>'startsTime')::time,
    (p_data->>'durationMinutes')::int,(p_data->>'validFrom')::date,nullif(p_data->>'validUntil','')::date,coalesce(nullif(p_data->>'openBeforeHours','')::int,24),p_data->'rooms',(p_data->>'autoTeam')::boolean,(p_data->>'active')::boolean,auth.uid())
   on conflict(id) do update set name=excluded.name,rule=excluded.rule,weekdays=excluded.weekdays,month_day=excluded.month_day,month_week=excluded.month_week,starts_time=excluded.starts_time,duration_minutes=excluded.duration_minutes,
    valid_from=excluded.valid_from,valid_until=excluded.valid_until,open_before_hours=excluded.open_before_hours,rooms=excluded.rooms,auto_team=excluded.auto_team,active=excluded.active,version=private.kids_session_series.version+1
   returning version into v;
  exception when check_violation or invalid_datetime_format or numeric_value_out_of_range or invalid_text_representation then raise exception 'kids_invalid' using errcode='22023';
  end;
  perform private.kids_series_run((p_data->>'id')::uuid);
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'kids.series_saved','kids_series',(p_data->>'id'),jsonb_build_object('unit_id',p_unit,'rule',p_data->>'rule'));
  return jsonb_build_object('ok',true,'version',v);
 elsif p_action='series_delete' then
  delete from private.kids_session_series where id=nullif(p_data->>'id','')::uuid and unit_id=p_unit;
  return jsonb_build_object('ok',true);
 elsif p_action='series_skip' then
  update private.kids_session_series set skip_dates=array(select distinct x from unnest(skip_dates||(p_data->>'date')::date) x),version=version+1 where id=nullif(p_data->>'id','')::uuid and unit_id=p_unit;
  return jsonb_build_object('ok',true);
 elsif p_action='bookable' then
  -- Sessão avulsa: abrir a reserva das famílias antes do início.
  update private.kids_sessions set bookable_from=case when nullif(p_data->>'hours','') is null then null else starts_at-make_interval(hours=>least(336,greatest(1,(p_data->>'hours')::int))) end,version=version+1
   where id=nullif(p_data->>'session','')::uuid and unit_id=p_unit and status='draft';
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'kids_invalid' using errcode='22023';
end $function$;
revoke all on function private.kids_setup(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.kids_setup(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.kids_setup(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.kids_setup(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.kids_setup(uuid,uuid,text,jsonb) to authenticated;

-- Escala de sessão: quem já está na equipe fixa pode ser escalado (a identidade foi conferida ao entrar na equipe).
-- Famílias: sessões em rascunho que já abriram para reserva aparecem e podem ser reservadas.
do $$ declare d text; n int; begin
 d:=pg_get_functiondef('private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure);
 if position('s.bookable_from<=clock_timestamp()' in d)=0 then
  n:=(length(d)-length(replace(d,'where s.organization_id=p_org and s.unit_id=p_unit and s.status=''open'' and s.ends_at>clock_timestamp()','')))/length('where s.organization_id=p_org and s.unit_id=p_unit and s.status=''open'' and s.ends_at>clock_timestamp()');
  if n<>1 then raise exception 'member_family: lista de sessões não encontrada (%)',n;end if;
  d:=replace(d,'where s.organization_id=p_org and s.unit_id=p_unit and s.status=''open'' and s.ends_at>clock_timestamp()',
   'where s.organization_id=p_org and s.unit_id=p_unit and (s.status=''open'' or (s.status=''draft'' and s.bookable_from<=clock_timestamp())) and s.ends_at>clock_timestamp()');
  n:=(length(d)-length(replace(d,'where id=room.session_id and status=''open'' and ends_at>clock_timestamp()','')))/length('where id=room.session_id and status=''open'' and ends_at>clock_timestamp()');
  if n<>1 then raise exception 'member_family: reserva não encontrada (%)',n;end if;
  d:=replace(d,'where id=room.session_id and status=''open'' and ends_at>clock_timestamp()','where id=room.session_id and (status=''open'' or (status=''draft'' and bookable_from<=clock_timestamp())) and ends_at>clock_timestamp()');
  execute d;
 end if;
end $$;

-- Vinha Equipe: "Configurar Kids" aparece para quem configura salas, turmas e sessões.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.staff_access(uuid,text,jsonb)'::regprocedure);
 if position('''kidsConfigure''' in d)=0 then
  if position('''kidsStations'',private.kids_station_manager(p_org,u.id),' in d)=0 then raise exception 'staff_access: trecho não encontrado';end if;
  execute replace(d,'''kidsStations'',private.kids_station_manager(p_org,u.id),','''kidsStations'',private.kids_station_manager(p_org,u.id),''kidsConfigure'',private.kids_op_allowed(p_org,u.id,null,''configure''),');
 end if;
end $$;

-- A cada 15 minutos cria as sessões das repetições que entraram na janela de antecedência.
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.unschedule(jobid) from cron.job where jobname='kids-series-run';
  perform cron.schedule('kids-series-run','*/15 * * * *','select private.kids_series_run()');
 end if;
end $$;
