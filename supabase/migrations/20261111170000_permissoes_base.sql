-- Permissões · Fase P1 (docs/PLANO-PERMISSOES-USUARIOS-2026-11-11.md)
-- Base única de permissões: catálogo de seções e ações, concessões por pessoa (abrangência,
-- ações e limite a grupos), modelos prontos e a função private.can().
-- Nenhum acesso muda nesta fase: os módulos continuam com as regras atuais por papel. Na fase
-- P3 cada módulo passa a aceitar "regra atual OU private.can()".

-- 1. Catálogo: a fonte única do que pode ser concedido.
create table private.permission_catalog(
 code text primary key check(code ~ '^[a-z]+\.[a-z_]+$'),
 module text, -- módulo contratado exigido (saas_module_catalog); nulo = sempre disponível
 area text not null,
 label text not null check(length(label) between 2 and 80),
 actions text[] not null check(cardinality(actions)>0 and actions <@ array['view','create','edit','delete','approve','export']),
 group_kinds text[] not null default '{}' check(group_kinds <@ array['cell','network','scale_team','kids_class']),
 position integer not null,
 owner_only boolean not null default false -- só o dono concede (ex.: Usuários e permissões)
);
alter table private.permission_catalog enable row level security;
revoke all on private.permission_catalog from public,anon,authenticated,service_role;

insert into private.permission_catalog(code,module,area,label,actions,group_kinds,position,owner_only) values
 ('people.members','people','Pessoas','Membros',array['view','create','edit','delete','export'],'{}',10,false),
 ('people.visitors','people','Pessoas','Visitantes',array['view','create','edit','delete'],'{}',11,false),
 ('people.pending_profiles','people','Pessoas','Perfis pendentes',array['view','approve'],'{}',12,false),
 ('people.import','people','Pessoas','Importação de membros',array['create'],'{}',13,false),
 ('settings.users',null,'Configurações','Usuários e permissões',array['view','edit'],'{}',90,true),
 ('church.units',null,'Igreja','Igrejas e filiais',array['view','create','edit'],'{}',20,false),
 ('church.settings',null,'Igreja','Configurações e identidade',array['view','edit'],'{}',21,false),
 ('cells.cells','cells','Células','Células',array['view','create','edit','delete'],array['cell','network'],30,false),
 ('cells.networks','cells','Células','Redes',array['view','create','edit','delete'],array['network'],31,false),
 ('cells.reports','cells','Células','Relatórios de célula',array['view','create','approve'],array['cell','network'],32,false),
 ('cells.transfers','cells','Células','Transferências',array['view','approve'],array['network'],33,false),
 ('events.agenda','events','Programação','Agenda',array['view','create','edit','delete'],'{}',40,false),
 ('events.events','events','Programação','Eventos',array['view','create','edit','delete'],'{}',41,false),
 ('events.checkin','events','Programação','Inscrições e check-in',array['view','edit'],'{}',42,false),
 ('events.tickets','events','Programação','Ingressos',array['view','edit','export'],'{}',43,false),
 ('communication.notices','communication','Comunicação','Avisos',array['view','create','edit','delete'],'{}',50,false),
 ('communication.push','communication','Comunicação','Notificações push',array['view','create'],'{}',51,false),
 ('communication.banners','communication','Comunicação','Banners',array['view','create','edit','delete'],'{}',52,false),
 ('communication.broadcasts','broadcasts','Comunicação','Transmissões',array['view','create','edit','delete'],'{}',53,false),
 ('communication.chat','communication','Comunicação','Chat (moderação)',array['view','edit'],'{}',54,false),
 ('scales.teams','scales','Escalas','Equipes',array['view','create','edit','delete'],array['scale_team'],60,false),
 ('scales.schedules','scales','Escalas','Escalas e substituições',array['view','create','edit','delete'],array['scale_team'],61,false),
 ('kids.classes','kids','Kids','Turmas e salas',array['view','create','edit','delete'],array['kids_class'],70,false),
 ('kids.checkin','kids','Kids','Check-in e check-out',array['view','edit'],array['kids_class'],71,false),
 ('kids.incidents','kids','Kids','Ocorrências',array['view','create','approve'],array['kids_class'],72,false),
 ('finance.entries','finance','Financeiro','Lançamentos',array['view','create','edit','delete','export'],'{}',80,false),
 ('finance.payables','finance','Financeiro','Contas a receber e a pagar',array['view','create','edit','delete'],'{}',81,false),
 ('finance.reconciliation','finance','Financeiro','Conciliação',array['view','edit'],'{}',82,false),
 ('finance.closing','finance','Financeiro','Fechamento mensal',array['view','approve'],'{}',83,false),
 ('finance.reports','finance','Financeiro','Relatórios',array['view','export'],'{}',84,false),
 ('finance.digital','finance','Financeiro','Recebimentos digitais',array['view','edit'],'{}',85,false),
 ('finance.registry','finance','Financeiro','Cadastros financeiros',array['view','create','edit','delete'],'{}',86,false);

-- 2. Concessões por pessoa. unit_id nulo = todas as igrejas do ministério.
create table private.permission_grants(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 membership_id uuid not null references public.organization_memberships(id) on delete cascade,
 permission text not null references private.permission_catalog(code),
 unit_id uuid references public.organization_units(id) on delete cascade,
 include_children boolean not null default true,
 actions text[] not null check(cardinality(actions)>0),
 group_kind text check(group_kind in('cell','network','scale_team','kids_class')),
 group_ids uuid[] not null default '{}',
 granted_by uuid not null,
 granted_at timestamptz not null default now(),
 version integer not null default 1 check(version>0),
 check((group_kind is null)=(cardinality(group_ids)=0))
);
create unique index permission_grants_scope_key on private.permission_grants(membership_id,permission,coalesce(unit_id,'00000000-0000-0000-0000-000000000000'::uuid));
create index permission_grants_org on private.permission_grants(organization_id);
create index permission_grants_unit on private.permission_grants(unit_id);
create index permission_grants_permission on private.permission_grants(permission);
alter table private.permission_grants enable row level security;
revoke all on private.permission_grants from public,anon,authenticated,service_role;

-- 3. Modelos prontos (preenchem a matriz; depois podem ser ajustados pessoa a pessoa).
create table private.permission_templates(
 code text primary key,
 label text not null,
 description text not null,
 items jsonb not null check(jsonb_typeof(items)='object')
);
alter table private.permission_templates enable row level security;
revoke all on private.permission_templates from public,anon,authenticated,service_role;
insert into private.permission_templates values
 ('pastor','Pastor','Acompanha pessoas, células, programação, Kids e escalas; vê o Financeiro.',
  '{"people.members":["view","create","edit","export"],"people.visitors":["view","create","edit"],"people.pending_profiles":["view","approve"],"cells.cells":["view","create","edit"],"cells.networks":["view","create","edit"],"cells.reports":["view","approve"],"cells.transfers":["view","approve"],"events.agenda":["view","create","edit"],"events.events":["view","create","edit"],"kids.classes":["view"],"kids.incidents":["view","approve"],"scales.teams":["view"],"scales.schedules":["view"],"finance.reports":["view"]}'),
 ('secretaria','Secretaria','Cadastro de pessoas, perfis pendentes, agenda, eventos e check-in.',
  '{"people.members":["view","create","edit"],"people.visitors":["view","create","edit"],"people.pending_profiles":["view","approve"],"people.import":["create"],"events.agenda":["view","create","edit"],"events.events":["view","create","edit"],"events.checkin":["view","edit"],"kids.checkin":["view","edit"]}'),
 ('tesouraria','Tesouraria','Todo o Financeiro, sem gerir usuários.',
  '{"finance.entries":["view","create","edit","delete","export"],"finance.payables":["view","create","edit","delete"],"finance.reconciliation":["view","edit"],"finance.closing":["view","approve"],"finance.reports":["view","export"],"finance.digital":["view","edit"],"finance.registry":["view","create","edit","delete"]}'),
 ('lider_celula','Líder de célula','A própria célula: relatórios e participantes.',
  '{"cells.cells":["view","edit"],"cells.reports":["view","create"]}'),
 ('supervisor_rede','Supervisor de rede','As células da rede (e sub-redes): relatórios e transferências.',
  '{"cells.cells":["view","edit"],"cells.networks":["view"],"cells.reports":["view","approve"],"cells.transfers":["view","approve"]}'),
 ('lider_escala','Líder de escala','As equipes que lidera: escalas e substituições.',
  '{"scales.teams":["view","edit"],"scales.schedules":["view","create","edit","delete"]}'),
 ('lider_kids','Líder Kids','Turmas, check-in/out e ocorrências do Kids.',
  '{"kids.classes":["view","edit"],"kids.checkin":["view","edit"],"kids.incidents":["view","create"]}'),
 ('comunicacao','Comunicação','Avisos, push, banners e transmissões.',
  '{"communication.notices":["view","create","edit","delete"],"communication.push":["view","create"],"communication.banners":["view","create","edit","delete"],"communication.broadcasts":["view","create","edit","delete"]}');

-- 4. Regra única. O dono tem tudo; os demais só o que foi concedido, dentro da abrangência,
-- com o módulo contratado e, quando a seção é por grupo, só nos grupos concedidos.
create function private.unit_within(p_org uuid,p_unit uuid,p_root uuid,p_children boolean) returns boolean
language sql stable security definer set search_path='' as $$
 select p_root is null or p_unit=p_root or (p_children and exists(
  with recursive up(id,parent) as (
   select u.id,u.parent_unit_id from public.organization_units u where u.id=p_unit and u.organization_id=p_org
   union select u.id,u.parent_unit_id from public.organization_units u join up on u.id=up.parent where u.organization_id=p_org
  ) select 1 from up where up.id=p_root))
$$;
revoke all on function private.unit_within(uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;

-- Módulo contratado pela igreja, sem depender do papel de quem pergunta (a regra antiga
-- private.target_unit_module_enabled também exige acesso por papel à igreja).
create function private.unit_module_contracted(p_org uuid,p_unit uuid,p_module text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare c public.saas_unit_contracts;
begin
 if not exists(select 1 from public.saas_module_catalog where code=p_module) then return false;end if;
 select * into c from public.saas_unit_contracts where organization_id=p_org and unit_id=p_unit;
 if c.id is null or c.status='draft' then return true;end if;
 if c.status<>'active' then return false;end if;
 if c.module_decisions ? p_module then return c.module_decisions->p_module='true'::jsonb;end if;
 return exists(select 1 from public.saas_plan_modules where plan_id=c.plan_id and module_code=p_module and included);
end $$;
revoke all on function private.unit_module_contracted(uuid,uuid,text) from public,anon,authenticated,service_role;

create function private.can(p_org uuid,p_unit uuid,p_permission text,p_action text,p_group uuid default null) returns boolean
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
    and (g.group_kind is null or (p_group is not null and p_group=any(g.group_ids))))
 )
$$;
revoke all on function private.can(uuid,uuid,text,text,uuid) from public,anon,service_role;
grant execute on function private.can(uuid,uuid,text,text,uuid) to authenticated;

-- 5. Gestão das concessões (base para a tela Pessoas › Usuários, fase P2).
-- Só o dono e administradores gerenciam; administrador não concede seções exclusivas do dono
-- (Configurações › Usuários e permissões, separada do cadastro de membros em Pessoas)
-- nem altera o dono. Toda mudança vai para a auditoria com o antes e o depois.
create function private.permission_admin(p_org uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_owner boolean;m public.organization_memberships;cat private.permission_catalog;before jsonb;after jsonb;
 v_unit uuid;v_actions text[];v_kind text;v_groups uuid[];v_children boolean;tpl private.permission_templates;item record;
begin
 perform private.require_confirmed_self_service_email();
 if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'permission_admin_denied' using errcode='42501';end if;
 actor_owner:=private.has_organization_role(p_org,array['owner']::public.membership_role[]);
 if p_action='catalog' then
  return jsonb_build_object('sections',(select coalesce(jsonb_agg(to_jsonb(c) order by c.position),'[]') from private.permission_catalog c),
   'templates',(select coalesce(jsonb_agg(to_jsonb(t) order by t.label),'[]') from private.permission_templates t));
 end if;
 select * into m from public.organization_memberships where id=(p_data->>'membership')::uuid and organization_id=p_org for update;
 if not found then raise exception 'membership_not_found' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('membership',m.id,'role',m.role,'grants',(select coalesce(jsonb_agg(to_jsonb(g)-'organization_id' order by c.position,g.unit_id) ,'[]') from private.permission_grants g join private.permission_catalog c on c.code=g.permission where g.membership_id=m.id));
 end if;
 if m.role='owner' then raise exception 'owner_has_all_permissions' using errcode='22023';end if;
 if m.role='admin' and not actor_owner then raise exception 'permission_admin_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(g) order by g.permission,g.unit_id),'[]') into before from private.permission_grants g where g.membership_id=m.id;

 if p_action in('set','remove') then
  select * into cat from private.permission_catalog where code=p_data->>'permission';
  if not found then raise exception 'invalid_permission' using errcode='22023';end if;
  if cat.owner_only and not actor_owner then raise exception 'permission_admin_denied' using errcode='42501';end if;
  v_unit:=nullif(p_data->>'unit','')::uuid;
  if v_unit is not null and not exists(select 1 from public.organization_units where id=v_unit and organization_id=p_org) then raise exception 'invalid_unit' using errcode='22023';end if;
  if p_action='remove' then
   delete from private.permission_grants where membership_id=m.id and permission=cat.code and unit_id is not distinct from v_unit;
  else
   select array_agg(distinct a order by a) into v_actions from jsonb_array_elements_text(coalesce(p_data->'actions','[]')) a;
   if v_actions is null or not v_actions <@ cat.actions then raise exception 'invalid_actions' using errcode='22023';end if;
   v_kind:=nullif(p_data->>'groupKind','');
   select coalesce(array_agg(distinct x::uuid),'{}') into v_groups from jsonb_array_elements_text(coalesce(p_data->'groups','[]')) x;
   if (v_kind is null)<>(cardinality(v_groups)=0) or (v_kind is not null and not v_kind=any(cat.group_kinds)) or cardinality(v_groups)>200 then raise exception 'invalid_groups' using errcode='22023';end if;
   v_children:=coalesce((p_data->>'includeChildren')::boolean,true);
   insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,group_kind,group_ids,granted_by)
   values(p_org,m.id,cat.code,v_unit,v_children,v_actions,v_kind,v_groups,auth.uid())
   on conflict(membership_id,permission,coalesce(unit_id,'00000000-0000-0000-0000-000000000000'::uuid)) do update
    set include_children=excluded.include_children,actions=excluded.actions,group_kind=excluded.group_kind,group_ids=excluded.group_ids,granted_by=excluded.granted_by,granted_at=now(),version=private.permission_grants.version+1;
  end if;
 elsif p_action='apply_template' then
  select * into tpl from private.permission_templates where code=p_data->>'template';
  if not found then raise exception 'invalid_template' using errcode='22023';end if;
  v_unit:=nullif(p_data->>'unit','')::uuid;
  if v_unit is not null and not exists(select 1 from public.organization_units where id=v_unit and organization_id=p_org) then raise exception 'invalid_unit' using errcode='22023';end if;
  for item in select key,value from jsonb_each(tpl.items) loop
   insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,granted_by)
   select p_org,m.id,item.key,v_unit,true,array(select jsonb_array_elements_text(item.value)),auth.uid()
   on conflict(membership_id,permission,coalesce(unit_id,'00000000-0000-0000-0000-000000000000'::uuid)) do update
    set actions=array(select distinct a from unnest(private.permission_grants.actions||excluded.actions) a order by a),granted_by=excluded.granted_by,granted_at=now(),version=private.permission_grants.version+1;
  end loop;
 elsif p_action='clear' then
  delete from private.permission_grants where membership_id=m.id and (actor_owner or permission not in(select code from private.permission_catalog where owner_only));
 else raise exception 'invalid_action' using errcode='22023';end if;

 select coalesce(jsonb_agg(to_jsonb(g) order by g.permission,g.unit_id),'[]') into after from private.permission_grants g where g.membership_id=m.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'permissions.'||p_action,'organization_membership',m.id::text,jsonb_build_object('before',before,'after',after,'request',p_data));
 return jsonb_build_object('membership',m.id,'grants',after);
end $$;
revoke all on function private.permission_admin(uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.permission_admin(uuid,text,jsonb) to authenticated;

create function public.permission_admin(p_org uuid,p_action text,p_data jsonb) returns jsonb
language sql set search_path='' as $$select private.permission_admin(p_org,p_action,p_data)$$;
revoke all on function public.permission_admin(uuid,text,jsonb) from public,anon;
grant execute on function public.permission_admin(uuid,text,jsonb) to authenticated;
