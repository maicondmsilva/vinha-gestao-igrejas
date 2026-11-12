-- Permissões · Fase P3 · Pessoas, Programação e Comunicação (e P4: acessos avulsos de equipe).
-- Cada módulo passa a aceitar "regra atual OU permissão concedida" na ficha do usuário.
--  · Pessoas: Membros e Visitantes (ver/criar/editar) na igreja concedida. "Visitantes" vale só
--    para cadastros com etapa Visitante.
--  · Programação: Agenda e Eventos (criar/editar) gerenciam a programação; Inscrições e check-in
--    (editar) operam o check-in. Ingressos usa a gestão de eventos.
--  · Comunicação: Avisos, Banners e Transmissões (criar/editar) publicam; Push (criar) envia;
--    Chat (editar) modera.
-- Os acessos avulsos antigos de equipe (agenda, check-in, publicações e push) continuam valendo:
-- a função única private.staff_grant agora também aceita as permissões equivalentes.

-- 1. Consulta da aplicação: a pessoa tem alguma destas permissões em alguma igreja?
-- Usada só para abrir a tela/rota; cada ação continua conferida pelo banco na igreja certa.
create function private.permission_any(p_org uuid,p_checks text[]) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.has_organization_role(p_org,array['owner']::public.membership_role[]) or exists(
  select 1 from private.permission_grants g join public.organization_memberships m on m.id=g.membership_id
  join public.organizations o on o.id=g.organization_id and o.status in('active','trial')
  where g.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
   and exists(select 1 from unnest(p_checks) c where split_part(c,':',1)=g.permission and split_part(c,':',2)=any(g.actions))))
$$;
revoke all on function private.permission_any(uuid,text[]) from public,anon,service_role;
grant execute on function private.permission_any(uuid,text[]) to authenticated;
create function public.permission_any(p_org uuid,p_checks text[]) returns boolean
language sql stable security invoker set search_path='' as $$ select private.permission_any(p_org,p_checks) $$;
revoke all on function public.permission_any(uuid,text[]) from public,anon,service_role;
grant execute on function public.permission_any(uuid,text[]) to authenticated;

-- 2. Pessoas.
create function private.person_permission(p_person uuid,p_action text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.people p where p.id=p_person and p.unit_id is not null
  and private.unit_module_contracted(p.organization_id,p.unit_id,'people')
  and (private.can(p.organization_id,p.unit_id,'people.members',p_action)
   or p.journey_status='Visitante' and private.can(p.organization_id,p.unit_id,'people.visitors',p_action)))
$$;
revoke all on function private.person_permission(uuid,text) from public,anon,authenticated,service_role;

-- O cadastro (pessoa, endereços e contatos de emergência) aceita a permissão concedida.
-- Anotações pastorais, consentimentos e transferências continuam só com a regra antiga
-- (private.can_view_person / private.can_manage_person não mudam).
create function private.person_record_view(target_person_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.can_view_person(target_person_id) or private.person_permission(target_person_id,'view')
$$;
create function private.person_record_manage(target_person_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.can_manage_person(target_person_id) or private.person_permission(target_person_id,'edit')
$$;
revoke all on function private.person_record_view(uuid),private.person_record_manage(uuid) from public,anon,service_role;
grant execute on function private.person_record_view(uuid),private.person_record_manage(uuid) to authenticated;

do $policies$
declare r record;q text;c text;
begin
 for r in select * from pg_policies where schemaname='public' and (tablename='people' and policyname in('people_select_scope','people_update_scope')
   or tablename in('person_addresses','emergency_contacts')) loop
  q:=replace(replace(coalesce(r.qual,''),'private.can_view_person(','private.person_record_view('),'private.can_manage_person(','private.person_record_manage(');
  c:=replace(replace(coalesce(r.with_check,''),'private.can_view_person(','private.person_record_view('),'private.can_manage_person(','private.person_record_manage(');
  if q=coalesce(r.qual,'') and c=coalesce(r.with_check,'') then continue;end if;
  execute format('alter policy %I on %I.%I',r.policyname,r.schemaname,r.tablename)
   ||case when r.qual is not null then format(' using (%s)',q) else '' end
   ||case when r.with_check is not null then format(' with check (%s)',c) else '' end;
 end loop;
end $policies$;

-- Cadastrar: regra antiga OU permissão "criar" na igreja do cadastro.
create function private.person_create_permission(p_org uuid,p_unit uuid,p_journey text) returns boolean
language sql stable security definer set search_path='' as $$
 select p_unit is not null and private.unit_module_contracted(p_org,p_unit,'people')
  and (private.can(p_org,p_unit,'people.members','create') or p_journey='Visitante' and private.can(p_org,p_unit,'people.visitors','create'))
$$;
revoke all on function private.person_create_permission(uuid,uuid,text) from public,anon,service_role;
grant execute on function private.person_create_permission(uuid,uuid,text) to authenticated;
alter policy people_insert_scope on public.people with check (
 (private.has_organization_role(organization_id,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
  and exists(select 1 from public.organizations o where o.id=people.organization_id and o.status in('active','trial'))
  and (private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[]) or private.can_access_unit(organization_id,unit_id,array['manage','admin']::public.unit_access_level[])))
 or private.person_create_permission(organization_id,unit_id,journey_status));

-- 3. Programação e Comunicação: os acessos avulsos de equipe aceitam as permissões equivalentes.
alter function private.staff_grant(uuid,uuid,text) rename to staff_grant_by_role;
create function private.staff_grant(p_org uuid,p_unit uuid,p_scope text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.staff_grant_by_role(p_org,p_unit,p_scope) or exists(select 1 from (values
   ('agenda','events.agenda','create'),('agenda','events.agenda','edit'),('agenda','events.events','create'),('agenda','events.events','edit'),
   ('checkin','events.checkin','edit'),
   ('publishing','communication.notices','create'),('publishing','communication.notices','edit'),
   ('publishing','communication.banners','create'),('publishing','communication.banners','edit'),
   ('publishing','communication.broadcasts','create'),('publishing','communication.broadcasts','edit'),
   ('push','communication.push','create')) m(scope,perm,act)
  where m.scope=p_scope and private.can(p_org,p_unit,m.perm,m.act))
$$;
revoke all on function private.staff_grant(uuid,uuid,text),private.staff_grant_by_role(uuid,uuid,text) from public,anon,authenticated,service_role;

alter function private.chat_unit_moderator(uuid,uuid) rename to chat_unit_moderator_by_role;
create function private.chat_unit_moderator(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.chat_unit_moderator_by_role(p_org,p_unit) or private.can(p_org,p_unit,'communication.chat','edit')
$$;
revoke all on function private.chat_unit_moderator(uuid,uuid),private.chat_unit_moderator_by_role(uuid,uuid) from public,anon,authenticated,service_role;

-- Alterar cadastro: o novo estado também precisa estar coberto (regra antiga OU permissão
-- "editar" na igreja de destino).
create function private.person_edit_permission(p_org uuid,p_unit uuid,p_journey text) returns boolean
language sql stable security definer set search_path='' as $$
 select p_unit is not null and private.unit_module_contracted(p_org,p_unit,'people')
  and (private.can(p_org,p_unit,'people.members','edit') or p_journey='Visitante' and private.can(p_org,p_unit,'people.visitors','edit'))
$$;
revoke all on function private.person_edit_permission(uuid,uuid,text) from public,anon,service_role;
grant execute on function private.person_edit_permission(uuid,uuid,text) to authenticated;
alter policy people_update_scope on public.people with check (
 (exists(select 1 from public.organizations o where o.id=people.organization_id and o.status in('active','trial'))
  and (private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[]) or private.can_access_unit(organization_id,unit_id,array['manage','admin']::public.unit_access_level[])))
 or private.person_edit_permission(organization_id,unit_id,journey_status));

-- A proteção de contrato do cadastro confere o módulo contratado na igreja sem depender do
-- papel (quem pode gravar continua decidido pelas regras de leitura/gravação acima).
create function private.people_module_contracted(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and p_unit is not null and private.is_organization_member(p_org)
  and exists(select 1 from public.organization_units u where u.id=p_unit and u.organization_id=p_org)
  and private.unit_module_contracted(p_org,p_unit,'people')
$$;
revoke all on function private.people_module_contracted(uuid,uuid) from public,anon,service_role;
grant execute on function private.people_module_contracted(uuid,uuid) to authenticated;
create or replace function private.guard_member_unit_contract() returns trigger
language plpgsql set search_path='' as $$
begin
 if current_user='authenticated' then
  if not (private.target_unit_module_enabled(new.organization_id,new.unit_id,'people') or private.people_module_contracted(new.organization_id,new.unit_id)) then
   raise exception 'target_unit_module_not_enabled' using errcode='42501';
  end if;
  if tg_op='UPDATE' and not (private.target_unit_module_enabled(old.organization_id,old.unit_id,'people') or private.people_module_contracted(old.organization_id,old.unit_id)) then
   raise exception 'source_unit_module_not_enabled' using errcode='42501';
  end if;
 end if;
 return new;
end $$;
