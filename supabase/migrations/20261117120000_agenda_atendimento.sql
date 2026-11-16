-- Agenda de atendimento (docs/ANALISE-AGENDA-ATENDIMENTO-ACOMPANHAMENTO.md), com as decisões:
-- horários sempre respeitados; convite do atendente com aceite do membro (liberado 12 h antes sem resposta);
-- relatório de atendimento com sigilo por permissão de usuário (Equipe pastoral, Restrito, Sigiloso);
-- "Novos convertidos" vira "Integração Visitante" com decisão de fé; calendário do atendente.

-- ── A. Regras por atendente ──────────────────────────────────────────────────────────────────────
alter table private.pastoral_attendants add column if not exists audience text not null default 'all';
alter table private.pastoral_attendants add column if not exists min_notice_hours integer not null default 24;
alter table private.pastoral_attendants add column if not exists max_open integer not null default 2;
alter table private.pastoral_attendants add column if not exists cancel_hours integer not null default 12;
alter table private.pastoral_attendants add column if not exists max_per_day integer;
alter table private.pastoral_attendants add column if not exists buffer_minutes integer not null default 0;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='pastoral_attendants_rules_check') then
  alter table private.pastoral_attendants add constraint pastoral_attendants_rules_check check(
   audience in('all','leaders','group','invite') and min_notice_hours between 1 and 168 and max_open between 1 and 10
   and cancel_hours between 0 and 72 and (max_per_day is null or max_per_day between 1 and 20) and buffer_minutes in(0,5,10,15,30));
 end if;
end $$;

-- Quem vê o atendente em "Falar com a liderança".
create or replace function private.pastoral_audience_ok(p_attendant uuid, p_me uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select case a.audience
  when 'all' then true
  when 'invite' then false
  when 'leaders' then p_me is not null and (
   exists(select 1 from private.group_assignments x join private.group_functions f on f.id=x.function_id where x.person_id=p_me and x.until is null and f.leadership)
   or exists(select 1 from private.person_positions pp where pp.person_id=p_me and pp.until is null)
   or exists(select 1 from public.church_cells c where c.leader_person_id=p_me and c.status='active')
   or exists(select 1 from public.church_cell_networks n where n.supervisor_person_id=p_me and n.status='active'))
  else p_me is not null and (
   exists(select 1 from public.church_cells c join public.church_cell_participants cp on cp.cell_id=c.id and cp.status='active' and cp.person_id=p_me where c.leader_person_id=a.person_id and c.status='active')
   or exists(select 1 from public.church_cell_networks n join public.church_cell_network_links l on l.network_id=n.id join public.church_cell_participants cp on cp.cell_id=l.cell_id and cp.status='active' and cp.person_id=p_me
     where n.supervisor_person_id=a.person_id and n.status='active')
   or exists(select 1 from private.group_assignments la join private.group_functions lf on lf.id=la.function_id and lf.leadership
     join private.group_assignments ma on ma.kind=la.kind and ma.group_id=la.group_id and ma.person_id=p_me and ma.until is null
     where la.person_id=a.person_id and la.until is null))
 end from private.pastoral_attendants a where a.id=p_attendant
$$;
revoke all on function private.pastoral_audience_ok(uuid,uuid) from public,anon,authenticated;

-- Convite sem resposta: liberado 12 h antes do horário.
create or replace function private.pastoral_expire(p_org uuid) returns void
language sql security definer set search_path to '' as $$
 update private.pastoral_appointments set status='cancelled',decided_reason='Sem resposta do membro: horário liberado 12 h antes.',version=version+1,updated_at=clock_timestamp()
 where organization_id=p_org and status='confirmed' and origin='staff' and not member_ack and starts_at<=now()+interval '12 hours' and starts_at>now()-interval '30 days'
$$;
revoke all on function private.pastoral_expire(uuid) from public,anon,authenticated;

-- Horários livres: antecedência, intervalo entre atendimentos, limite por dia e agenda da própria pessoa (quem atende também é atendido).
create or replace function private.pastoral_slots(p_attendant uuid, p_day date, p_minutes integer, p_member boolean)
returns setof timestamptz language sql stable security definer set search_path to '' as $$
 with a as (select x.*,private.unit_timezone(x.unit_id) tz,make_interval(mins=>x.buffer_minutes) buf from private.pastoral_attendants x where x.id=p_attendant and x.active)
 select s from a
  cross join lateral private.pastoral_day_ranges(a.id,p_day) h
  cross join lateral generate_series((p_day+h.starts) at time zone a.tz,((p_day+h.ends) at time zone a.tz)-make_interval(mins=>p_minutes),interval '30 minutes') s
 where not exists(select 1 from private.pastoral_blocks b where b.attendant_id=a.id and p_day between b.starts_on and b.ends_on)
  and (not p_member or s>=now()+make_interval(hours=>a.min_notice_hours))
  and s>now()
  and not exists(select 1 from private.pastoral_appointments ap where ap.attendant_id=a.id and ap.status in('requested','confirmed')
   and tstzrange(ap.starts_at-a.buf,ap.ends_at+a.buf) && tstzrange(s,s+make_interval(mins=>p_minutes)))
  and not exists(select 1 from private.pastoral_appointments ap where ap.person_id=a.person_id and ap.status in('requested','confirmed')
   and tstzrange(ap.starts_at,ap.ends_at) && tstzrange(s,s+make_interval(mins=>p_minutes)))
  and (a.max_per_day is null or (select count(*) from private.pastoral_appointments ap where ap.attendant_id=a.id and ap.status in('requested','confirmed')
   and (ap.starts_at at time zone a.tz)::date=p_day)<a.max_per_day)
 order by s
$$;
revoke all on function private.pastoral_slots(uuid,date,integer,boolean) from public,anon,authenticated;

-- Ajustes nas funções existentes (trechos conferidos; falha se algo não for encontrado).
do $$ declare d text;
 procedure_text text;
begin
 d:=pg_get_functiondef('private.pastoral_staff(uuid,uuid,text,jsonb)'::regprocedure);
 if position('pastoral_outside_hours' in d)=0 then
  if position($x$  st:=(p_data->>'startsAt')::timestamptz;
  if st<now() or st>now()+interval '180 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;$x$ in d)=0 then raise exception 'pastoral_staff: agendamento não encontrado'; end if;
  d:=replace(d,$x$  st:=(p_data->>'startsAt')::timestamptz;
  if st<now() or st>now()+interval '180 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;$x$,
  $x$  st:=(p_data->>'startsAt')::timestamptz;
  if st<now() or st>now()+interval '180 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  -- O atendente também respeita a própria disponibilidade (horários, datas, bloqueios e a sua agenda).
  if not exists(select 1 from private.pastoral_slots(a.id,(st at time zone private.unit_timezone(a.unit_id))::date,(p_data->>'minutes')::int,false) s where s=st) then raise exception 'pastoral_outside_hours' using errcode='22023';end if;$x$);
  if position($x$'confirmed','staff',false,$x$ in d)=0 then raise exception 'pastoral_staff: inserção não encontrada'; end if;
  -- Aceite pelo app: só quando há conta no app e mais de 12 h até o horário (urgências ficam confirmadas e avisadas).
  d:=replace(d,$x$'confirmed','staff',false,$x$,$x$'confirmed','staff',(select auth_user_id is null from public.people where id=person) or st<=now()+interval '12 hours',$x$);
  d:=replace(d,$x$can_view:=private.can(p_org,p_unit,'pastoral.agenda','view');$x$,$x$perform private.pastoral_expire(p_org);can_view:=private.can(p_org,p_unit,'pastoral.agenda','view');$x$);
  execute d;
 end if;

 d:=pg_get_functiondef('private.pastoral_member(uuid,uuid,text,jsonb)'::regprocedure);
 if position('pastoral_audience_ok' in d)=0 then
  d:=replace(d,$x$('attendants','month','day','request','mine','cancel','ack')$x$,$x$('attendants','month','day','request','mine','cancel','ack','decline')$x$);
  d:=replace(d,$x$ me:=private.pastoral_person(p_org);$x$,$x$ me:=private.pastoral_person(p_org);
 perform private.pastoral_expire(p_org);$x$);
  d:=replace(d,$x$'autoConfirm',x.auto_confirm,$x$,$x$'autoConfirm',x.auto_confirm,'rules',jsonb_build_object('minHours',x.min_notice_hours,'cancelHours',x.cancel_hours,'maxOpen',x.max_open),$x$);
  d:=replace(d,$x$where x.organization_id=p_org and x.unit_id=p_unit and x.active and p.status='active'$x$,$x$where x.organization_id=p_org and x.unit_id=p_unit and x.active and p.status='active' and private.pastoral_audience_ok(x.id,me) and x.person_id is distinct from me$x$);
  d:=replace(d,$x$if a.id is null then raise exception 'pastoral_unavailable' using errcode='22023';end if;$x$,$x$if a.id is null or not private.pastoral_audience_ok(a.id,me) then raise exception 'pastoral_unavailable' using errcode='22023';end if;$x$);
  d:=replace(d,$x$if open_count>=2 then$x$,$x$if open_count>=a.max_open then$x$);
  d:=replace(d,$x$if ap.starts_at<now()+interval '12 hours' then raise exception 'pastoral_cancel_late'$x$,$x$if ap.starts_at<now()+(select make_interval(hours=>z.cancel_hours) from private.pastoral_attendants z where z.id=ap.attendant_id) then raise exception 'pastoral_cancel_late'$x$);
  if position($x$  else
   if ap.status<>'confirmed' or ap.member_ack then$x$ in d)=0 then raise exception 'pastoral_member: aceite não encontrado'; end if;
  d:=replace(d,$x$  else
   if ap.status<>'confirmed' or ap.member_ack then$x$,$x$  elsif p_action='decline' then
   -- Convite do atendente: o membro recusa ou pede outro horário; o horário fica livre.
   if ap.status<>'confirmed' or ap.member_ack or ap.origin<>'staff' or length(coalesce(p_data->>'reason',''))>200 then raise exception 'pastoral_changed' using errcode='40001';end if;
   update private.pastoral_appointments set status='cancelled',decided_reason=left(case when coalesce((p_data->>'other')::boolean,false) then 'O membro pediu outro horário' else 'O membro recusou o convite' end||coalesce(': '||nullif(btrim(p_data->>'reason'),''),''),200),
    version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  else
   if ap.status<>'confirmed' or ap.member_ack then$x$);
  execute d;
 end if;
end $$;

-- Regras do atendente (ele mesmo ou quem configura a agenda).
create or replace function public.pastoral_rules(p_org uuid, p_unit uuid, p_attendant uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare a private.pastoral_attendants;
begin
 if auth.uid() is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_pastoral' using errcode='22023'; end if;
 select * into a from private.pastoral_attendants where id=p_attendant and organization_id=p_org and unit_id=p_unit for update;
 if a.id is null or not(private.pastoral_self(a.id) or private.can(p_org,p_unit,'pastoral.settings','edit')) then raise exception 'pastoral_denied' using errcode='42501'; end if;
 if p_data='{}'::jsonb then
  return jsonb_build_object('audience',a.audience,'minHours',a.min_notice_hours,'maxOpen',a.max_open,'cancelHours',a.cancel_hours,'maxPerDay',a.max_per_day,'buffer',a.buffer_minutes);
 end if;
 update private.pastoral_attendants set audience=coalesce(p_data->>'audience',audience),min_notice_hours=coalesce((p_data->>'minHours')::int,min_notice_hours),
  max_open=coalesce((p_data->>'maxOpen')::int,max_open),cancel_hours=coalesce((p_data->>'cancelHours')::int,cancel_hours),
  max_per_day=case when p_data ? 'maxPerDay' then nullif(p_data->>'maxPerDay','')::int else max_per_day end,buffer_minutes=coalesce((p_data->>'buffer')::int,buffer_minutes),
  version=version+1,updated_at=now() where id=a.id returning * into a;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'pastoral.rules','pastoral_attendant',a.id::text,p_data);
 return jsonb_build_object('ok',true,'audience',a.audience,'minHours',a.min_notice_hours,'maxOpen',a.max_open,'cancelHours',a.cancel_hours,'maxPerDay',a.max_per_day,'buffer',a.buffer_minutes);
end $$;
revoke all on function public.pastoral_rules(uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function public.pastoral_rules(uuid,uuid,uuid,jsonb) to authenticated;

-- ── C. Relatório de atendimento e privacidade por permissão ─────────────────────────────────────
insert into private.permission_catalog(code,module,area,label,actions,group_kinds,position,owner_only) values
 ('pastoral.history','people','Pessoas','Histórico de atendimento (sem conteúdo)','{view}','{}',16,false),
 ('pastoral.reports','people','Pessoas','Relatórios de atendimento','{view}','{}',16,false),
 ('pastoral.secret','people','Pessoas','Relatórios sigilosos','{view}','{}',16,false)
on conflict(code) do nothing;
update private.permission_catalog set label='Relatórios restritos' where code='pastoral.notes';

alter table public.people add column if not exists faith_decision text;
alter table public.people add column if not exists previous_church text;
alter table public.people add column if not exists followup_next date;
alter table public.people add column if not exists followup_started date;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='people_faith_decision_check') then
  alter table public.people add constraint people_faith_decision_check check(faith_decision is null or faith_decision in('none','here','reconciled','other_church'));
  alter table public.people add constraint people_previous_church_check check(previous_church is null or char_length(previous_church)<=120);
 end if;
end $$;
update public.people set faith_decision='here' where converted_at is not null and faith_decision is null;
update public.people set followup_started=coalesce(followup_started,converted_at) where converted_at is not null;

create table if not exists private.pastoral_reports(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid references public.organization_units(id) on delete set null,
 person_id uuid not null,
 appointment_id uuid unique references private.pastoral_appointments(id) on delete set null,
 kind text not null check(kind in('atendimento','acompanhamento')),
 contact text check(contact is null or contact in('ligacao','mensagem','visita','encontro','culto','outro')),
 author_person uuid references public.people(id) on delete set null,
 author_user uuid not null references auth.users(id),
 summary text not null check(length(btrim(summary)) between 3 and 8000),
 topics text[] not null default '{}' check(cardinality(topics)<=10 and topics <@ array['vida_espiritual','familia','casamento','financas','luto','saude','trabalho','ministerio','outro']),
 prayer text not null default '' check(length(prayer)<=2000),
 referrals text[] not null default '{}' check(cardinality(referrals)<=6 and referrals <@ array['celula','discipulado','outro_atendente','profissional','ministerio']),
 next_step date,
 privacy text not null default 'team' check(privacy in('team','restricted','secret')),
 addenda jsonb not null default '[]' check(jsonb_typeof(addenda)='array'),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete cascade
);
create index if not exists pastoral_reports_person on private.pastoral_reports(person_id,created_at desc);
create index if not exists pastoral_reports_author on private.pastoral_reports(author_user,created_at desc);
create table if not exists private.pastoral_report_reads(
 report_id uuid not null references private.pastoral_reports(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 read_at timestamptz not null default now()
);
create index if not exists pastoral_report_reads_report on private.pastoral_report_reads(report_id,read_at desc);
alter table private.pastoral_reports enable row level security;
alter table private.pastoral_report_reads enable row level security;
revoke all on private.pastoral_reports,private.pastoral_report_reads from public,anon,authenticated;

create or replace function private.report_readable(r private.pastoral_reports) returns boolean
language sql stable security definer set search_path to '' as $$
 select r.author_user=auth.uid()
  or (r.privacy='team' and private.can(r.organization_id,r.unit_id,'pastoral.reports','view'))
  or (r.privacy='restricted' and private.can(r.organization_id,r.unit_id,'pastoral.notes','view'))
  or (r.privacy='secret' and private.can(r.organization_id,r.unit_id,'pastoral.secret','view'))
$$;
revoke all on function private.report_readable(private.pastoral_reports) from public,anon,authenticated;

create or replace function private.history_visible(p_org uuid, p_unit uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select private.can(p_org,p_unit,'pastoral.history','view') or private.can(p_org,p_unit,'pastoral.reports','view')
  or private.can(p_org,p_unit,'pastoral.notes','view') or private.can(p_org,p_unit,'pastoral.secret','view')
$$;
revoke all on function private.history_visible(uuid,uuid) from public,anon,authenticated;

-- Anotações antigas viram relatórios "Restrito" (nada que era fechado fica aberto).
insert into private.pastoral_reports(organization_id,unit_id,person_id,appointment_id,kind,author_person,author_user,summary,privacy,created_at,updated_at)
select ap.organization_id,ap.unit_id,ap.person_id,ap.id,'atendimento',at.person_id,coalesce(pp.auth_user_id,ap.created_by),left(ap.notes,8000),'restricted',ap.updated_at,ap.updated_at
from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people pp on pp.id=at.person_id
where length(btrim(ap.notes))>=3 and coalesce(pp.auth_user_id,ap.created_by) is not null
on conflict(appointment_id) do nothing;

create or replace function private.report_row(r private.pastoral_reports, p_full boolean) returns jsonb
language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('id',r.id,'kind',r.kind,'contact',r.contact,'at',r.created_at,'person',r.person_id,
  'author',coalesce((select full_name from public.people where id=r.author_person),'Equipe'),'mine',r.author_user=auth.uid(),
  'privacy',r.privacy,'readable',p_full,'locked',r.created_at<now()-interval '7 days',
  'appointment',(select jsonb_build_object('kind',ap.kind,'mode',ap.mode,'startsAt',ap.starts_at) from private.pastoral_appointments ap where ap.id=r.appointment_id))
 ||case when p_full then jsonb_build_object('summary',r.summary,'topics',to_jsonb(r.topics),'prayer',r.prayer,'referrals',to_jsonb(r.referrals),'nextStep',r.next_step,'addenda',r.addenda) else '{}'::jsonb end
$$;
revoke all on function private.report_row(private.pastoral_reports,boolean) from public,anon,authenticated;

create or replace function public.pastoral_reports(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare actor uuid:=auth.uid(); me uuid; ap private.pastoral_appointments; r private.pastoral_reports; pid uuid; target public.people; v_privacy text; v_full boolean;
begin
 if actor is null or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>24000 then raise exception 'invalid_report' using errcode='22023'; end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and o.status in('active','trial')) then raise exception 'report_denied' using errcode='42501'; end if;
 select id into me from public.people where organization_id=p_org and auth_user_id=actor and status='active' order by (unit_id=p_unit) desc limit 1;

 if p_action='save' then
  v_privacy:=coalesce(nullif(p_data->>'privacy',''),'team');
  if length(btrim(coalesce(p_data->>'summary','')))<3 or v_privacy not in('team','restricted','secret')
   or (nullif(p_data->>'nextStep','') is not null and p_data->>'nextStep' !~ '^\d{4}-\d{2}-\d{2}$') then raise exception 'invalid_report' using errcode='22023'; end if;
  if coalesce(p_data->>'id','')<>'' then
   select * into r from private.pastoral_reports where id=(p_data->>'id')::uuid and organization_id=p_org for update;
   if r.id is null or r.author_user<>actor then raise exception 'report_denied' using errcode='42501'; end if;
   if r.created_at<now()-interval '7 days' then raise exception 'report_locked' using errcode='22023'; end if;
   update private.pastoral_reports set summary=btrim(p_data->>'summary'),topics=coalesce(array(select jsonb_array_elements_text(p_data->'topics')),'{}'),prayer=btrim(coalesce(p_data->>'prayer','')),
    referrals=coalesce(array(select jsonb_array_elements_text(p_data->'referrals')),'{}'),next_step=nullif(p_data->>'nextStep','')::date,privacy=v_privacy,
    contact=case when kind='acompanhamento' then coalesce(nullif(p_data->>'contact',''),contact) else contact end,updated_at=now() where id=r.id returning * into r;
  elsif coalesce(p_data->>'appointment','')<>'' then
   -- Atendimento: só quem atendeu, depois do horário; marca como realizado.
   select * into ap from private.pastoral_appointments where id=(p_data->>'appointment')::uuid and organization_id=p_org for update;
   if ap.id is null or not private.pastoral_self(ap.attendant_id) then raise exception 'report_denied' using errcode='42501'; end if;
   if ap.status not in('confirmed','done') or ap.starts_at>now() then raise exception 'report_too_early' using errcode='22023'; end if;
   if exists(select 1 from private.pastoral_reports where appointment_id=ap.id) then raise exception 'report_exists' using errcode='23505'; end if;
   insert into private.pastoral_reports(organization_id,unit_id,person_id,appointment_id,kind,author_person,author_user,summary,topics,prayer,referrals,next_step,privacy)
   values(p_org,ap.unit_id,ap.person_id,ap.id,'atendimento',me,actor,btrim(p_data->>'summary'),coalesce(array(select jsonb_array_elements_text(p_data->'topics')),'{}'),btrim(coalesce(p_data->>'prayer','')),
    coalesce(array(select jsonb_array_elements_text(p_data->'referrals')),'{}'),nullif(p_data->>'nextStep','')::date,v_privacy) returning * into r;
   update private.pastoral_appointments set status='done',version=version+1,updated_at=clock_timestamp() where id=ap.id and status='confirmed';
  else
   -- Integração Visitante: registro de contato do acompanhante (ou de quem gerencia a pessoa).
   pid:=(p_data->>'person')::uuid;
   select * into target from public.people where id=pid and organization_id=p_org;
   if target.id is null or not (target.followup_person=me or private.person_record_manage(pid)) then raise exception 'report_denied' using errcode='42501'; end if;
   if coalesce(p_data->>'contact','') not in('ligacao','mensagem','visita','encontro','culto','outro') then raise exception 'invalid_report' using errcode='22023'; end if;
   insert into private.pastoral_reports(organization_id,unit_id,person_id,kind,contact,author_person,author_user,summary,topics,prayer,referrals,next_step,privacy)
   values(p_org,coalesce(target.unit_id,p_unit),pid,'acompanhamento',p_data->>'contact',me,actor,btrim(p_data->>'summary'),coalesce(array(select jsonb_array_elements_text(p_data->'topics')),'{}'),
    btrim(coalesce(p_data->>'prayer','')),coalesce(array(select jsonb_array_elements_text(p_data->'referrals')),'{}'),nullif(p_data->>'nextStep','')::date,v_privacy) returning * into r;
   -- Só quem já está na Integração Visitante tem a etapa e o próximo contato atualizados.
   update public.people set followup_next=nullif(p_data->>'nextStep','')::date,followup_status=case when coalesce(followup_status,'pending')='pending' then 'contacted' else followup_status end,
    followup_at=now() where id=pid and followup_started is not null;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.report_saved','pastoral_report',r.id::text,jsonb_build_object('kind',r.kind,'privacy',r.privacy,'person',r.person_id));
  return jsonb_build_object('ok',true,'report',private.report_row(r,true));
 end if;

 if p_action='addendum' then
  select * into r from private.pastoral_reports where id=(p_data->>'id')::uuid and organization_id=p_org for update;
  if r.id is null or r.author_user<>actor then raise exception 'report_denied' using errcode='42501'; end if;
  if length(btrim(coalesce(p_data->>'text','')))<3 or length(p_data->>'text')>2000 or jsonb_array_length(r.addenda)>=30 then raise exception 'invalid_report' using errcode='22023'; end if;
  update private.pastoral_reports set addenda=addenda||jsonb_build_object('at',now(),'text',btrim(p_data->>'text')),updated_at=now() where id=r.id returning * into r;
  return jsonb_build_object('ok',true,'report',private.report_row(r,true));
 end if;

 if p_action='history' then
  pid:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=pid and organization_id=p_org) then raise exception 'invalid_report' using errcode='22023'; end if;
  if not (private.history_visible(p_org,p_unit) or exists(select 1 from private.pastoral_reports x where x.person_id=pid and x.author_user=actor)
    or exists(select 1 from public.people x where x.id=pid and x.followup_person=me)) then raise exception 'report_denied' using errcode='42501'; end if;
  -- Registra quem leu cada relatório (exceto o próprio autor).
  insert into private.pastoral_report_reads(report_id,user_id)
  select x.id,actor from private.pastoral_reports x where x.person_id=pid and x.author_user<>actor and private.report_readable(x);
  return jsonb_build_object('items',coalesce((select jsonb_agg(private.report_row(x,private.report_readable(x)) order by x.created_at desc) from private.pastoral_reports x
    where x.person_id=pid and (private.history_visible(p_org,p_unit) or x.author_user=actor or private.report_readable(x))),'[]'),
   'canSee',jsonb_build_object('team',private.can(p_org,p_unit,'pastoral.reports','view'),'restricted',private.can(p_org,p_unit,'pastoral.notes','view'),'secret',private.can(p_org,p_unit,'pastoral.secret','view')));
 end if;

 if p_action='reads' then
  select * into r from private.pastoral_reports where id=(p_data->>'id')::uuid and organization_id=p_org;
  if r.id is null or r.author_user<>actor then raise exception 'report_denied' using errcode='42501'; end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('at',x.read_at,'name',coalesce(p.full_name,'Usuário da equipe')) order by x.read_at desc)
   from private.pastoral_report_reads x left join public.people p on p.auth_user_id=x.user_id and p.organization_id=p_org where x.report_id=r.id),'[]'));
 end if;

 raise exception 'invalid_report' using errcode='22023';
end $function$;
revoke all on function public.pastoral_reports(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.pastoral_reports(uuid,uuid,text,jsonb) to authenticated;

-- ── D. Integração Visitante (antes "Novos convertidos") ──────────────────────────────────────────
create or replace function private.people_converts(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_today date; v_days int; p public.people; v_status text; v_follow uuid; v_date date; v_faith text;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if jsonb_typeof(coalesce(p_data,'{}'))<>'object' then raise exception 'invalid_convert' using errcode='22023'; end if;
 if not private.people_list_allowed(p_org,p_unit) then raise exception 'people_access_denied' using errcode='42501'; end if;
 v_today:=(now() at time zone coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo'))::date;
 if p_action='list' then
  v_days:=coalesce(nullif(p_data->>'days','')::int,90);
  if v_days not in (30,90,180,365) then raise exception 'invalid_convert' using errcode='22023'; end if;
  return (with list as (
    select pp.*,coalesce(pp.followup_started,pp.converted_at) started,
     (select string_agg(cc.name,', ' order by cc.name) from public.church_cell_participants c join public.church_cells cc on cc.id=c.cell_id
       where c.person_id=pp.id and c.status='active') cells,
     (select count(*) from private.pastoral_reports r where r.person_id=pp.id and r.kind='acompanhamento') contacts,
     (select max(r.created_at) from private.pastoral_reports r where r.person_id=pp.id and r.kind='acompanhamento') last_contact
    from public.people pp
    where pp.organization_id=p_org and pp.unit_id=p_unit and coalesce(pp.followup_started,pp.converted_at) is not null and pp.status not in ('rejected','deceased')
     and (coalesce(pp.followup_started,pp.converted_at)>=v_today-v_days or coalesce(pp.followup_status,'pending') in ('pending','contacted','in_cell')) and private.person_record_view(pp.id))
   select jsonb_build_object('today',v_today,
    'counts',jsonb_build_object('total',count(*),'pending',count(*) filter (where coalesce(followup_status,'pending')='pending'),
      'contacted',count(*) filter (where followup_status='contacted'),'in_cell',count(*) filter (where followup_status='in_cell'),
      'integrated',count(*) filter (where followup_status='integrated'),'stopped',count(*) filter (where followup_status='stopped'),
      'late',count(*) filter (where coalesce(followup_status,'pending')='pending' and started<v_today-7),
      'decisions',count(*) filter (where faith_decision in('here','reconciled') and converted_at>=v_today-30),
      'otherChurch',count(*) filter (where faith_decision='other_church'),
      'noContact',count(*) filter (where coalesce(followup_status,'pending') in('pending','contacted') and coalesce(last_contact::date,started)<v_today-7)),
    'items',coalesce(jsonb_agg(jsonb_build_object('person',l.id,'name',l.full_name,'phone',coalesce(l.phone,''),'convertedAt',l.converted_at,'startedAt',l.started,
      'days',v_today-l.started,'status',coalesce(l.followup_status,'pending'),'followup',l.followup_person,'faith',coalesce(l.faith_decision,'unknown'),'previousChurch',coalesce(l.previous_church,''),
      'followupName',(select f.full_name from public.people f where f.id=l.followup_person),'note',coalesce(l.followup_note,''),'next',l.followup_next,
      'contacts',l.contacts,'lastContact',l.last_contact,
      'cells',coalesce(l.cells,''),'journey',l.journey_status,'updatedAt',l.followup_at) order by l.started desc,l.full_name),'[]'::jsonb))
   from list l);
 end if;
 if p_action<>'save' then raise exception 'invalid_convert' using errcode='22023'; end if;
 if p_data-array['person','convertedAt','status','followup','note','faith','previousChurch','next','stop']<>'{}'::jsonb
  or coalesce(p_data->>'person','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or (nullif(p_data->>'followup','') is not null and p_data->>'followup' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (nullif(p_data->>'convertedAt','') is not null and p_data->>'convertedAt' !~ '^\d{4}-\d{2}-\d{2}$')
  or (nullif(p_data->>'next','') is not null and p_data->>'next' !~ '^\d{4}-\d{2}-\d{2}$')
  or (nullif(p_data->>'faith','') is not null and p_data->>'faith' not in('unknown','none','here','reconciled','other_church'))
  or length(coalesce(p_data->>'previousChurch',''))>120
  or length(coalesce(p_data->>'note',''))>500 then raise exception 'invalid_convert' using errcode='22023'; end if;
 select * into p from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if p.id is null or not private.person_record_manage(p.id) then raise exception 'people_access_denied' using errcode='42501'; end if;
 if coalesce((p_data->>'stop')::boolean,false) then
  update public.people set followup_started=null,followup_status=null,followup_person=null,followup_next=null,followup_at=now(),updated_at=now() where id=p.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'people.integration.removed','person',p.id::text,'{}');
  return jsonb_build_object('ok',true);
 end if;
 v_status:=coalesce(nullif(p_data->>'status',''),p.followup_status,'pending');
 if v_status not in ('pending','contacted','in_cell','integrated','stopped') then raise exception 'invalid_convert' using errcode='22023'; end if;
 v_faith:=case when p_data ? 'faith' then nullif(nullif(p_data->>'faith',''),'unknown') else p.faith_decision end;
 v_date:=case when p_data ? 'convertedAt' then nullif(p_data->>'convertedAt','')::date else p.converted_at end;
 if v_faith in('here','reconciled') and v_date is null then v_date:=v_today; end if;
 if v_faith is null or v_faith in('none','other_church') then v_date:=case when p_data ? 'convertedAt' then v_date else null end; end if;
 if v_date is not null and (v_date>v_today or v_date<v_today-36500) then raise exception 'invalid_convert' using errcode='22023'; end if;
 v_follow:=case when p_data ? 'followup' then nullif(p_data->>'followup','')::uuid else p.followup_person end;
 if v_follow is not null and (v_follow=p.id or not exists(select 1 from public.people f where f.id=v_follow and f.organization_id=p_org and f.status='active')) then
  raise exception 'invalid_convert' using errcode='22023'; end if;
 update public.people set converted_at=v_date,faith_decision=v_faith,
  previous_church=case when p_data ? 'previousChurch' then nullif(btrim(p_data->>'previousChurch'),'') else previous_church end,
  followup_started=coalesce(followup_started,v_today),followup_status=v_status,followup_person=v_follow,
  followup_next=case when p_data ? 'next' then nullif(p_data->>'next','')::date else followup_next end,
  followup_note=case when p_data ? 'note' then nullif(btrim(p_data->>'note'),'') else followup_note end,followup_at=now(),updated_at=now()
 where id=p.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'people.integration.updated','person',p.id::text,jsonb_build_object('status',v_status,'faith',v_faith,'followup',v_follow));
 return jsonb_build_object('ok',true);
end $$;

-- Acompanhante avisado no app; convites, aceites e lembretes de atendimento na caixa de notificações.
do $$ begin
 if to_regprocedure('private.member_inbox_before_agenda2(uuid,uuid)') is null then
  alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_agenda2;
 end if;
end $$;
create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from private.member_inbox_before_agenda2(p_org,p_unit) b where b.message_key not like 'pastoral:%:confirmed' or not exists(
   select 1 from private.pastoral_appointments x where 'pastoral:'||x.id::text||':confirmed'=b.message_key and x.origin='staff' and not x.member_ack)
  union all
  -- Convite do atendente aguardando aceite.
  select 'pastoral-invite:'||ap.id::text,'Convite para um atendimento',
   coalesce(p.full_name,'A liderança')||' convidou você para '||to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'DD/MM "às" HH24:MI')||'. Toque para aceitar ou recusar.',
   ap.created_at,'pastoral'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people p on p.id=at.person_id
  where ap.organization_id=p_org and ap.user_id=auth.uid() and ap.status='confirmed' and ap.origin='staff' and not ap.member_ack and ap.starts_at>now()
  union all
  -- Lembrete 24 h antes.
  select 'pastoral-remind:'||ap.id::text,'Atendimento amanhã',
   'Com '||coalesce(p.full_name,'a liderança')||' às '||to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'HH24:MI')||'.',
   ap.starts_at-interval '24 hours','pastoral'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people p on p.id=at.person_id
  where ap.organization_id=p_org and ap.user_id=auth.uid() and ap.status='confirmed' and ap.member_ack and now() between ap.starts_at-interval '24 hours' and ap.starts_at
  union all
  -- Para quem atende: o membro aceitou, recusou ou pediu outro horário.
  select 'pastoral-att:'||ap.id::text||':'||ap.status||':'||ap.member_ack::text,
   case when ap.status='confirmed' then split_part(m.full_name,' ',1)||' aceitou o atendimento' else split_part(m.full_name,' ',1)||' não poderá ir' end,
   to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'DD/MM "às" HH24:MI')||case when ap.status='cancelled' and ap.decided_reason<>'' then ' · '||ap.decided_reason else '' end,
   ap.updated_at,'pastoralTeam'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people att on att.id=at.person_id join public.people m on m.id=ap.person_id
  where ap.organization_id=p_org and att.auth_user_id=auth.uid() and ap.origin='staff' and ap.updated_at>now()-interval '30 days'
   and ((ap.status='confirmed' and ap.member_ack and ap.updated_at>ap.created_at) or (ap.status='cancelled' and ap.decided_reason like 'O membro%'))
  union all
  -- Para o acompanhante da Integração Visitante.
  select 'integration:'||v.id::text||':'||coalesce(v.followup_person::text,''),'Você vai acompanhar '||split_part(v.full_name,' ',1),
   'Faça o primeiro contato e registre no app em Integração Visitante.',v.followup_at,'integration'::text,v.id
  from public.people v join public.people me on me.id=v.followup_person
  where v.organization_id=p_org and me.auth_user_id=auth.uid() and v.followup_started is not null and coalesce(v.followup_status,'pending') in('pending','contacted') and v.followup_at>now()-interval '30 days'
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;

-- ── App: Integração Visitante do acompanhante e calendário de quem atende ───────────────────────
create or replace function public.member_followups(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare actor uuid:=auth.uid(); me uuid; v public.people; tz text;
begin
 if actor is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_followup' using errcode='22023'; end if;
 select id into me from public.people where organization_id=p_org and auth_user_id=actor and status='active' order by (unit_id=p_unit) desc limit 1;
 if me is null then return jsonb_build_object('items','[]'::jsonb,'agenda','[]'::jsonb); end if;
 tz:=coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo');
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('person',x.id,'name',x.full_name,'phone',coalesce(x.phone,''),'status',coalesce(x.followup_status,'pending'),
    'faith',coalesce(x.faith_decision,'unknown'),'previousChurch',coalesce(x.previous_church,''),'next',x.followup_next,'startedAt',x.followup_started,'journey',x.journey_status,
    'contacts',(select count(*) from private.pastoral_reports r where r.person_id=x.id and r.kind='acompanhamento'),
    'last',(select max(r.created_at) from private.pastoral_reports r where r.person_id=x.id and r.kind='acompanhamento')) order by x.followup_next nulls last,x.full_name)
   from public.people x where x.organization_id=p_org and x.followup_person=me and x.followup_started is not null and coalesce(x.followup_status,'pending') not in('integrated','stopped')),'[]'));
 end if;
 if p_action='status' then
  select * into v from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and followup_person=me for update;
  if v.id is null then raise exception 'followup_denied' using errcode='42501'; end if;
  if coalesce(p_data->>'status','') not in('pending','contacted','in_cell','integrated','stopped') then raise exception 'invalid_followup' using errcode='22023'; end if;
  update public.people set followup_status=p_data->>'status',followup_at=now() where id=v.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'people.integration.app_status','person',v.id::text,jsonb_build_object('status',p_data->>'status'));
  return jsonb_build_object('ok',true);
 end if;
 if p_action='calendar' then
  -- Agenda do próprio usuário: atendimentos (como atendente ou atendido), próximos contatos e relatórios pendentes.
  return jsonb_build_object('timezone',tz,'items',coalesce((select jsonb_agg(e order by e->>'at') from (
   select jsonb_build_object('type',case when ap.status='confirmed' and ap.origin='staff' and not ap.member_ack then 'invite' when ap.status='requested' then 'request' else 'appointment' end,
    'id',ap.id,'at',ap.starts_at,'end',ap.ends_at,'title',m.full_name,'detail',ap.kind,'mode',ap.mode,'role','attendant') e
   from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people m on m.id=ap.person_id
   where at.person_id=me and ap.status in('requested','confirmed') and ap.starts_at between now()-interval '1 day' and now()+interval '60 days'
   union all
   select jsonb_build_object('type','report','id',ap.id,'at',ap.starts_at,'end',ap.ends_at,'title',m.full_name,'detail',ap.kind,'mode',ap.mode,'role','attendant')
   from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people m on m.id=ap.person_id
   where at.person_id=me and ap.status in('confirmed','done') and ap.starts_at<now() and ap.starts_at>now()-interval '30 days' and not exists(select 1 from private.pastoral_reports r where r.appointment_id=ap.id)
   union all
   select jsonb_build_object('type','attended','id',ap.id,'at',ap.starts_at,'end',ap.ends_at,'title',coalesce(pp.full_name,'Liderança'),'detail',ap.kind,'mode',ap.mode,'role','person')
   from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people pp on pp.id=at.person_id
   where ap.person_id=me and ap.status='confirmed' and ap.starts_at between now()-interval '1 day' and now()+interval '60 days'
   union all
   select jsonb_build_object('type','followup','id',x.id,'at',(x.followup_next+time '09:00') at time zone tz,'end',null,'title',x.full_name,'detail','Contato de integração','mode',null,'role','followup')
   from public.people x where x.organization_id=p_org and x.followup_person=me and x.followup_next is not null and x.followup_next between current_date-7 and current_date+60
    and coalesce(x.followup_status,'pending') not in('integrated','stopped')
  ) y(e)),'[]'));
 end if;
 raise exception 'invalid_followup' using errcode='22023';
end $function$;
revoke all on function public.member_followups(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.member_followups(uuid,uuid,text,jsonb) to authenticated;

-- Atendimento informa se já tem relatório (calendário: "relatório pendente").
do $$ declare d text; begin
 d:=pg_get_functiondef('private.pastoral_row(private.pastoral_appointments,boolean)'::regprocedure);
 if position('''reported''' in d)=0 then
  if position($x$jsonb_build_object('id',ap.id,$x$ in d)=0 then raise exception 'pastoral_row: trecho não encontrado'; end if;
  execute replace(d,$x$jsonb_build_object('id',ap.id,$x$,$x$jsonb_build_object('id',ap.id,'reported',exists(select 1 from private.pastoral_reports rr where rr.appointment_id=ap.id),$x$);
 end if;
end $$;
