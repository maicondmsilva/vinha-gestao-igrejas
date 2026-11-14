-- Telão Kids: o Holyrics mostra um alerta por vez. Quando um responsável responde e ainda há outro chamado
-- no telão (enviado ao telão, sem resposta, do último minuto), mostra de novo esse outro em vez de apagar a faixa.
create or replace function private.kids_projector_alert_text(p_attendance uuid) returns text
language sql stable security definer set search_path to '' as $$
 select 'Kids: responsável pela criança nº '||coalesce(a.tag_number::text,'?')||', compareça à '||coalesce(nullif(r.name,''),'sala Kids')
 from private.kids_attendance a left join private.kids_session_rooms g on g.id=a.group_id left join private.kids_rooms r on r.id=g.room_id where a.id=p_attendance
$$;
revoke all on function private.kids_projector_alert_text(uuid) from public,anon,authenticated;

create or replace function private.kids_call_projector() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare other private.kids_guardian_calls;
begin
 if tg_op='INSERT' and new.projector then
  perform private.kids_projector_send(new.organization_id,new.unit_id,new.id,'alert',jsonb_build_object(
   'text',coalesce(private.kids_projector_alert_text(new.attendance_id),'Kids: responsável, compareça à sala Kids'),'show',true,'close_after_seconds',60));
 elsif tg_op='UPDATE' and new.projector and old.answer is null and new.answer is not null then
  select * into other from private.kids_guardian_calls k where k.unit_id=new.unit_id and k.id<>new.id and k.projector and k.answer is null
   and k.created_at>now()-interval '60 seconds' and exists(select 1 from private.kids_projector_log l where l.call_id=k.id and l.action='alert') order by k.created_at desc limit 1;
  if other.id is not null then
   perform private.kids_projector_send(other.organization_id,other.unit_id,other.id,'alert',jsonb_build_object(
    'text',coalesce(private.kids_projector_alert_text(other.attendance_id),'Kids: responsável, compareça à sala Kids'),'show',true,
    'close_after_seconds',greatest(10,60-extract(epoch from now()-other.created_at)::int)));
  else
   perform private.kids_projector_send(new.organization_id,new.unit_id,new.id,'hide',jsonb_build_object('text','','show',false));
  end if;
 end if;
 return new;
end $function$;
revoke all on function private.kids_call_projector() from public,anon,authenticated;
