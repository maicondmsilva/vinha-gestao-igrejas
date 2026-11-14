-- Agenda pastoral · quem atende ajusta pelo app a própria confirmação automática (liga/desliga) e as durações aceitas.
create or replace function private.pastoral_self_settings(p_org uuid, p_unit uuid, p_attendant uuid, p_auto boolean, p_durations smallint[], p_version integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare a private.pastoral_attendants; v integer;
begin
 select * into a from private.pastoral_attendants where id=p_attendant and organization_id=p_org and unit_id=p_unit for update;
 if a.id is null or not private.pastoral_self(a.id) then raise exception 'pastoral_denied' using errcode='42501';end if;
 if p_auto is null or p_durations is null or cardinality(p_durations) not between 1 and 6 or not p_durations<@array[15,30,45,60,90,120]::smallint[] then raise exception 'invalid_pastoral' using errcode='22023';end if;
 if a.version<>p_version then raise exception 'pastoral_changed' using errcode='40001';end if;
 update private.pastoral_attendants set auto_confirm=p_auto,durations=(select array_agg(distinct d order by d) from unnest(p_durations) d),version=version+1,updated_at=clock_timestamp() where id=a.id returning version into v;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'pastoral.self_settings','pastoral_attendant',a.id::text,jsonb_build_object('unit_id',p_unit,'auto',p_auto));
 return jsonb_build_object('ok',true,'id',a.id,'version',v);
end $function$;
revoke all on function private.pastoral_self_settings(uuid,uuid,uuid,boolean,smallint[],integer) from public,anon,authenticated;
create or replace function public.pastoral_self_settings(p_org uuid, p_unit uuid, p_attendant uuid, p_auto boolean, p_durations smallint[], p_version integer) returns jsonb
language sql security definer set search_path to '' as $$ select private.pastoral_self_settings(p_org,p_unit,p_attendant,p_auto,p_durations,p_version) $$;
revoke all on function public.pastoral_self_settings(uuid,uuid,uuid,boolean,smallint[],integer) from public,anon;
grant execute on function public.pastoral_self_settings(uuid,uuid,uuid,boolean,smallint[],integer) to authenticated;
