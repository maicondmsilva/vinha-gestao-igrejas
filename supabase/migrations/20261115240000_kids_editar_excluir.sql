-- Kids · editar e excluir salas, turmas e sessões sem perder histórico.
-- Uma sessão "tem lançamentos" quando já teve entrada, reserva de família ou registro de custódia.
-- Sala ou turma com lançamentos (usada numa sessão com lançamentos) não é excluída: só desativada.

create or replace function private.kids_session_has_records(p_session uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select exists(select 1 from private.kids_attendance where session_id=p_session)
  or exists(select 1 from private.kids_member_reservations where session_id=p_session)
  or exists(select 1 from private.kids_custody_events where session_id=p_session)
$$;
revoke all on function private.kids_session_has_records(uuid) from public,anon,authenticated;

create or replace function private.kids_room_has_records(p_room uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select exists(select 1 from private.kids_session_rooms g where g.room_id=p_room and private.kids_session_has_records(g.session_id))
$$;
revoke all on function private.kids_room_has_records(uuid) from public,anon,authenticated;

create or replace function private.kids_class_has_records(p_class uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select exists(select 1 from private.kids_session_rooms g where g.class_id=p_class and private.kids_session_has_records(g.session_id))
$$;
revoke all on function private.kids_class_has_records(uuid) from public,anon,authenticated;

-- Exclusão (somente sem lançamentos). Retira também as salas montadas em sessões ainda vazias e das repetições.
create or replace function private.kids_setup_delete(p_org uuid,p_unit uuid,p_action text,p_id uuid) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare s private.kids_sessions; tz text;
begin
 if p_action='room_delete' then
  perform 1 from private.kids_rooms where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  if private.kids_room_has_records(p_id) then raise exception 'kids_has_records' using errcode='40001';end if;
  delete from private.kids_assignments where group_id in(select id from private.kids_session_rooms where room_id=p_id);
  delete from private.kids_session_rooms where room_id=p_id;
  update private.kids_session_series set rooms=coalesce((select jsonb_agg(x) from jsonb_array_elements(rooms) x where x->>'roomId'<>p_id::text),'[]'::jsonb),version=version+1
   where unit_id=p_unit and rooms @> jsonb_build_array(jsonb_build_object('roomId',p_id::text));
  delete from private.kids_rooms where id=p_id;
 elsif p_action='class_delete' then
  perform 1 from private.kids_classes where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  if private.kids_class_has_records(p_id) then raise exception 'kids_has_records' using errcode='40001';end if;
  delete from private.kids_assignments where group_id in(select id from private.kids_session_rooms where class_id=p_id);
  delete from private.kids_session_rooms where class_id=p_id;
  update private.kids_session_series set rooms=coalesce((select jsonb_agg(x) from jsonb_array_elements(rooms) x where x->>'classId'<>p_id::text),'[]'::jsonb),version=version+1
   where unit_id=p_unit and rooms @> jsonb_build_array(jsonb_build_object('classId',p_id::text));
  delete from private.kids_classes where id=p_id;
 elsif p_action='session_delete' then
  select * into s from private.kids_sessions where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'kids_not_found' using errcode='P0002';end if;
  if private.kids_session_has_records(p_id) then raise exception 'kids_has_records' using errcode='40001';end if;
  delete from private.kids_assignments where session_id=p_id;
  delete from private.kids_session_rooms where session_id=p_id;
  delete from private.kids_sessions where id=p_id;
  -- Sessão criada por repetição: pula essa data para não ser criada de novo.
  if s.series_id is not null then
   tz:=private.unit_timezone(p_unit);
   update private.kids_session_series set skip_dates=array(select distinct x from unnest(skip_dates||(s.starts_at at time zone tz)::date) x),version=version+1 where id=s.series_id;
  end if;
 else raise exception 'kids_invalid' using errcode='22023';
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'kids.'||p_action,'kids',p_id);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.kids_setup_delete(uuid,uuid,text,uuid) from public,anon,authenticated;

do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_setup(uuid,uuid,text,jsonb)'::regprocedure);
 if position('kids_setup_delete' in d)=0 then
  if position('''active'',r.active,''version'',r.version)' in d)=0 or position('''active'',c.active,''version'',c.version)' in d)=0
   or position('''bookableFrom'',s.bookable_from,''version'',s.version,' in d)=0 or position(' elsif p_action=''series_delete'' then' in d)=0 then raise exception 'kids_setup: trechos não encontrados';end if;
  d:=replace(d,'''active'',r.active,''version'',r.version)','''active'',r.active,''version'',r.version,''locked'',private.kids_room_has_records(r.id))');
  d:=replace(d,'''active'',c.active,''version'',c.version)','''active'',c.active,''version'',c.version,''locked'',private.kids_class_has_records(c.id))');
  d:=replace(d,'''bookableFrom'',s.bookable_from,''version'',s.version,','''bookableFrom'',s.bookable_from,''version'',s.version,''locked'',private.kids_session_has_records(s.id),');
  d:=replace(d,' elsif p_action=''series_delete'' then',' elsif p_action in(''room_delete'',''class_delete'',''session_delete'') then
  return private.kids_setup_delete(p_org,p_unit,p_action,nullif(p_data->>''id'','''')::uuid);
 elsif p_action=''series_delete'' then');
  execute d;
 end if;
end $$;
