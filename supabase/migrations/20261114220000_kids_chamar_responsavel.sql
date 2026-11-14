-- Kids · chamar o responsável: a equipe da sala (Vinha Equipe ou painel) chama os responsáveis de uma criança presente.
-- O responsável recebe o aviso na caixa de notificações do app (e por push quando o Firebase estiver ativo) e responde.

create table if not exists private.kids_guardian_calls(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 attendance_id uuid not null,
 profile_id uuid not null,
 session_id uuid not null,
 group_id uuid,
 reason text not null check(reason in('diaper','crying','health','pickup','other')),
 message text not null default '' check(length(message)<=200),
 created_by uuid not null,
 created_at timestamptz not null default now(),
 answer text check(answer in('coming','ok')),
 answered_at timestamptz,
 answered_by uuid
);
create index if not exists kids_guardian_calls_session on private.kids_guardian_calls(session_id,created_at desc);
create index if not exists kids_guardian_calls_profile on private.kids_guardian_calls(profile_id,created_at desc);
alter table private.kids_guardian_calls enable row level security;
revoke all on private.kids_guardian_calls from public,anon,authenticated;

create or replace function private.kids_call_reason(p text) returns text language sql immutable set search_path to '' as $$
 select case p when 'diaper' then 'troca de fralda' when 'crying' then 'está chorando e pediu você' when 'health' then 'um cuidado de saúde' when 'pickup' then 'buscar a criança agora' else 'falar com você' end
$$;

-- Equipe: chamar e acompanhar respostas.
create or replace function private.kids_call(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare a private.kids_attendance; c private.kids_guardian_calls; v_session uuid;
begin
 if auth.uid() is null or p_action not in('call','list') or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_kids_call' using errcode='22023';end if;
 if p_action='list' then
  v_session:=nullif(p_data->>'session','')::uuid;
  if v_session is null or not private.kids_op_allowed(p_org,p_unit,v_session,'read') then raise exception 'kids_access_denied' using errcode='42501';end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'attendance',k.attendance_id,'child',p.full_name,'reason',k.reason,'message',k.message,'createdAt',k.created_at,'answer',k.answer,'answeredAt',k.answered_at) order by k.created_at desc)
   from private.kids_guardian_calls k join private.kids_profiles kp on kp.id=k.profile_id join public.people p on p.id=kp.person_id
   where k.organization_id=p_org and k.unit_id=p_unit and k.session_id=v_session and k.created_at>now()-interval '12 hours'),'[]'::jsonb));
 end if;
 if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or p_data->>'reason' not in('diaper','crying','health','pickup','other') or length(coalesce(p_data->>'message',''))>200 then raise exception 'invalid_kids_call' using errcode='22023';end if;
 select * into c from private.kids_guardian_calls where id=(p_data->>'id')::uuid;
 if c.id is not null then return jsonb_build_object('ok',true,'id',c.id);end if;
 select * into a from private.kids_attendance where id=nullif(p_data->>'attendance','')::uuid and organization_id=p_org and unit_id=p_unit;
 if a.id is null or a.checked_out_at is not null then raise exception 'invalid_kids_call' using errcode='22023';end if;
 if not private.kids_op_allowed(p_org,p_unit,a.session_id,'read',a.group_id) then raise exception 'kids_access_denied' using errcode='42501';end if;
 if exists(select 1 from private.kids_guardian_calls where attendance_id=a.id and created_at>now()-interval '2 minutes' and answer is null) then raise exception 'kids_call_recent' using errcode='54000';end if;
 insert into private.kids_guardian_calls(id,organization_id,unit_id,attendance_id,profile_id,session_id,group_id,reason,message,created_by)
  values((p_data->>'id')::uuid,p_org,p_unit,a.id,a.profile_id,a.session_id,a.group_id,p_data->>'reason',btrim(coalesce(p_data->>'message','')),auth.uid());
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'kids.guardian_called','kids_attendance',a.id::text,jsonb_build_object('unit_id',p_unit,'reason',p_data->>'reason'));
 return jsonb_build_object('ok',true,'id',(p_data->>'id')::uuid);
end $function$;
revoke all on function private.kids_call(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.kids_call(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.kids_call(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.kids_call(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.kids_call(uuid,uuid,text,jsonb) to authenticated;

-- Responsável: ver chamados das próprias crianças (últimas 12 h) e responder.
create or replace function private.member_kids_call(p_org uuid, p_action text, p_id uuid, p_answer text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); c private.kids_guardian_calls;
begin
 if uid is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'child',split_part(p.full_name,' ',1),'reason',k.reason,'reasonText',private.kids_call_reason(k.reason),'message',k.message,'createdAt',k.created_at,'answer',k.answer) order by k.created_at desc)
   from private.kids_guardian_calls k join private.kids_profiles kp on kp.id=k.profile_id join public.people p on p.id=kp.person_id
   where k.organization_id=p_org and k.created_at>now()-interval '12 hours'
    and exists(select 1 from private.kids_guardians g join public.people gp on gp.id=g.person_id where g.profile_id=k.profile_id and g.status='approved' and gp.auth_user_id=uid)),'[]'::jsonb));
 elsif p_action='answer' then
  if p_answer not in('coming','ok') then raise exception 'invalid_kids_call' using errcode='22023';end if;
  select k.* into c from private.kids_guardian_calls k where k.id=p_id and k.organization_id=p_org
   and exists(select 1 from private.kids_guardians g join public.people gp on gp.id=g.person_id where g.profile_id=k.profile_id and g.status='approved' and gp.auth_user_id=uid) for update;
  if c.id is null then raise exception 'kids_access_denied' using errcode='42501';end if;
  update private.kids_guardian_calls set answer=p_answer,answered_at=clock_timestamp(),answered_by=uid where id=c.id;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_kids_call' using errcode='22023';
end $function$;
revoke all on function private.member_kids_call(uuid,text,uuid,text) from public,anon,authenticated;
create or replace function public.member_kids_call(p_org uuid, p_action text, p_id uuid default null, p_answer text default null) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_kids_call(p_org,p_action,p_id,p_answer) $$;
revoke all on function public.member_kids_call(uuid,text,uuid,text) from public,anon;
grant execute on function public.member_kids_call(uuid,text,uuid,text) to authenticated;

-- Caixa de notificações do responsável.
do $$ begin
 if to_regprocedure('private.member_inbox_before_kids_calls(uuid,uuid)') is null then
  alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_kids_calls;
 end if;
end $$;
create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from private.member_inbox_before_kids_calls(p_org,p_unit)
  union all
  select 'kids-call:'||k.id::text,'Sala Kids: chamado para '||split_part(p.full_name,' ',1),
   'A equipe chamou você: '||private.kids_call_reason(k.reason)||case when k.message<>'' then ' — '||k.message else '' end||'. Toque para responder.',
   k.created_at,'kids'::text,k.id
  from private.kids_guardian_calls k join private.kids_profiles kp on kp.id=k.profile_id join public.people p on p.id=kp.person_id
  where k.organization_id=p_org and k.created_at>now()-interval '12 hours'
   and exists(select 1 from private.kids_guardians g join public.people gp on gp.id=g.person_id where g.profile_id=k.profile_id and g.status='approved' and gp.auth_user_id=auth.uid())
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;
