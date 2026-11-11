-- Permissões · Fase P3 · Financeiro.
-- Cada ação do Financeiro passa a aceitar "regra atual OU permissão concedida" (private.can()).
-- Quem já tinha acesso (dono, administrador e tesouraria com gestão na igreja) continua igual.
-- Quem recebeu permissões em Configurações › Usuários e permissões passa a ver e fazer só o
-- que foi concedido, na abrangência concedida. Ações exclusivas de dono/administrador continuam
-- assim (destinação de recebimentos, cadastros compartilhados, reabrir mês, orçamento,
-- contribuições individuais).

-- 1. Regra atual, preservada com outro nome.
create function private.church_ledger_role_allowed(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and private.has_organization_role(p_org,array['owner','admin','finance']::public.membership_role[])
 and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[])
 and private.target_unit_module_enabled(p_org,p_unit,'finance')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'));
$$;
revoke all on function private.church_ledger_role_allowed(uuid,uuid) from public,anon,authenticated,service_role;

-- Alguma permissão financeira concedida que cubra a igreja (portão de entrada dos módulos).
create function private.finance_grant_any(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.permission_catalog c where c.code like 'finance.%' and exists(
  select 1 from unnest(c.actions) a where private.can(p_org,p_unit,c.code,a)))
$$;
revoke all on function private.finance_grant_any(uuid,uuid) from public,anon,authenticated,service_role;

-- O portão geral do Financeiro passa a aceitar quem tem permissão concedida; a ação exata é
-- conferida pelos portões das funções de entrada abaixo.
create or replace function private.church_ledger_allowed(p_org uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.church_ledger_role_allowed(p_org,p_unit) or private.finance_grant_any(p_org,p_unit);
$$;

-- 2. Portão por ação.
create function private.finance_require(p_org uuid,p_unit uuid,p_permission text,p_action text) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if p_unit is null or not (private.church_ledger_role_allowed(p_org,p_unit) or private.can(p_org,p_unit,p_permission,p_action)) then
  raise exception 'finance_permission_denied' using errcode='42501';
 end if;
end $$;
revoke all on function private.finance_require(uuid,uuid,text,text) from public,anon,authenticated,service_role;

-- 3. Funções de entrada com o portão por ação. As funções anteriores ficam com o sufixo
-- _before_permissions e só são chamadas por estas.
alter function private.finance_f1(uuid,uuid[],text,jsonb) rename to finance_f1_before_permissions;
create function private.finance_f1(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid;perm text;act text;
begin
 perm:=case when p_action='catalog' then 'finance.registry'
  when p_action='entry' and p_data->>'kind' in('income','expense') and nullif(p_data->>'paid','') is null then 'finance.payables'
  else 'finance.entries' end;
 act:=case p_action when 'snapshot' then 'view' when 'choices' then 'view' when 'entry' then 'create' when 'void' then 'edit' when 'delete' then 'delete'
  when 'catalog' then case when coalesce((p_data->>'version')::integer,0)=0 then 'create' else 'edit' end else 'edit' end;
 foreach u in array coalesce(p_units,'{}') loop perform private.finance_require(p_org,u,perm,act);end loop;
 return private.finance_f1_before_permissions(p_org,p_units,p_action,p_data);
end $$;

alter function private.finance_f2(uuid,uuid,text,jsonb) rename to finance_f2_before_permissions;
create function private.finance_f2(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.finance_require(p_org,p_unit,'finance.payables',case when p_action in('history','activity') then 'view' when p_action='series' then 'create' else 'edit' end);
 return private.finance_f2_before_permissions(p_org,p_unit,p_action,p_data);
end $$;

alter function private.finance_f5(uuid,uuid,text,jsonb) rename to finance_f5_before_permissions;
create function private.finance_f5(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if p_action in('close','reopen') then perform private.finance_require(p_org,p_unit,'finance.closing','approve');
 else perform private.finance_require(p_org,p_unit,'finance.reconciliation',case when p_action='snapshot' then 'view' else 'edit' end);end if;
 return private.finance_f5_before_permissions(p_org,p_unit,p_action,p_data);
end $$;

alter function private.finance_f6(uuid,uuid[],text,jsonb) rename to finance_f6_before_permissions;
create function private.finance_f6(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid;
begin
 foreach u in array coalesce(p_units,'{}') loop
  if p_action='budget' then perform private.finance_require(p_org,u,'finance.registry','edit');
  else perform private.finance_require(p_org,u,'finance.reports',case when coalesce((p_data->>'export')::boolean,false) then 'export' else 'view' end);end if;
 end loop;
 return private.finance_f6_before_permissions(p_org,p_units,p_action,p_data);
end $$;

alter function private.finance_digital(uuid,uuid,text,jsonb) rename to finance_digital_before_permissions;
create function private.finance_digital(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.finance_require(p_org,p_unit,'finance.digital',case when p_action in('list','detail') then 'view' else 'edit' end);
 return private.finance_digital_before_permissions(p_org,p_unit,p_action,p_data);
end $$;

alter function private.finance_digital_destination(uuid,uuid,text,jsonb) rename to finance_digital_destination_before_permissions;
create function private.finance_digital_destination(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.finance_require(p_org,p_unit,'finance.digital',case when p_action='list' then 'view' else 'edit' end);
 return private.finance_digital_destination_before_permissions(p_org,p_unit,p_action,p_data);
end $$;

alter function private.finance_annotate_entry(uuid,uuid,jsonb) rename to finance_annotate_entry_before_permissions;
create function private.finance_annotate_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.finance_require(p_org,p_unit,'finance.entries','edit');
 return private.finance_annotate_entry_before_permissions(p_org,p_unit,p_data);
end $$;

alter function private.finance_revise_entry(uuid,uuid,jsonb) rename to finance_revise_entry_before_permissions;
create function private.finance_revise_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.finance_require(p_org,p_unit,'finance.entries','edit');
 return private.finance_revise_entry_before_permissions(p_org,p_unit,p_data);
end $$;

alter function private.finance_revise_pending(uuid,uuid,jsonb) rename to finance_revise_pending_before_permissions;
create function private.finance_revise_pending(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.finance_require(p_org,p_unit,'finance.payables','edit');
 return private.finance_revise_pending_before_permissions(p_org,p_unit,p_data);
end $$;

-- As funções públicas (invoker) continuam chamando as privadas pelo mesmo nome. Só as novas
-- entradas ficam disponíveis para a sessão; as anteriores só são chamadas por elas.
do $grants$
declare f text;
begin
 foreach f in array array['finance_f1(uuid,uuid[],text,jsonb)','finance_f2(uuid,uuid,text,jsonb)','finance_f5(uuid,uuid,text,jsonb)','finance_f6(uuid,uuid[],text,jsonb)','finance_digital(uuid,uuid,text,jsonb)','finance_digital_destination(uuid,uuid,text,jsonb)','finance_annotate_entry(uuid,uuid,jsonb)','finance_revise_entry(uuid,uuid,jsonb)','finance_revise_pending(uuid,uuid,jsonb)'] loop
  execute format('revoke all on function private.%s from public,anon,service_role',f);
  execute format('grant execute on function private.%s to authenticated',f);
  execute format('revoke all on function private.%s from public,anon,authenticated,service_role',replace(f,'(','_before_permissions('));
 end loop;
end $grants$;

-- 4. As igrejas da pessoa incluem as cobertas por permissões concedidas (para escolher a
-- igreja nas telas). Cada módulo continua decidindo o que a pessoa pode fazer.
create function private.permission_unit_granted(p_org uuid,p_membership uuid,p_unit uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.permission_grants g join public.organization_memberships m on m.id=g.membership_id
  where g.organization_id=p_org and g.membership_id=p_membership and m.user_id=auth.uid() and m.status='active'
   and private.unit_within(p_org,p_unit,g.unit_id,g.include_children))
$$;
-- Chamada pela access_context (invoker); só responde sobre o próprio vínculo de quem chama.
revoke all on function private.permission_unit_granted(uuid,uuid,uuid) from public,anon,service_role;
grant execute on function private.permission_unit_granted(uuid,uuid,uuid) to authenticated;

do $ctx$
declare d text;needle text;
begin
 d:=pg_get_functiondef('public.access_context()'::regprocedure);
 needle:='and private.can_access_unit(m.organization_id,u.id)';
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'access_context_changed';end if;
 d:=replace(d,needle,'and (private.can_access_unit(m.organization_id,u.id) or private.permission_unit_granted(m.organization_id,m.id,u.id))');
 execute d;
end $ctx$;
