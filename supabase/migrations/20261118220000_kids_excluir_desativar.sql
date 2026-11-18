-- Kids: excluir quando não há registros; quando há (entradas, reservas, histórico), DESATIVAR em vez de bloquear.
-- Sala/turma desativada: some das próximas datas e das repetições, mas o histórico continua nos relatórios.
-- Sessão (data) com registros: em preparação vira cancelada; encerrada/cancelada é arquivada (sai das listas,
-- continua nos relatórios). Sessão aberta precisa ser encerrada antes.
begin;
set local lock_timeout='5s';

create or replace function pg_temp.swap(p regprocedure, a text, b text) returns void language plpgsql as $f$
declare d text:=pg_get_functiondef(p);
begin
 if position(a in d)=0 then raise exception 'trecho não encontrado em %: %', p, left(a,90); end if;
 execute replace(d,a,b);
end $f$;

alter table private.kids_sessions add column if not exists archived_at timestamptz;

create or replace function private.kids_setup_deactivate(p_org uuid, p_unit uuid, p_action text, p_id uuid) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare s private.kids_sessions; tz text;
begin
 if p_action in('room_deactivate','class_deactivate') then
  if p_action='room_deactivate' then
   perform 1 from private.kids_rooms where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  else
   perform 1 from private.kids_classes where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  end if;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  -- Em uso numa sessão aberta agora: encerre a sessão antes.
  if exists(select 1 from private.kids_session_rooms g join private.kids_sessions x on x.id=g.session_id
    where x.status='open' and (p_action='room_deactivate' and g.room_id=p_id or p_action='class_deactivate' and g.class_id=p_id)) then
   raise exception 'kids_in_open_session' using errcode='40001';
  end if;
  -- Sai das próximas datas em preparação que ainda não têm entrada nem reserva nessa sala.
  delete from private.kids_assignments z using private.kids_session_rooms g, private.kids_sessions x
   where z.group_id=g.id and x.id=g.session_id and x.status='draft' and x.unit_id=p_unit
   and (p_action='room_deactivate' and g.room_id=p_id or p_action='class_deactivate' and g.class_id=p_id)
   and not exists(select 1 from private.kids_attendance a where a.group_id=g.id)
   and not exists(select 1 from private.kids_member_reservations r where r.group_id=g.id);
  delete from private.kids_session_rooms g using private.kids_sessions x
   where x.id=g.session_id and x.status='draft' and x.unit_id=p_unit
   and (p_action='room_deactivate' and g.room_id=p_id or p_action='class_deactivate' and g.class_id=p_id)
   and not exists(select 1 from private.kids_attendance a where a.group_id=g.id)
   and not exists(select 1 from private.kids_member_reservations r where r.group_id=g.id);
  -- E das repetições, para não voltar nas próximas datas.
  update private.kids_session_series set rooms=coalesce((select jsonb_agg(x) from jsonb_array_elements(rooms) x
    where x->>(case when p_action='room_deactivate' then 'roomId' else 'classId' end)<>p_id::text),'[]'::jsonb),version=version+1
   where unit_id=p_unit and rooms @> jsonb_build_array(jsonb_build_object(case when p_action='room_deactivate' then 'roomId' else 'classId' end,p_id::text));
  if p_action='room_deactivate' then
   update private.kids_rooms set active=false,version=version+1 where id=p_id;
  else
   update private.kids_classes set active=false,version=version+1 where id=p_id;
  end if;
 elsif p_action='session_archive' then
  select * into s from private.kids_sessions where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  if s.status='open' then raise exception 'kids_session_open' using errcode='40001';end if;
  update private.kids_sessions set status=case when status='draft' then 'cancelled' else status end,archived_at=clock_timestamp(),version=version+1 where id=p_id;
  -- Data de repetição: não é criada de novo.
  if s.series_id is not null then
   tz:=private.unit_timezone(p_unit);
   update private.kids_session_series set skip_dates=array(select distinct x from unnest(skip_dates||(s.starts_at at time zone tz)::date) x),version=version+1 where id=s.series_id;
  end if;
 else
  raise exception 'kids_invalid' using errcode='22023';
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'kids.'||p_action,'kids',p_id);
 return jsonb_build_object('ok',true,'deactivated',true);
end $$;
revoke all on function private.kids_setup_deactivate(uuid,uuid,text,uuid) from public,anon,authenticated;

-- Liga as novas ações ao kids_setup (que já confere quem configura a igreja).
select pg_temp.swap('private.kids_setup(uuid,uuid,text,jsonb)',
 $$ elsif p_action in('room_delete','class_delete','session_delete') then$$,
 $$ elsif p_action in('room_deactivate','class_deactivate','session_archive') then
  return private.kids_setup_deactivate(p_org,p_unit,p_action,nullif(p_data->>'id','')::uuid);
 elsif p_action in('room_delete','class_delete','session_delete') then$$);

-- Sessões arquivadas saem da lista e da escolha automática da página Hoje (seguem nos relatórios).
select pg_temp.swap('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)',
 $$if sid is null then select id into sid from private.kids_sessions s where organization_id=p_org and unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,s.id) order by$$,
 $$if sid is null then select id into sid from private.kids_sessions s where organization_id=p_org and unit_id=p_unit and s.archived_at is null and private.kids_op_allowed(p_org,p_unit,s.id) order by$$);
select pg_temp.swap('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)',
 $$from (select * from private.kids_sessions s where organization_id=p_org and unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,s.id) order by (id=sid) desc$$,
 $$from (select * from private.kids_sessions s where organization_id=p_org and unit_id=p_unit and (s.archived_at is null or s.id=sid) and private.kids_op_allowed(p_org,p_unit,s.id) order by (id=sid) desc$$);
commit;
