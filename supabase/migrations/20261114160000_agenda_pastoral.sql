-- Agenda pastoral e de liderança: quem atende, horários da semana, bloqueios e atendimentos.
-- Membro pede horário pelo app (calendário de dias livres); pastor, líder ou secretaria marcam com o membro.
-- Regras: confirmação automática ou manual por quem atende; mínimo de 24 h de antecedência; cancelamento pelo
-- membro até 12 h antes; até 2 pedidos em aberto por membro; duração escolhida entre as que quem atende aceita.

create extension if not exists btree_gist with schema extensions;

insert into private.permission_catalog(code,module,area,label,actions,group_kinds,position,owner_only) values
 ('pastoral.agenda','people','Pessoas','Agenda pastoral',array['view','create','edit','approve'],'{}',14,false),
 ('pastoral.settings','people','Pessoas','Configurar agenda pastoral',array['view','edit'],'{}',15,false),
 ('pastoral.notes','people','Pessoas','Anotações pastorais sigilosas',array['view'],'{}',16,false)
on conflict(code) do nothing;

create table if not exists private.pastoral_attendants(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 person_id uuid not null references public.people(id) on delete cascade,
 role_label text not null default 'Pastor' check(length(btrim(role_label)) between 2 and 40),
 about text not null default '' check(length(about)<=300),
 auto_confirm boolean not null default false,
 durations smallint[] not null default '{30,45,60}' check(cardinality(durations) between 1 and 6 and durations <@ array[15,30,45,60,90,120]::smallint[]),
 kinds text[] not null default '{conversa,aconselhamento,oracao,visita}' check(cardinality(kinds) between 1 and 5 and kinds <@ array['conversa','aconselhamento','oracao','visita','outro']),
 modes text[] not null default '{presencial}' check(cardinality(modes) between 1 and 3 and modes <@ array['presencial','online','visita']),
 active boolean not null default true,
 version integer not null default 1 check(version>0),
 created_by uuid,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(unit_id,person_id)
);
create table if not exists private.pastoral_hours(
 id uuid primary key default gen_random_uuid(),
 attendant_id uuid not null references private.pastoral_attendants(id) on delete cascade,
 weekday smallint not null check(weekday between 0 and 6),
 starts time not null, ends time not null, check(ends>starts)
);
create index if not exists pastoral_hours_attendant on private.pastoral_hours(attendant_id,weekday);
create table if not exists private.pastoral_blocks(
 id uuid primary key default gen_random_uuid(),
 attendant_id uuid not null references private.pastoral_attendants(id) on delete cascade,
 starts_on date not null, ends_on date not null, check(ends_on>=starts_on and ends_on-starts_on<=366),
 reason text not null default '' check(length(reason)<=120)
);
create index if not exists pastoral_blocks_attendant on private.pastoral_blocks(attendant_id,starts_on);
create table if not exists private.pastoral_appointments(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 attendant_id uuid not null references private.pastoral_attendants(id) on delete restrict,
 person_id uuid not null references public.people(id) on delete cascade,
 user_id uuid references auth.users(id) on delete set null,
 kind text not null check(kind in('conversa','aconselhamento','oracao','visita','outro')),
 mode text not null check(mode in('presencial','online','visita')),
 starts_at timestamptz not null, ends_at timestamptz not null, check(ends_at>starts_at and ends_at-starts_at<=interval '2 hours'),
 status text not null check(status in('requested','confirmed','declined','cancelled','done','missed')),
 origin text not null check(origin in('member','staff')),
 member_ack boolean not null default true,
 message text not null default '' check(length(message)<=500),
 notes text not null default '' check(length(notes)<=4000),
 link text not null default '' check(length(link)<=300),
 decided_reason text not null default '' check(length(decided_reason)<=200),
 version integer not null default 1 check(version>0),
 created_by uuid,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 constraint pastoral_no_overlap exclude using gist(attendant_id with =,tstzrange(starts_at,ends_at) with &&) where (status in('requested','confirmed'))
);
create index if not exists pastoral_appointments_user on private.pastoral_appointments(user_id,organization_id,starts_at);
create index if not exists pastoral_appointments_person on private.pastoral_appointments(person_id);
create index if not exists pastoral_appointments_scope on private.pastoral_appointments(unit_id,starts_at);
alter table private.pastoral_attendants enable row level security;
alter table private.pastoral_hours enable row level security;
alter table private.pastoral_blocks enable row level security;
alter table private.pastoral_appointments enable row level security;
revoke all on private.pastoral_attendants,private.pastoral_hours,private.pastoral_blocks,private.pastoral_appointments from public,anon,authenticated;

-- Horários livres de um dia (início de cada horário, a cada 30 min). p_member aplica a antecedência mínima de 24 h.
create or replace function private.pastoral_slots(p_attendant uuid, p_day date, p_minutes integer, p_member boolean)
returns setof timestamptz language sql stable security definer set search_path to '' as $$
 with a as (select x.*,private.unit_timezone(x.unit_id) tz from private.pastoral_attendants x where x.id=p_attendant and x.active)
 select s from a
  join private.pastoral_hours h on h.attendant_id=a.id and h.weekday=extract(dow from p_day)::int
  cross join lateral generate_series((p_day+h.starts) at time zone a.tz,((p_day+h.ends) at time zone a.tz)-make_interval(mins=>p_minutes),interval '30 minutes') s
 where not exists(select 1 from private.pastoral_blocks b where b.attendant_id=a.id and p_day between b.starts_on and b.ends_on)
  and (not p_member or s>=now()+interval '24 hours')
  and s>now()
  and not exists(select 1 from private.pastoral_appointments ap where ap.attendant_id=a.id and ap.status in('requested','confirmed') and tstzrange(ap.starts_at,ap.ends_at) && tstzrange(s,s+make_interval(mins=>p_minutes)))
 order by s
$$;
revoke all on function private.pastoral_slots(uuid,date,integer,boolean) from public,anon,authenticated;

create or replace function private.pastoral_person(p_org uuid) returns uuid language sql stable security definer set search_path to '' as $$
 select p.id from public.people p where p.organization_id=p_org and p.auth_user_id=auth.uid() and p.status='active' order by p.created_at limit 1
$$;
revoke all on function private.pastoral_person(uuid) from public,anon,authenticated;

create or replace function private.pastoral_row(ap private.pastoral_appointments, p_notes boolean) returns jsonb language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('id',ap.id,'attendantId',ap.attendant_id,'attendant',coalesce(pp.full_name,''),'role',coalesce(at.role_label,''),'personId',ap.person_id,'person',coalesce(m.full_name,''),
  'kind',ap.kind,'mode',ap.mode,'startsAt',ap.starts_at,'endsAt',ap.ends_at,'status',ap.status,'origin',ap.origin,'memberAck',ap.member_ack,'message',ap.message,'link',ap.link,'reason',ap.decided_reason,
  'notes',case when p_notes then ap.notes else '' end,'version',ap.version,
  'address',case when ap.mode='visita' and ap.status='confirmed' then concat_ws(', ',nullif(m.street,''),nullif(m.number,''),nullif(m.district,''),nullif(m.city,'')) else '' end)
 from private.pastoral_attendants at join public.people pp on pp.id=at.person_id
  left join lateral (select pe.full_name,pa.street,pa.number,pa.district,pa.city from public.people pe left join public.person_addresses pa on pa.person_id=pe.id and pa.organization_id=pe.organization_id where pe.id=ap.person_id order by pa.updated_at desc nulls last limit 1) m on true
 where at.id=ap.attendant_id
$$;
revoke all on function private.pastoral_row(private.pastoral_appointments,boolean) from public,anon,authenticated;

-- ===== Membro (app) =====
create or replace function private.pastoral_member(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare actor uuid=auth.uid(); me uuid; a private.pastoral_attendants; ap private.pastoral_appointments; tz text; m date; d date; mins integer; st timestamptz; days jsonb='[]'; n integer; open_count integer; v integer;
begin
 if actor is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action is null or p_action not in('attendants','month','day','request','mine','cancel','ack') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>8000 then raise exception 'invalid_pastoral' using errcode='22023';end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 me:=private.pastoral_person(p_org);
 if p_action='attendants' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',p.full_name,'role',x.role_label,'about',x.about,'durations',x.durations,'kinds',x.kinds,'modes',x.modes,'autoConfirm',x.auto_confirm,
    'myLeader',me is not null and exists(select 1 from public.church_cells c join public.church_cell_participants cp on cp.cell_id=c.id and cp.status='active' and cp.person_id=me where c.leader_person_id=x.person_id and c.status='active'),
    'pastor',coalesce((to_jsonb(p)->>'is_pastor')::boolean,false)) order by 2)
   from private.pastoral_attendants x join public.people p on p.id=x.person_id where x.organization_id=p_org and x.unit_id=p_unit and x.active and p.status='active' and exists(select 1 from private.pastoral_hours h where h.attendant_id=x.id)),'[]'::jsonb),
   'linked',me is not null,'rules',jsonb_build_object('minHours',24,'cancelHours',12,'maxOpen',2));
 elsif p_action='mine' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(private.pastoral_row(ap2,false) order by ap2.starts_at desc) from (select * from private.pastoral_appointments z where z.organization_id=p_org and (z.user_id=actor or me is not null and z.person_id=me) and z.starts_at>now()-interval '180 days' order by z.starts_at desc limit 50) ap2),'[]'::jsonb));
 end if;

 if p_action in('month','day','request') then
  select * into a from private.pastoral_attendants where id=nullif(p_data->>'attendant','')::uuid and organization_id=p_org and unit_id=p_unit and active;
  if a.id is null then raise exception 'pastoral_unavailable' using errcode='22023';end if;
  mins:=(p_data->>'minutes')::integer;
  if mins is null or not mins=any(a.durations) then raise exception 'invalid_pastoral' using errcode='22023';end if;
  tz:=private.unit_timezone(p_unit);
 end if;

 if p_action='month' then
  if coalesce(p_data->>'month','') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  m:=(p_data->>'month'||'-01')::date;
  for d in select g::date from generate_series(m,(m+interval '1 month'-interval '1 day')::date,interval '1 day') g loop
   if d<(now() at time zone tz)::date then days:=days||jsonb_build_object('date',d,'state','past','slots',0);continue;end if;
   if d>(now() at time zone tz)::date+60 then days:=days||jsonb_build_object('date',d,'state','closed','slots',0);continue;end if;
   if not exists(select 1 from private.pastoral_hours h where h.attendant_id=a.id and h.weekday=extract(dow from d)::int) or exists(select 1 from private.pastoral_blocks b where b.attendant_id=a.id and d between b.starts_on and b.ends_on) then
    days:=days||jsonb_build_object('date',d,'state','none','slots',0);continue;end if;
   select count(*) into n from private.pastoral_slots(a.id,d,mins,true);
   days:=days||jsonb_build_object('date',d,'state',case when n>0 then 'available' else 'full' end,'slots',n);
  end loop;
  return jsonb_build_object('month',p_data->>'month','timezone',tz,'days',days);
 elsif p_action='day' then
  if coalesce(p_data->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  d:=(p_data->>'date')::date;
  if d>(now() at time zone tz)::date+60 then return jsonb_build_object('date',d,'slots','[]'::jsonb);end if;
  return jsonb_build_object('date',d,'timezone',tz,'slots',coalesce((select jsonb_agg(jsonb_build_object('startsAt',s,'label',to_char(s at time zone tz,'HH24:MI')) order by s) from private.pastoral_slots(a.id,d,mins,true) s),'[]'::jsonb));
 elsif p_action='request' then
  if me is null then raise exception 'pastoral_profile_required' using errcode='42501';end if;
  if not(p_data?&array['id','attendant','minutes','startsAt','kind','mode','message']) or p_data-array['id','attendant','minutes','startsAt','kind','mode','message']<>'{}'
   or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or length(coalesce(p_data->>'message',''))>500 or (p_data->>'message') ~ '[\x00-\x08\x0b\x0c\x0e-\x1f]'
   or not (p_data->>'kind')=any(a.kinds) or not (p_data->>'mode')=any(a.modes) then raise exception 'invalid_pastoral' using errcode='22023';end if;
  select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid;
  if ap.id is not null then if ap.user_id=actor then return jsonb_build_object('ok',true,'id',ap.id,'status',ap.status,'version',ap.version);end if;raise exception 'invalid_pastoral' using errcode='22023';end if;
  st:=(p_data->>'startsAt')::timestamptz;
  perform pg_advisory_xact_lock(hashtextextended('pastoral:'||a.id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('pastoral-user:'||actor::text,0));
  select count(*) into open_count from private.pastoral_appointments where organization_id=p_org and user_id=actor and status in('requested','confirmed') and ends_at>now();
  if open_count>=2 then raise exception 'pastoral_open_limit' using errcode='54000';end if;
  if not exists(select 1 from private.pastoral_slots(a.id,(st at time zone tz)::date,mins,true) s where s=st) then raise exception 'pastoral_slot_taken' using errcode='40001';end if;
  insert into private.pastoral_appointments(id,organization_id,unit_id,attendant_id,person_id,user_id,kind,mode,starts_at,ends_at,status,origin,member_ack,message,created_by)
   values((p_data->>'id')::uuid,p_org,p_unit,a.id,me,actor,p_data->>'kind',p_data->>'mode',st,st+make_interval(mins=>mins),case when a.auto_confirm then 'confirmed' else 'requested' end,'member',true,btrim(p_data->>'message'),actor) returning * into ap;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.request','pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',p_unit,'attendant',a.id,'status',ap.status));
  return jsonb_build_object('ok',true,'id',ap.id,'status',ap.status,'version',ap.version);
 else -- cancel / ack
  if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or jsonb_typeof(p_data->'version')<>'number' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid and organization_id=p_org for update;
  if ap.id is null or not(ap.user_id=actor or me is not null and ap.person_id=me) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if ap.version<>(p_data->>'version')::integer then raise exception 'pastoral_changed' using errcode='40001';end if;
  if p_action='cancel' then
   if ap.status not in('requested','confirmed') then raise exception 'pastoral_changed' using errcode='40001';end if;
   if ap.starts_at<now()+interval '12 hours' then raise exception 'pastoral_cancel_late' using errcode='22023';end if;
   update private.pastoral_appointments set status='cancelled',version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  else
   if ap.status<>'confirmed' or ap.member_ack then raise exception 'pastoral_changed' using errcode='40001';end if;
   update private.pastoral_appointments set member_ack=true,version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.member_'||p_action,'pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',ap.unit_id));
  return jsonb_build_object('ok',true,'id',ap.id,'version',v);
 end if;
end $function$;
revoke all on function private.pastoral_member(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.pastoral_member(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.pastoral_member(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.pastoral_member(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.pastoral_member(uuid,uuid,text,jsonb) to authenticated;

-- ===== Equipe (painel e app de quem atende) =====
-- Quem atende sempre organiza a própria agenda; secretaria e pastores precisam da permissão.
create or replace function private.pastoral_self(p_attendant uuid) returns boolean language sql stable security definer set search_path to '' as $$
 select exists(select 1 from private.pastoral_attendants a join public.people p on p.id=a.person_id where a.id=p_attendant and p.auth_user_id=auth.uid() and p.status='active'
  and exists(select 1 from public.organization_memberships m where m.organization_id=a.organization_id and m.user_id=auth.uid() and m.status='active'))
$$;
revoke all on function private.pastoral_self(uuid) from public,anon,authenticated;

create or replace function private.pastoral_staff(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare actor uuid=auth.uid(); a private.pastoral_attendants; ap private.pastoral_appointments; att uuid; tz text; v integer; mins integer; st timestamptz; person uuid; x jsonb; fr timestamptz; tt timestamptz;
 can_view boolean; can_edit boolean; can_settings boolean; can_notes boolean;
begin
 if actor is null then raise exception 'pastoral_denied' using errcode='42501';end if;
 if p_action is null or p_action not in('overview','save_attendant','hours','block','unblock','decide','schedule','status','note','slots') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>16000 then raise exception 'invalid_pastoral' using errcode='22023';end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'pastoral_denied' using errcode='42501';end if;
 can_view:=private.can(p_org,p_unit,'pastoral.agenda','view');can_edit:=private.can(p_org,p_unit,'pastoral.agenda','edit');can_settings:=private.can(p_org,p_unit,'pastoral.settings','edit');can_notes:=private.can(p_org,p_unit,'pastoral.notes','view');
 tz:=private.unit_timezone(p_unit);

 if p_action='overview' then
  fr:=coalesce(nullif(p_data->>'from','')::timestamptz,now()-interval '7 days');tt:=coalesce(nullif(p_data->>'to','')::timestamptz,now()+interval '35 days');
  if tt<fr or tt-fr>interval '120 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  if not(can_view or can_settings or exists(select 1 from private.pastoral_attendants z where z.organization_id=p_org and z.unit_id=p_unit and private.pastoral_self(z.id))) then raise exception 'pastoral_denied' using errcode='42501';end if;
  return jsonb_build_object('timezone',tz,'canEdit',can_edit,'canSettings',can_settings,
   'attendants',coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'personId',z.person_id,'name',p.full_name,'role',z.role_label,'about',z.about,'autoConfirm',z.auto_confirm,'durations',z.durations,'kinds',z.kinds,'modes',z.modes,'active',z.active,'version',z.version,'self',private.pastoral_self(z.id),
     'hours',coalesce((select jsonb_agg(jsonb_build_object('weekday',h.weekday,'starts',to_char(h.starts,'HH24:MI'),'ends',to_char(h.ends,'HH24:MI')) order by h.weekday,h.starts) from private.pastoral_hours h where h.attendant_id=z.id),'[]'::jsonb),
     'blocks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'from',b.starts_on,'to',b.ends_on,'reason',b.reason) order by b.starts_on) from private.pastoral_blocks b where b.attendant_id=z.id and b.ends_on>=current_date),'[]'::jsonb)) order by p.full_name)
    from private.pastoral_attendants z join public.people p on p.id=z.person_id where z.organization_id=p_org and z.unit_id=p_unit and (can_view or can_settings or private.pastoral_self(z.id))),'[]'::jsonb),
   'items',coalesce((select jsonb_agg(private.pastoral_row(q,private.pastoral_self(q.attendant_id) or can_notes) order by q.starts_at) from private.pastoral_appointments q
    where q.organization_id=p_org and q.unit_id=p_unit and q.starts_at between fr and tt and (can_view or private.pastoral_self(q.attendant_id))),'[]'::jsonb));
 end if;

 if p_action='save_attendant' then
  if not can_settings then raise exception 'pastoral_denied' using errcode='42501';end if;
  if not(p_data?&array['id','person','role','about','autoConfirm','durations','kinds','modes','active','version']) or p_data-array['id','person','role','about','autoConfirm','durations','kinds','modes','active','version']<>'{}' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  person:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=person and organization_id=p_org and status='active') then raise exception 'invalid_pastoral' using errcode='22023';end if;
  select * into a from private.pastoral_attendants where id=(p_data->>'id')::uuid for update;
  if a.id is null then
   if (p_data->>'version')::int<>0 then raise exception 'pastoral_changed' using errcode='40001';end if;
   insert into private.pastoral_attendants(id,organization_id,unit_id,person_id,role_label,about,auto_confirm,durations,kinds,modes,active,created_by)
    values((p_data->>'id')::uuid,p_org,p_unit,person,btrim(p_data->>'role'),btrim(p_data->>'about'),(p_data->>'autoConfirm')::boolean,
     array(select jsonb_array_elements_text(p_data->'durations')::smallint),array(select jsonb_array_elements_text(p_data->'kinds')),array(select jsonb_array_elements_text(p_data->'modes')),(p_data->>'active')::boolean,actor) returning version into v;
  else
   if a.organization_id<>p_org or a.unit_id<>p_unit then raise exception 'pastoral_denied' using errcode='42501';end if;
   if a.version<>(p_data->>'version')::int then raise exception 'pastoral_changed' using errcode='40001';end if;
   update private.pastoral_attendants set person_id=person,role_label=btrim(p_data->>'role'),about=btrim(p_data->>'about'),auto_confirm=(p_data->>'autoConfirm')::boolean,
    durations=array(select jsonb_array_elements_text(p_data->'durations')::smallint),kinds=array(select jsonb_array_elements_text(p_data->'kinds')),modes=array(select jsonb_array_elements_text(p_data->'modes')),
    active=(p_data->>'active')::boolean,version=version+1,updated_at=clock_timestamp() where id=a.id returning version into v;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.attendant_saved','pastoral_attendant',p_data->>'id',jsonb_build_object('unit_id',p_unit));
  return jsonb_build_object('ok',true,'id',p_data->>'id','version',v);
 end if;

 att:=nullif(p_data->>'attendant','')::uuid;
 if p_action in('hours','block','unblock','schedule','slots') then
  select * into a from private.pastoral_attendants where id=att and organization_id=p_org and unit_id=p_unit for update;
  if a.id is null then raise exception 'pastoral_denied' using errcode='42501';end if;
 end if;

 if p_action in('hours','block','unblock') then
  if not(private.pastoral_self(a.id) or can_settings) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if p_action='hours' then
   -- Substitui a semana inteira: [{weekday,starts,ends}], até 21 faixas, sem sobreposição no mesmo dia.
   if jsonb_typeof(p_data->'hours')<>'array' or jsonb_array_length(p_data->'hours')>21 then raise exception 'invalid_pastoral' using errcode='22023';end if;
   for x in select value from jsonb_array_elements(p_data->'hours') loop
    if (x->>'weekday') !~ '^[0-6]$' or coalesce(x->>'starts','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or coalesce(x->>'ends','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or (x->>'ends')::time<=(x->>'starts')::time then raise exception 'invalid_pastoral' using errcode='22023';end if;
   end loop;
   if exists(select 1 from jsonb_array_elements(p_data->'hours') h1,jsonb_array_elements(p_data->'hours') h2 where h1<>h2 and h1->>'weekday'=h2->>'weekday' and (h1->>'starts')::time<(h2->>'ends')::time and (h2->>'starts')::time<(h1->>'ends')::time) then raise exception 'invalid_pastoral' using errcode='22023';end if;
   delete from private.pastoral_hours where attendant_id=a.id;
   insert into private.pastoral_hours(attendant_id,weekday,starts,ends) select a.id,(h->>'weekday')::smallint,(h->>'starts')::time,(h->>'ends')::time from jsonb_array_elements(p_data->'hours') h;
  elsif p_action='block' then
   if coalesce(p_data->>'from','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(p_data->>'to','') !~ '^\d{4}-\d{2}-\d{2}$' or length(coalesce(p_data->>'reason',''))>120 then raise exception 'invalid_pastoral' using errcode='22023';end if;
   insert into private.pastoral_blocks(attendant_id,starts_on,ends_on,reason) values(a.id,(p_data->>'from')::date,(p_data->>'to')::date,btrim(coalesce(p_data->>'reason','')));
  else
   delete from private.pastoral_blocks where id=nullif(p_data->>'id','')::uuid and attendant_id=a.id;
  end if;
  update private.pastoral_attendants set version=version+1,updated_at=clock_timestamp() where id=a.id returning version into v;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.'||p_action,'pastoral_attendant',a.id::text,jsonb_build_object('unit_id',p_unit));
  return jsonb_build_object('ok',true,'id',a.id,'version',v);
 end if;

 if p_action='slots' then
  if not(private.pastoral_self(a.id) or can_edit) then raise exception 'pastoral_denied' using errcode='42501';end if;
  mins:=(p_data->>'minutes')::integer;
  if mins is null or mins not in(15,30,45,60,90,120) or coalesce(p_data->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  return jsonb_build_object('slots',coalesce((select jsonb_agg(jsonb_build_object('startsAt',s,'label',to_char(s at time zone tz,'HH24:MI')) order by s) from private.pastoral_slots(a.id,(p_data->>'date')::date,mins,false) s),'[]'::jsonb));
 end if;

 if p_action='schedule' then
  -- Equipe marca com um membro (ex.: visita). Sem a regra das 24 h, mas sem sobrepor horários.
  if not(private.pastoral_self(a.id) or can_edit) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if not(p_data?&array['id','attendant','person','minutes','startsAt','kind','mode','message','link']) or p_data-array['id','attendant','person','minutes','startsAt','kind','mode','message','link']<>'{}'
   or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or (p_data->>'minutes')::int not in(15,30,45,60,90,120) or (p_data->>'kind') not in('conversa','aconselhamento','oracao','visita','outro') or (p_data->>'mode') not in('presencial','online','visita')
   or length(coalesce(p_data->>'message',''))>500 or length(coalesce(p_data->>'link',''))>300 or (p_data->>'link')<>'' and (p_data->>'link') !~ '^https://' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  person:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=person and organization_id=p_org and status='active') then raise exception 'invalid_pastoral' using errcode='22023';end if;
  -- Líder de célula sem permissão geral só marca com participantes das suas células.
  if not can_edit and not coalesce((select to_jsonb(p)->>'is_pastor' from public.people p where p.id=a.person_id),'false')::boolean
   and not exists(select 1 from public.church_cells c join public.church_cell_participants cp on cp.cell_id=c.id and cp.status='active' where c.leader_person_id=a.person_id and cp.person_id=person) then raise exception 'pastoral_denied' using errcode='42501';end if;
  select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid;
  if ap.id is not null then return jsonb_build_object('ok',true,'id',ap.id,'version',ap.version);end if;
  st:=(p_data->>'startsAt')::timestamptz;
  if st<now() or st>now()+interval '180 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  begin
   insert into private.pastoral_appointments(id,organization_id,unit_id,attendant_id,person_id,user_id,kind,mode,starts_at,ends_at,status,origin,member_ack,message,link,created_by)
    values((p_data->>'id')::uuid,p_org,p_unit,a.id,person,(select auth_user_id from public.people where id=person),p_data->>'kind',p_data->>'mode',st,st+make_interval(mins=>(p_data->>'minutes')::int),'confirmed','staff',false,btrim(p_data->>'message'),p_data->>'link',actor) returning * into ap;
  exception when exclusion_violation then raise exception 'pastoral_slot_taken' using errcode='40001';
  end;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.schedule','pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',p_unit,'attendant',a.id));
  return jsonb_build_object('ok',true,'id',ap.id,'version',ap.version);
 end if;

 -- decide / status / note: atendimento existente
 if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or jsonb_typeof(p_data->'version')<>'number' then raise exception 'invalid_pastoral' using errcode='22023';end if;
 select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if ap.id is null then raise exception 'pastoral_denied' using errcode='42501';end if;
 if ap.version<>(p_data->>'version')::int then raise exception 'pastoral_changed' using errcode='40001';end if;
 if p_action='note' then
  if not private.pastoral_self(ap.attendant_id) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if length(coalesce(p_data->>'notes',''))>4000 then raise exception 'invalid_pastoral' using errcode='22023';end if;
  update private.pastoral_appointments set notes=coalesce(p_data->>'notes',''),version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
 else
  if not(private.pastoral_self(ap.attendant_id) or private.can(p_org,p_unit,'pastoral.agenda','approve') or can_edit) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if p_action='decide' then
   if ap.status<>'requested' or p_data->>'decision' not in('confirm','decline') or length(coalesce(p_data->>'reason',''))>200 or length(coalesce(p_data->>'link',''))>300 or coalesce(p_data->>'link','')<>'' and (p_data->>'link') !~ '^https://' then raise exception 'invalid_pastoral' using errcode='22023';end if;
   update private.pastoral_appointments set status=case when p_data->>'decision'='confirm' then 'confirmed' else 'declined' end,decided_reason=btrim(coalesce(p_data->>'reason','')),link=coalesce(nullif(p_data->>'link',''),link),version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  else
   if p_data->>'status' not in('done','missed','cancelled') or ap.status not in('requested','confirmed') or p_data->>'status' in('done','missed') and ap.starts_at>now() then raise exception 'invalid_pastoral' using errcode='22023';end if;
   update private.pastoral_appointments set status=p_data->>'status',decided_reason=btrim(coalesce(p_data->>'reason','')),version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.'||p_action,'pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',p_unit));
 return jsonb_build_object('ok',true,'id',ap.id,'version',v);
end $function$;
revoke all on function private.pastoral_staff(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.pastoral_staff(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.pastoral_staff(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.pastoral_staff(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.pastoral_staff(uuid,uuid,text,jsonb) to authenticated;

-- Caixa de notificações do app: confirmações e recusas, sem o motivo do atendimento.
do $$ begin
 if to_regprocedure('private.member_inbox_before_pastoral(uuid,uuid)') is null then
  alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_pastoral;
 end if;
end $$;
create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from private.member_inbox_before_pastoral(p_org,p_unit)
  union all
  select 'pastoral:'||ap.id::text||':'||ap.status,
   case when ap.status='confirmed' and ap.origin='staff' then 'Marcamos um horário com você' when ap.status='confirmed' then 'Seu horário foi confirmado' else 'Não foi possível atender neste horário' end,
   'Com '||coalesce(p.full_name,'a equipe pastoral')||' em '||to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'DD/MM "às" HH24:MI')||case when ap.status='declined' then '. Escolha outro dia no app.' else '.' end,
   ap.updated_at,'pastoral'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people p on p.id=at.person_id
  where ap.organization_id=p_org and ap.user_id=auth.uid() and ap.status in('confirmed','declined') and ap.updated_at>now()-interval '60 days'
   and not(ap.status='confirmed' and ap.origin='member' and at.auto_confirm and ap.created_at=ap.updated_at)
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;
