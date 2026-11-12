-- Permissões · Fase P3 · Igreja.
--  · Igrejas e filiais (church.units): ver; criar filial abaixo da igreja concedida; editar a
--    igreja concedida (e as filhas, conforme a abrangência). Excluir continua com a administração.
--  · Configurações e identidade (church.settings): editar a identidade do ministério exige a
--    permissão concedida para todo o ministério (sem igreja específica).

-- Concessão para todo o ministério (sem igreja específica), usada em ajustes do ministério.
create function private.can_ministry(p_org uuid,p_permission text,p_action text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.has_organization_role(p_org,array['owner']::public.membership_role[]) or exists(
  select 1 from private.permission_grants g join public.organization_memberships m on m.id=g.membership_id
  join public.organizations o on o.id=g.organization_id and o.status in('active','trial')
  where g.organization_id=p_org and m.user_id=auth.uid() and m.status='active' and g.unit_id is null
   and g.permission=p_permission and p_action=any(g.actions)))
$$;
revoke all on function private.can_ministry(uuid,text,text) from public,anon,service_role;
grant execute on function private.can_ministry(uuid,text,text) to authenticated;

-- Igrejas: leitura e gravação pelas regras das tabelas (avaliadas como a pessoa logada).
create function private.unit_permission(p_org uuid,p_unit uuid,p_action text) returns boolean
language sql stable security definer set search_path='' as $$
 select p_unit is not null and private.can(p_org,p_unit,'church.units',p_action)
$$;
revoke all on function private.unit_permission(uuid,uuid,text) from public,anon,service_role;
grant execute on function private.unit_permission(uuid,uuid,text) to authenticated;

alter policy units_select_member on public.organization_units using (
 ((private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[])
   and exists(select 1 from public.organizations o where o.id=organization_units.organization_id and o.status in('active','trial')))
  or private.can_access_unit(organization_id,id))
 or private.unit_permission(organization_id,id,'view'));
alter policy units_update_admin on public.organization_units
 using (private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[]) or private.unit_permission(organization_id,id,'edit'))
 with check (private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[])
  or private.unit_permission(organization_id,id,'edit') and (parent_unit_id is null or private.unit_permission(organization_id,parent_unit_id,'edit')));
alter policy units_insert_admin on public.organization_units with check (
 private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[])
 or parent_unit_id is not null and private.unit_permission(organization_id,parent_unit_id,'create'));

-- Configurações e identidade do ministério.
do $settings$
declare d text;a text:=$a$and role in ('owner','admin','pastor') for share;
 if not found then raise exception 'settings_access_denied'$a$;
begin
 d:=pg_get_functiondef('private.organization_settings_save(uuid,uuid,jsonb)'::regprocedure);
 if (length(d)-length(replace(d,a,'')))/length(a)<>1 then raise exception 'organization_settings_save_changed';end if;
 d:=replace(d,a,$b$and (role in ('owner','admin','pastor') or private.can_ministry(p_org,'church.settings','edit')) for share;
 if not found then raise exception 'settings_access_denied'$b$);
 execute d;
end $settings$;

-- A proteção da igreja trava o ministério por uma função controlada (quem edita por permissão
-- não tem gravação no ministério). Autonomias (financeira, comunicação e identidade visual)
-- continuam só com a administração.
create function private.lock_active_organization(p_org uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.organizations where id=p_org and status in ('active','trial') for update;
 return found;
end $$;
revoke all on function private.lock_active_organization(uuid) from public,anon,service_role;
grant execute on function private.lock_active_organization(uuid) to authenticated;
do $guard$
declare d text;a text:=$a$ perform 1 from public.organizations where id=new.organization_id and status in ('active','trial') for update;
 if not found then raise exception 'unit_organization_unavailable' using errcode='42501'; end if;$a$;
begin
 d:=pg_get_functiondef('private.guard_unit_client_fields()'::regprocedure);
 if (length(d)-length(replace(d,a,'')))/length(a)<>1 then raise exception 'guard_unit_client_fields_changed';end if;
 d:=replace(d,a,$b$ if not private.lock_active_organization(new.organization_id) then raise exception 'unit_organization_unavailable' using errcode='42501'; end if;
 if not private.has_organization_role(new.organization_id,array['owner','pastor','admin']::public.membership_role[])
  and (new.financial_autonomy is distinct from case when tg_op='UPDATE' then old.financial_autonomy else false end
   or new.communication_autonomy is distinct from case when tg_op='UPDATE' then old.communication_autonomy else true end
   or new.branding_autonomy is distinct from case when tg_op='UPDATE' then old.branding_autonomy else false end) then
  raise exception 'unit_autonomy_admin_only' using errcode='42501';
 end if;$b$);
 execute d;
end $guard$;
