-- Permissões · Fase P4 · Limitar a grupos.
-- A matriz passa a oferecer, nas seções que aceitam, o limite por células, redes, equipes de
-- escala ou turmas Kids. O banco confere que cada grupo é do tipo indicado e da própria
-- organização. Ativar a regra em cada módulo (Células, Escalas, Kids) é a etapa seguinte.

-- Grupos disponíveis por tipo (só ativos, só da organização).
create function private.permission_group_options(p_org uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'cell',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'unit',c.unit_id) order by c.name),'[]') from public.church_cells c where c.organization_id=p_org and c.status='active'),
  'network',(select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'name',n.name,'unit',n.unit_id) order by n.name),'[]') from public.church_cell_networks n where n.organization_id=p_org and n.status='active'),
  'scale_team',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'unit',t.unit_id) order by t.name),'[]') from private.scale_teams t where t.organization_id=p_org and t.active),
  'kids_class',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'name',k.name,'unit',k.unit_id) order by k.name),'[]') from private.kids_classes k where k.organization_id=p_org and k.active))
$$;
revoke all on function private.permission_group_options(uuid) from public,anon,authenticated,service_role;

-- Cada grupo concedido precisa existir, ser do tipo indicado e da organização.
create function private.permission_groups_valid(p_org uuid,p_kind text,p_groups uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(cardinality(p_groups),0)=0 or (select count(*) from unnest(p_groups) g where case p_kind
  when 'cell' then exists(select 1 from public.church_cells c where c.id=g and c.organization_id=p_org)
  when 'network' then exists(select 1 from public.church_cell_networks n where n.id=g and n.organization_id=p_org)
  when 'scale_team' then exists(select 1 from private.scale_teams t where t.id=g and t.organization_id=p_org)
  when 'kids_class' then exists(select 1 from private.kids_classes k where k.id=g and k.organization_id=p_org)
  else false end)=cardinality(p_groups)
$$;
revoke all on function private.permission_groups_valid(uuid,text,uuid[]) from public,anon,authenticated,service_role;

alter function private.permission_admin(uuid,text,jsonb) rename to permission_admin_before_groups;
create function private.permission_admin(p_org uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_groups uuid[];
begin
 if p_action='groups' then
  perform private.require_confirmed_self_service_email();
  if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'permission_admin_denied' using errcode='42501';end if;
  return private.permission_group_options(p_org);
 end if;
 if p_action='set' and nullif(p_data->>'groupKind','') is not null then
  select coalesce(array_agg(distinct x::uuid),'{}') into v_groups from jsonb_array_elements_text(coalesce(p_data->'groups','[]')) x;
  if not private.permission_groups_valid(p_org,p_data->>'groupKind',v_groups) then raise exception 'invalid_groups' using errcode='22023';end if;
 end if;
 return private.permission_admin_before_groups(p_org,p_action,p_data);
end $$;
revoke all on function private.permission_admin(uuid,text,jsonb),private.permission_admin_before_groups(uuid,text,jsonb) from public,anon,service_role;
revoke all on function private.permission_admin_before_groups(uuid,text,jsonb) from authenticated;
grant execute on function private.permission_admin(uuid,text,jsonb) to authenticated;
