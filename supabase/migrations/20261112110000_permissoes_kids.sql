-- Permissões · Fases P3/P4 · Kids.
-- O Kids passa a aceitar "regra atual OU permissão concedida" na ficha do usuário, com
-- "Limitar a grupos" por turma. A regra antiga (papéis e a equipe escalada em cada sessão)
-- continua valendo.
--  · Crianças e responsáveis (kids.children, nova): ver e cadastrar crianças e responsáveis;
--    "aprovar" libera a aprovação de responsáveis autorizados a retirar.
--  · Turmas e salas (kids.classes): ver; criar/editar configura sessões e salas (sem limite de
--    turma) e, com limite, coordena as salas das turmas escolhidas.
--  · Check-in e check-out (kids.checkin): ver; editar recebe e entrega crianças nas salas das
--    turmas escolhidas.
--  · Ocorrências (kids.incidents): "aprovar" libera as informações de cuidado (saúde/alergias).

insert into private.permission_catalog(code,module,area,label,actions,group_kinds,position,owner_only) values
 ('kids.children','kids','Kids','Crianças e responsáveis',array['view','create','edit','approve'],'{}',69,false);
update private.permission_catalog set label='Ocorrências e cuidados' where code='kids.incidents';
update private.permission_templates set items=items||'{"kids.children":["view","create","edit"]}' where code in('lider_kids','secretaria');
update private.permission_templates set items=items||'{"kids.children":["view","approve"]}' where code='pastor';

-- Turma da sala da sessão (o "grupo" nas funções do Kids é a sala da sessão).
create function private.kids_room_classes(p_org uuid,p_group uuid) returns uuid[]
language sql stable security definer set search_path='' as $$
 select case when p_group is null then null else coalesce((select array[r.class_id] from private.kids_session_rooms r where r.id=p_group and r.organization_id=p_org and r.class_id is not null),array[p_group]) end
$$;
revoke all on function private.kids_room_classes(uuid,uuid) from public,anon,authenticated,service_role;

create function private.kids_permission_base(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.session_alive() and private.unit_module_contracted(p_org,p_unit,'people')
$$;
revoke all on function private.kids_permission_base(uuid,uuid) from public,anon,authenticated,service_role;

alter function private.kids_allowed(uuid,uuid,text) rename to kids_allowed_by_role;
create function private.kids_allowed(p_org uuid,p_unit uuid,p_mode text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select private.kids_allowed_by_role(p_org,p_unit,p_mode) or (private.kids_permission_base(p_org,p_unit) and case p_mode
  when 'read' then private.can(p_org,p_unit,'kids.children','view')
  when 'write' then private.can(p_org,p_unit,'kids.children','create') or private.can(p_org,p_unit,'kids.children','edit')
  when 'approve' then private.can(p_org,p_unit,'kids.children','approve')
  when 'care' then private.can(p_org,p_unit,'kids.incidents','approve')
  else false end)
$$;

alter function private.kids_op_allowed(uuid,uuid,uuid,text,uuid) rename to kids_op_allowed_by_role;
create function private.kids_op_allowed(p_org uuid,p_unit uuid,p_session uuid default null,p_mode text default 'read',p_group uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select private.kids_op_allowed_by_role(p_org,p_unit,p_session,p_mode,p_group) or (private.kids_permission_base(p_org,p_unit)
  and (p_session is null or exists(select 1 from private.kids_sessions s where s.id=p_session and s.organization_id=p_org and s.unit_id=p_unit))
  and case p_mode
   when 'configure' then private.can(p_org,p_unit,'kids.classes','create') or private.can(p_org,p_unit,'kids.classes','edit')
   when 'supervise' then private.can_in(p_org,p_unit,'kids.classes','edit',private.kids_room_classes(p_org,p_group))
   when 'receive' then private.can_in(p_org,p_unit,'kids.checkin','edit',private.kids_room_classes(p_org,p_group))
   when 'accept' then private.can_in(p_org,p_unit,'kids.checkin','edit',private.kids_room_classes(p_org,p_group))
   else private.can_in(p_org,p_unit,'kids.checkin','view',private.kids_room_classes(p_org,p_group))
    or private.can_in(p_org,p_unit,'kids.classes','view',private.kids_room_classes(p_org,p_group)) end)
$$;

revoke all on function private.kids_allowed(uuid,uuid,text),private.kids_allowed_by_role(uuid,uuid,text),private.kids_op_allowed(uuid,uuid,uuid,text,uuid),private.kids_op_allowed_by_role(uuid,uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
