-- Agenda pastoral · calendário de disponibilidade: quem atende marca, no app ou no painel, os horários de um dia
-- específico. Quando um dia tem horários próprios, eles substituem a semana padrão só naquele dia
-- (lista vazia = "não atendo neste dia"). Bloqueios (férias, viagem) continuam valendo por cima de tudo.

create table if not exists private.pastoral_dates(
 id uuid primary key default gen_random_uuid(),
 attendant_id uuid not null references private.pastoral_attendants(id) on delete cascade,
 day date not null,
 starts time, ends time,
 check((starts is null and ends is null) or (starts is not null and ends is not null and ends>starts))
);
create index if not exists pastoral_dates_attendant on private.pastoral_dates(attendant_id,day);
alter table private.pastoral_dates enable row level security;
revoke all on private.pastoral_dates from public,anon,authenticated;

-- Faixas do dia: as próprias da data (se houver registro) ou as da semana padrão.
create or replace function private.pastoral_day_ranges(p_attendant uuid, p_day date)
returns table(starts time, ends time) language sql stable security definer set search_path to '' as $$
 select d.starts,d.ends from private.pastoral_dates d where d.attendant_id=p_attendant and d.day=p_day and d.starts is not null
 union all
 select h.starts,h.ends from private.pastoral_hours h where h.attendant_id=p_attendant and h.weekday=extract(dow from p_day)::int
  and not exists(select 1 from private.pastoral_dates d where d.attendant_id=p_attendant and d.day=p_day)
$$;
revoke all on function private.pastoral_day_ranges(uuid,date) from public,anon,authenticated;

create or replace function private.pastoral_slots(p_attendant uuid, p_day date, p_minutes integer, p_member boolean)
returns setof timestamptz language sql stable security definer set search_path to '' as $$
 with a as (select x.*,private.unit_timezone(x.unit_id) tz from private.pastoral_attendants x where x.id=p_attendant and x.active)
 select s from a
  cross join lateral private.pastoral_day_ranges(a.id,p_day) h
  cross join lateral generate_series((p_day+h.starts) at time zone a.tz,((p_day+h.ends) at time zone a.tz)-make_interval(mins=>p_minutes),interval '30 minutes') s
 where not exists(select 1 from private.pastoral_blocks b where b.attendant_id=a.id and p_day between b.starts_on and b.ends_on)
  and (not p_member or s>=now()+interval '24 hours')
  and s>now()
  and not exists(select 1 from private.pastoral_appointments ap where ap.attendant_id=a.id and ap.status in('requested','confirmed') and tstzrange(ap.starts_at,ap.ends_at) && tstzrange(s,s+make_interval(mins=>p_minutes)))
 order by s
$$;
revoke all on function private.pastoral_slots(uuid,date,integer,boolean) from public,anon,authenticated;

-- Calendário de quem atende: month (situação de cada dia), day (salvar horários de uma data), reset (voltar à semana padrão).
create or replace function private.pastoral_availability(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare a private.pastoral_attendants; d0 date; d date; x jsonb; v integer;
begin
 if auth.uid() is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_pastoral' using errcode='22023';end if;
 select * into a from private.pastoral_attendants where id=nullif(p_data->>'attendant','')::uuid and organization_id=p_org and unit_id=p_unit;
 if a.id is null or not(private.pastoral_self(a.id) or private.can(p_org,p_unit,'pastoral.settings','edit')) then raise exception 'pastoral_denied' using errcode='42501';end if;
 if p_action='month' then
  if coalesce(p_data->>'month','') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  d0:=(p_data->>'month'||'-01')::date;
  return jsonb_build_object('version',a.version,
   'hours',coalesce((select jsonb_agg(jsonb_build_object('weekday',h.weekday,'starts',to_char(h.starts,'HH24:MI'),'ends',to_char(h.ends,'HH24:MI')) order by h.weekday,h.starts) from private.pastoral_hours h where h.attendant_id=a.id),'[]'::jsonb),
   'blocks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'from',b.starts_on,'to',b.ends_on,'reason',b.reason) order by b.starts_on) from private.pastoral_blocks b where b.attendant_id=a.id and b.ends_on>=d0 and b.starts_on<(d0+interval '1 month')::date),'[]'::jsonb),
   'days',(select jsonb_agg(jsonb_build_object('date',g::date,
     'custom',exists(select 1 from private.pastoral_dates pd where pd.attendant_id=a.id and pd.day=g::date),
     'blocked',exists(select 1 from private.pastoral_blocks b where b.attendant_id=a.id and g::date between b.starts_on and b.ends_on),
     'booked',(select count(*) from private.pastoral_appointments ap where ap.attendant_id=a.id and ap.status in('requested','confirmed') and (ap.starts_at at time zone private.unit_timezone(a.unit_id))::date=g::date),
     'ranges',coalesce((select jsonb_agg(jsonb_build_object('starts',to_char(r.starts,'HH24:MI'),'ends',to_char(r.ends,'HH24:MI')) order by r.starts) from private.pastoral_day_ranges(a.id,g::date) r),'[]'::jsonb)) order by g)
    from generate_series(d0,(d0+interval '1 month'-interval '1 day')::date,interval '1 day') g));
 elsif p_action in('day','reset') then
  if coalesce(p_data->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  d:=(p_data->>'date')::date;
  if d<(now() at time zone private.unit_timezone(a.unit_id))::date or d>current_date+400 then raise exception 'invalid_pastoral' using errcode='22023';end if;
  perform 1 from private.pastoral_attendants where id=a.id for update;
  delete from private.pastoral_dates where attendant_id=a.id and day=d;
  if p_action='day' then
   if jsonb_typeof(p_data->'ranges')<>'array' or jsonb_array_length(p_data->'ranges')>6 then raise exception 'invalid_pastoral' using errcode='22023';end if;
   for x in select value from jsonb_array_elements(p_data->'ranges') loop
    if coalesce(x->>'starts','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or coalesce(x->>'ends','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or (x->>'ends')::time<=(x->>'starts')::time then raise exception 'invalid_pastoral' using errcode='22023';end if;
   end loop;
   if exists(select 1 from jsonb_array_elements(p_data->'ranges') r1,jsonb_array_elements(p_data->'ranges') r2 where r1<>r2 and (r1->>'starts')::time<(r2->>'ends')::time and (r2->>'starts')::time<(r1->>'ends')::time) then raise exception 'invalid_pastoral' using errcode='22023';end if;
   if jsonb_array_length(p_data->'ranges')=0 then insert into private.pastoral_dates(attendant_id,day) values(a.id,d);
   else insert into private.pastoral_dates(attendant_id,day,starts,ends) select a.id,d,(r->>'starts')::time,(r->>'ends')::time from jsonb_array_elements(p_data->'ranges') r;end if;
  end if;
  update private.pastoral_attendants set version=version+1,updated_at=clock_timestamp() where id=a.id returning version into v;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'pastoral.date_'||p_action,'pastoral_attendant',a.id::text,jsonb_build_object('unit_id',p_unit,'date',d));
  return jsonb_build_object('ok',true,'version',v);
 end if;
 raise exception 'invalid_pastoral' using errcode='22023';
end $function$;
revoke all on function private.pastoral_availability(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.pastoral_availability(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.pastoral_availability(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.pastoral_availability(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.pastoral_availability(uuid,uuid,text,jsonb) to authenticated;
