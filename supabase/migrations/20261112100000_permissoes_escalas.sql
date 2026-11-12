-- Permissões · Fases P3/P4 · Escalas.
-- As funções de Escalas passam a aceitar "regra atual OU permissão concedida" na ficha do
-- usuário (Configurações › Usuários e permissões), com "Limitar a grupos" por equipe de escala.
--  · Equipes (scales.teams): ver e configurar equipes, funções e membros. Criar equipe nova
--    exige a permissão "criar" sem limite de grupo.
--  · Escalas e substituições (scales.schedules): ver, montar, preencher e publicar escalas.
-- A regra antiga (dono/administrador e os acessos por equipe já cadastrados) continua valendo.

-- 1. Regra genérica com lista de grupos, usada por Escalas, Kids e Células.
-- p_groups nulo = pergunta geral (vale qualquer concessão, limitada ou não); com grupos, a
-- concessão limitada precisa cobrir ao menos um deles.
create function private.can_in(p_org uuid,p_unit uuid,p_permission text,p_action text,p_groups uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from public.organizations o where o.id=p_org and o.status in('active','trial'))
 and exists(select 1 from public.organization_units u where u.id=p_unit and u.organization_id=p_org and u.status='active')
 and exists(select 1 from private.permission_catalog c where c.code=p_permission and p_action=any(c.actions)
  and (c.module is null or private.unit_module_contracted(p_org,p_unit,c.module)))
 and (
  private.has_organization_role(p_org,array['owner']::public.membership_role[])
  or exists(select 1 from private.permission_grants g join public.organization_memberships m on m.id=g.membership_id
   where g.organization_id=p_org and m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
    and g.permission=p_permission and p_action=any(g.actions)
    and private.unit_within(p_org,p_unit,g.unit_id,g.include_children)
    and (g.group_kind is null or p_groups is null or g.group_ids && p_groups))
 )
$$;
revoke all on function private.can_in(uuid,uuid,text,text,uuid[]) from public,anon,authenticated,service_role;

-- 2. Escalas: capacidade pedida pela função → seção e ações do catálogo.
-- O contexto (equipes ou escalas) vem da função de entrada chamada.
create function private.scale_permission(p_org uuid,p_unit uuid,p_team uuid,p_cap text) returns boolean
language sql stable security definer set search_path='' as $$
 with x as (select case when coalesce(nullif(current_setting('vinha.scale_ctx',true),''),'schedules')='teams' and p_cap in('read','manage') then 'scales.teams' else 'scales.schedules' end perm,
  case p_cap when 'read' then array['view'] when 'manage' then array['create','edit'] else array['edit'] end acts)
 select private.unit_module_contracted(p_org,p_unit,'people') and exists(select 1 from x,unnest(x.acts) a
  where private.can_in(p_org,p_unit,x.perm,a,case when p_team is null then null else array[p_team] end))
$$;
revoke all on function private.scale_permission(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

alter function private.scale_allowed(uuid,uuid,uuid,text) rename to scale_allowed_by_role;
create function private.scale_allowed(p_org uuid,p_unit uuid,p_team uuid,p_cap text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.scale_allowed_by_role(p_org,p_unit,p_team,p_cap) or private.scale_permission(p_org,p_unit,p_team,p_cap)
$$;
revoke all on function private.scale_allowed(uuid,uuid,uuid,text),private.scale_allowed_by_role(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

-- 3. Criar equipe: administrador ou permissão "criar" em Equipes sem limite de grupo.
-- Gerenciar os acessos antigos por equipe continua exclusivo do administrador.
do $foundation$
declare d text;needle text:=$n$if (cap='admin' and not admin) or$n$;
begin
 d:=pg_get_functiondef('private.scale_foundation(uuid,uuid,text,jsonb)'::regprocedure);
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'scale_foundation_changed';end if;
 d:=replace(d,needle,$r$if (cap='admin' and not (admin or p_action='team' and private.can(p_org,p_unit,'scales.teams','create'))) or$r$);
 execute d;
end $foundation$;

-- 4. Funções de entrada informam o contexto e chamam as anteriores (sufixo _before_permissions).
alter function private.scale_foundation(uuid,uuid,text,jsonb) rename to scale_foundation_before_permissions;
create function private.scale_foundation(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform set_config('vinha.scale_ctx','teams',true);
 r:=private.scale_foundation_before_permissions(p_org,p_unit,p_action,p_data);
 if p_action='list' then r:=r||jsonb_build_object('canCreate',private.scale_admin(p_org,p_unit) or private.can(p_org,p_unit,'scales.teams','create'));end if;
 perform set_config('vinha.scale_ctx','',true);
 return r;
end $$;

alter function private.scale_planning(uuid,uuid,text,jsonb) rename to scale_planning_before_permissions;
create function private.scale_planning(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform set_config('vinha.scale_ctx','schedules',true);
 r:=private.scale_planning_before_permissions(p_org,p_unit,p_action,p_data);
 perform set_config('vinha.scale_ctx','',true);
 return r;
end $$;

alter function private.scale_operations(uuid,uuid,text,jsonb) rename to scale_operations_before_permissions;
create function private.scale_operations(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform set_config('vinha.scale_ctx','schedules',true);
 r:=private.scale_operations_before_permissions(p_org,p_unit,p_action,p_data);
 perform set_config('vinha.scale_ctx','',true);
 return r;
end $$;

do $grants$
declare f text;
begin
 foreach f in array array['scale_foundation','scale_planning','scale_operations'] loop
  execute format('revoke all on function private.%s(uuid,uuid,text,jsonb) from public,anon,service_role',f);
  execute format('grant execute on function private.%s(uuid,uuid,text,jsonb) to authenticated',f);
  execute format('revoke all on function private.%s_before_permissions(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role',f);
 end loop;
end $grants$;
