-- Escalas · quadro de montagem: linhas = funções (com as vagas), colunas = cultos do período.
-- Reaproveita as regras existentes: qualificação, conflitos (private.scale_conflicts),
-- preencher vaga de culto publicado e publicar (private.scale_operations).

create or replace function private.scale_board(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
 v_from date; v_to date; v_team uuid; s private.scale_services; q private.scale_positions; r private.scale_roles;
 v_member uuid; v_ordinal int; conflicts text[]; v jsonb; sid text; published jsonb:='[]'::jsonb; failed jsonb:='[]'::jsonb;
 ids uuid[];
begin
 perform set_config('vinha.scale_ctx','schedules',true);
 perform private.require_confirmed_self_service_email();
 p_data:=coalesce(p_data,'{}'::jsonb);
 if p_action is null or p_action not in ('view','assign','publish') or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>16000 then
  raise exception 'scale_input' using errcode='22023';
 end if;
 perform 1 from public.organizations where id=p_org and status in ('active','trial');
 if not found then raise exception 'scale_access_denied' using errcode='42501'; end if;
 v_team:=nullif(p_data->>'team','')::uuid;
 if not private.scale_allowed(p_org,p_unit,v_team,'read') then raise exception 'scale_access_denied' using errcode='42501'; end if;

 if p_action='view' then
  v_from:=(p_data->>'from')::date; v_to:=(p_data->>'to')::date;
  if v_from is null or v_to is null or v_to<v_from or v_to-v_from>62 then raise exception 'scale_input' using errcode='22023'; end if;
  select coalesce(array_agg(x.id order by x.starts_at,x.id),'{}') into ids from (
   select sv.id,sv.starts_at from private.scale_services sv
   where sv.organization_id=p_org and sv.unit_id=p_unit and sv.status in ('draft','published')
    and (sv.starts_at at time zone sv.timezone)::date between v_from and v_to
    and exists(select 1 from private.scale_positions pq where pq.service_id=sv.id and private.scale_allowed(p_org,p_unit,pq.team_id,'read') and (v_team is null or pq.team_id=v_team))
   order by sv.starts_at,sv.id limit 31) x;
  return jsonb_build_object(
   'services',coalesce((select jsonb_agg(jsonb_build_object('id',sv.id,'title',sv.title,'startsAt',sv.starts_at,'timezone',sv.timezone,'status',sv.status,'version',sv.version,
     'started',sv.arrival_at<=now(),'canPublish',sv.status='draft' and sv.arrival_at>now() and private.scale_service_allowed(p_org,p_unit,sv.id,'publish'),
     'open',(select count(*) from private.scale_positions pq where pq.service_id=sv.id and pq.member_id is null and (v_team is null or pq.team_id=v_team))) order by sv.starts_at,sv.id)
    from private.scale_services sv where sv.id=any(ids)),'[]'::jsonb),
   'rows',coalesce((select jsonb_agg(jsonb_build_object('team',x.team_id,'teamName',x.team_name,'role',x.role_id,'roleName',x.role_name,'ordinal',x.ordinal,
     'canAssign',private.scale_allowed(p_org,p_unit,x.team_id,'assign')) order by x.team_name,x.role_name,x.ordinal)
    from (select distinct pq.team_id,t.name team_name,pq.role_id,rr.name role_name,pq.ordinal from private.scale_positions pq
     join private.scale_teams t on t.id=pq.team_id join private.scale_roles rr on rr.id=pq.role_id
     where pq.service_id=any(ids) and private.scale_allowed(p_org,p_unit,pq.team_id,'read') and (v_team is null or pq.team_id=v_team)) x),'[]'::jsonb),
   'cells',coalesce((select jsonb_agg(jsonb_build_object('service',pq.service_id,'team',pq.team_id,'role',pq.role_id,'ordinal',pq.ordinal,'member',pq.member_id,'name',pp.full_name,
     'conflicts',to_jsonb(private.scale_conflicts(pq.service_id,pq.role_id,pq.member_id,pq.ordinal)),
     'response',(select i.response from private.scale_invites i where i.service_id=pq.service_id and i.role_id=pq.role_id and i.ordinal=pq.ordinal and i.active order by i.invited_at desc limit 1)))
    from private.scale_positions pq left join private.scale_members m on m.id=pq.member_id left join public.people pp on pp.id=m.person_id
    where pq.service_id=any(ids) and private.scale_allowed(p_org,p_unit,pq.team_id,'read') and (v_team is null or pq.team_id=v_team)),'[]'::jsonb));
 end if;

 if p_action='assign' then
  select * into s from private.scale_services where id=nullif(p_data->>'service','')::uuid and organization_id=p_org and unit_id=p_unit for update;
  if s.id is null then raise exception 'scale_access_denied' using errcode='42501'; end if;
  select * into r from private.scale_roles where id=nullif(p_data->>'role','')::uuid and organization_id=p_org and unit_id=p_unit;
  if r.id is null or not private.scale_allowed(p_org,p_unit,r.team_id,'assign') then raise exception 'scale_access_denied' using errcode='42501'; end if;
  v_ordinal:=(p_data->>'ordinal')::int; v_member:=nullif(p_data->>'member','')::uuid;
  select * into q from private.scale_positions where service_id=s.id and role_id=r.id and ordinal=v_ordinal for update;
  if q.service_id is null then raise exception 'scale_role_invalid' using errcode='22023'; end if;
  if s.version is distinct from (p_data->>'version')::int then raise exception 'scale_changed' using errcode='40001'; end if;
  if s.arrival_at<=now() or s.status not in ('draft','published') then raise exception 'scale_state' using errcode='22023'; end if;
  if s.status='published' then
   -- Culto publicado: só preenche vaga aberta, pelas mesmas regras da tela da escala (gera convite).
   if v_member is null or q.member_id is not null then raise exception 'scale_state' using errcode='22023'; end if;
   v:=private.scale_operations(p_org,p_unit,'fill',jsonb_build_object('service',s.id,'role',r.id,'ordinal',v_ordinal,'member',v_member,'version',s.version,
     'request',extensions.gen_random_uuid(),'override',coalesce((p_data->>'override')::boolean,false),'reason',coalesce(p_data->>'reason','')));
  else
   if v_member is not null then
    if not private.scale_qualified(p_org,p_unit,v_member,r.id) then raise exception 'scale_qualification' using errcode='22023'; end if;
    if exists(select 1 from private.scale_positions o join private.scale_members om on om.id=o.member_id join private.scale_members nm on nm.id=v_member
     where o.service_id=s.id and om.person_id=nm.person_id and not(o.role_id=r.id and o.ordinal=v_ordinal)) then
     raise exception 'scale_person_duplicate' using errcode='22023';
    end if;
   end if;
   update private.scale_positions set member_id=v_member where service_id=s.id and role_id=r.id and ordinal=v_ordinal;
   update private.scale_services set version=version+1 where id=s.id;
  end if;
  insert into private.scale_service_history(service_id,organization_id,unit_id,actor,action,before_data,after_data)
   values(s.id,p_org,p_unit,auth.uid(),'board.assign',jsonb_build_object('member',q.member_id),jsonb_build_object('role',r.id,'ordinal',v_ordinal,'member',v_member));
  select * into s from private.scale_services where id=s.id;
  return jsonb_build_object('ok',true,'version',s.version,'conflicts',to_jsonb(private.scale_conflicts(s.id,r.id,v_member,v_ordinal)));
 end if;

 -- publish: cada culto é tratado à parte; um culto com problema não impede os outros.
 if jsonb_typeof(p_data->'services')<>'array' or jsonb_array_length(p_data->'services') not between 1 and 31 then raise exception 'scale_input' using errcode='22023'; end if;
 for sid in select jsonb_array_elements_text(p_data->'services') loop
  begin
   v:=private.scale_operations(p_org,p_unit,'view',jsonb_build_object('service',sid::uuid));
   perform private.scale_operations(p_org,p_unit,'publish',jsonb_build_object('service',sid::uuid,'token',v->>'token','scope','current',
     'request',extensions.gen_random_uuid(),'override',coalesce((p_data->>'override')::boolean,false),'reason',coalesce(p_data->>'reason','')));
   published:=published||to_jsonb(sid::uuid);
  exception when others then
   failed:=failed||jsonb_build_object('id',sid,'code',sqlstate,'error',sqlerrm);
  end;
 end loop;
 return jsonb_build_object('published',published,'failed',failed);
end $$;

create or replace function public.scale_board(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language sql security invoker set search_path to '' as $$ select private.scale_board(p_org,p_unit,p_action,p_data) $$;
revoke all on function private.scale_board(uuid,uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.scale_board(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.scale_board(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.scale_board(uuid,uuid,text,jsonb) to authenticated;
