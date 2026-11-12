-- Permissões · Fases P3/P4 · Células.
-- Células passa a aceitar "regra atual OU permissão concedida" na ficha do usuário.
--  · Sem limite de grupo: Células (ver/criar/editar) abre o cadastro de células da igreja;
--    Redes (ver/criar/editar) abre o cadastro de redes.
--  · Com "Limitar a grupos" (células ou redes): a pessoa atua na área de acompanhamento
--    (Células+) só nas células escolhidas ou nas redes escolhidas e nas redes abaixo delas,
--    como os supervisores de rede já cadastrados. Ver = acompanhar; Células · editar =
--    acompanhamento; Relatórios · criar/aprovar = relatórios.
-- A regra antiga (papéis e supervisores cadastrados por rede) continua valendo.

-- 1. Gestão da igreja: papel antigo (líder/pastor/admin com gestão na igreja) ou permissão.
create function private.cell_manage_allowed(p_org uuid,p_unit uuid,p_permission text) returns boolean
language sql stable security definer set search_path='' as $$
 select (private.has_organization_role(p_org,array['owner','admin','pastor','leader']::public.membership_role[])
   and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]))
  or private.can(p_org,p_unit,p_permission,'edit') or private.can(p_org,p_unit,p_permission,'create')
$$;
revoke all on function private.cell_manage_allowed(uuid,uuid,text) from public,anon,service_role;
grant execute on function private.cell_manage_allowed(uuid,uuid,text) to authenticated;

-- Leitura do cadastro (também usada nas regras de leitura das tabelas): só concessão sem limite.
create or replace function private.cell_directory_allowed(p_organization uuid,p_unit uuid) returns boolean
language sql stable set search_path='' as $$
 select (auth.uid() is not null
 and private.has_organization_role(p_organization,array['owner','admin','pastor','leader','secretary']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit)
 and private.target_unit_module_enabled(p_organization,p_unit,'cells')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id
 where u.id=p_unit and u.organization_id=p_organization and u.status='active' and o.status in ('active','trial')))
 or private.can(p_organization,p_unit,'cells.cells','view') or private.can(p_organization,p_unit,'cells.networks','view');
$$;

do $cells$
declare f text;perm text;d text;n integer;
 flag text:=$p$private\.has_organization_role\(p_organization,array\['owner','admin','pastor','leader'\]::public\.membership_role\[\]\)\s+and private\.can_access_unit\(p_organization,p_unit,array\['manage','admin'\]::public\.unit_access_level\[\]\)$p$;
 deny text:=$p$or not private\.has_organization_role\(p_organization,array\['owner','admin','pastor','leader'\]::public\.membership_role\[\]\)\s+or not private\.can_access_unit\(p_organization,p_unit,array\['manage','admin'\]::public\.unit_access_level\[\]\)$p$;
begin
 for f,perm in select * from (values
  ('public.cell_directory_save(uuid,uuid,uuid,integer,jsonb)','cells.cells'),
  ('public.cell_operations_save(uuid,uuid,text,uuid,uuid,integer,jsonb)','cells.cells'),
  ('private.cell_visits_save(uuid,uuid,uuid,uuid,integer,jsonb)','cells.cells'),
  ('private.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb)','cells.networks'),
  ('public.cell_directory_list(uuid,uuid,uuid)','cells.cells'),
  ('public.cell_directory_list_v2(uuid,uuid,uuid)','cells.cells'),
  ('public.cell_operations_read(uuid,uuid,text,uuid,uuid,uuid,text,date,date)','cells.cells'),
  ('public.cell_visits_read(uuid,uuid,uuid,date,date,uuid)','cells.cells'),
  ('public.cell_flows_read(uuid,uuid,text,uuid)','cells.cells'),
  ('public.cell_networks_read(uuid,uuid,text,uuid,uuid)','cells.networks')) v(a,b) loop
  d:=pg_get_functiondef(f::regprocedure);
  n:=(select count(*) from regexp_matches(d,flag,'g'))+(select count(*) from regexp_matches(d,deny,'g'));
  if n<>1 then raise exception 'cell_function_changed: % (%)',f,n;end if;
  d:=regexp_replace(d,flag,format('private.cell_manage_allowed(p_organization,p_unit,%L)',perm),'g');
  d:=regexp_replace(d,deny,format('or not private.cell_manage_allowed(p_organization,p_unit,%L)',perm),'g');
  execute d;
 end loop;
end $cells$;

-- 2. Acompanhamento (Células+) por célula ou rede concedida.
create function private.cell_network_ancestors(p_org uuid,p_unit uuid,p_networks uuid[]) returns uuid[]
language sql stable security definer set search_path='' as $$
 with recursive up(id,seen) as (
  select n.id,array[n.id] from public.church_cell_networks n where n.id=any(p_networks) and n.organization_id=p_org and n.unit_id=p_unit and n.status='active'
  union all select e.parent_id,u.seen||e.parent_id from up u join public.church_cell_network_parents e on e.network_id=u.id
   join public.church_cell_networks n on n.id=e.parent_id and n.organization_id=p_org and n.unit_id=p_unit and n.status='active'
   where not e.parent_id=any(u.seen) and cardinality(u.seen)<32)
 select coalesce(array_agg(distinct id),'{}') from up
$$;
revoke all on function private.cell_network_ancestors(uuid,uuid,uuid[]) from public,anon,authenticated,service_role;

create function private.cell_grant_ok(p_org uuid,p_unit uuid,p_cap text,p_groups uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select case p_cap
  when 'followup' then private.can_in(p_org,p_unit,'cells.cells','edit',p_groups)
  when 'report' then private.can_in(p_org,p_unit,'cells.reports','create',p_groups) or private.can_in(p_org,p_unit,'cells.reports','approve',p_groups)
  else private.can_in(p_org,p_unit,'cells.cells','view',p_groups) or private.can_in(p_org,p_unit,'cells.networks','view',p_groups) or private.can_in(p_org,p_unit,'cells.reports','view',p_groups) end
$$;
revoke all on function private.cell_grant_ok(uuid,uuid,text,uuid[]) from public,anon,authenticated,service_role;

-- Alguma permissão de Células que cubra a igreja (limitada ou não).
create function private.cell_scope_granted(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_grant_ok(p_org,p_unit,'read',null)
$$;
revoke all on function private.cell_scope_granted(uuid,uuid) from public,anon,authenticated,service_role;

-- A área ativa para quem tem permissão concedida confere o módulo contratado sem exigir
-- acesso por papel à igreja.
alter function private.cell_plus_active(uuid,uuid,uuid) rename to cell_plus_active_by_role;
create function private.cell_plus_active(p_org uuid,p_unit uuid,p_actor uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_plus_active_by_role(p_org,p_unit,p_actor) or (p_actor is not null and p_actor=auth.uid()
  and exists(select 1 from public.organization_memberships where organization_id=p_org and user_id=p_actor and status='active')
  and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'))
  and private.cell_scope_granted(p_org,p_unit) and private.unit_module_contracted(p_org,p_unit,'people'))
$$;
revoke all on function private.cell_plus_active(uuid,uuid,uuid),private.cell_plus_active_by_role(uuid,uuid,uuid) from public,anon,authenticated,service_role;

alter function private.cell_plus_unit_read(uuid,uuid,uuid) rename to cell_plus_unit_read_by_role;
create function private.cell_plus_unit_read(p_org uuid,p_unit uuid,p_actor uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_plus_unit_read_by_role(p_org,p_unit,p_actor) or (p_actor=auth.uid() and private.cell_scope_granted(p_org,p_unit))
$$;

alter function private.cell_flow_manager(uuid,uuid,uuid) rename to cell_flow_manager_by_role;
create function private.cell_flow_manager(p_org uuid,p_unit uuid,p_actor uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_flow_manager_by_role(p_org,p_unit,p_actor) or (p_actor=auth.uid() and private.can(p_org,p_unit,'cells.cells','edit'))
$$;

alter function private.cell_plus_network(uuid,uuid,uuid,uuid,text) rename to cell_plus_network_by_role;
create function private.cell_plus_network(p_org uuid,p_unit uuid,p_network uuid,p_actor uuid,p_capability text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_plus_network_by_role(p_org,p_unit,p_network,p_actor,p_capability)
  or (p_actor=auth.uid() and private.cell_plus_active(p_org,p_unit,p_actor)
   and exists(select 1 from public.church_cell_networks n where n.id=p_network and n.organization_id=p_org and n.unit_id=p_unit and n.status='active')
   and private.cell_grant_ok(p_org,p_unit,p_capability,private.cell_network_ancestors(p_org,p_unit,array[p_network])))
$$;

alter function private.cell_plus_cell(uuid,uuid,uuid,uuid,text) rename to cell_plus_cell_by_role;
create function private.cell_plus_cell(p_org uuid,p_unit uuid,p_cell uuid,p_actor uuid,p_capability text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select private.cell_plus_cell_by_role(p_org,p_unit,p_cell,p_actor,p_capability)
  or (p_actor=auth.uid() and private.cell_plus_active(p_org,p_unit,p_actor)
   and exists(select 1 from public.church_cells c where c.id=p_cell and c.organization_id=p_org and c.unit_id=p_unit and c.status='active')
   and private.cell_grant_ok(p_org,p_unit,p_capability,array[p_cell]||private.cell_network_ancestors(p_org,p_unit,
    (select coalesce(array_agg(l.network_id),'{}') from public.church_cell_network_links l where l.cell_id=p_cell))))
$$;

revoke all on function private.cell_plus_unit_read(uuid,uuid,uuid),private.cell_plus_unit_read_by_role(uuid,uuid,uuid),
 private.cell_flow_manager(uuid,uuid,uuid),private.cell_flow_manager_by_role(uuid,uuid,uuid),
 private.cell_plus_network(uuid,uuid,uuid,uuid,text),private.cell_plus_network_by_role(uuid,uuid,uuid,uuid,text),
 private.cell_plus_cell(uuid,uuid,uuid,uuid,text),private.cell_plus_cell_by_role(uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

-- 3. A área de acompanhamento aceita quem tem permissão concedida na igreja (mesmo sem
-- acesso por papel à igreja) e não exige supervisor cadastrado por rede.
do $plus$
declare d text;a text;b text;
begin
 d:=pg_get_functiondef('private.cell_plus_read(uuid,uuid,text,uuid,uuid,date,date,uuid)'::regprocedure);
 a:='or not private.can_access_unit(p_org,p_unit) then';
 b:='if not manager and not exists(select 1 from private.cell_supervisor_grants g';
 if (length(d)-length(replace(d,a,'')))/length(a)<>1 or (length(d)-length(replace(d,b,'')))/length(b)<>1 then raise exception 'cell_plus_read_changed';end if;
 d:=replace(d,a,'or not (private.can_access_unit(p_org,p_unit) or private.cell_scope_granted(p_org,p_unit)) then');
 d:=replace(d,b,'if not manager and not private.cell_scope_granted(p_org,p_unit) and not exists(select 1 from private.cell_supervisor_grants g');
 execute d;
 d:=pg_get_functiondef('private.cell_study_file_allowed(text,boolean)'::regprocedure);
 a:='or not private.can_access_unit(m.organization_id,m.unit_id) then';
 if (length(d)-length(replace(d,a,'')))/length(a)<>1 then raise exception 'cell_study_file_changed';end if;
 d:=replace(d,a,'or not (private.can_access_unit(m.organization_id,m.unit_id) or private.cell_scope_granted(m.organization_id,m.unit_id)) then');
 execute d;
end $plus$;
