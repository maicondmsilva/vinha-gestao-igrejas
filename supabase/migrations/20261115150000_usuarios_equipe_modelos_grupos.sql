-- Usuários e permissões, simplificado:
--  · Tipos: Administrador, Pastor, Equipe e Membro (usuário do app). "Equipe" é automático: um membro que recebeu
--    alguma permissão ou função na plataforma (líder de célula, equipe de escala, Kids, atendimento pastoral, grupo).
--  · Igrejas de acesso deixam de ser escolhidas à parte: cada permissão diz em quais igrejas vale e o acesso de
--    leitura àquela igreja é criado junto (o que já existia continua).
--  · Modelos personalizados: a igreja cria modelos com nome e os acessos que cada um dá.
--  · Grupos (Configurações › Grupos): Pastores, Lideranças etc., para segmentar push e publicações.

-- ── Grupos de pessoas: tabelas ──
create table if not exists private.people_groups(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 60),
 description text not null default '' check(length(description)<=240),
 color text not null default '#285c45' check(color ~ '^#[0-9a-fA-F]{6}$'),
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists people_groups_name on private.people_groups(organization_id,lower(name));
create table if not exists private.people_group_members(
 group_id uuid not null references private.people_groups(id) on delete cascade,
 person_id uuid not null references public.people(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 added_by uuid,
 added_at timestamptz not null default now(),
 primary key(group_id,person_id)
);
create index if not exists people_group_members_person on private.people_group_members(person_id);
alter table private.people_groups enable row level security;
alter table private.people_group_members enable row level security;
revoke all on private.people_groups,private.people_group_members from public,anon,authenticated;


-- ── Equipe automática ────────────────────────────────────────────────────────────────────────────
create or replace function private.membership_is_team(p_membership uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select exists(select 1 from private.permission_grants g where g.membership_id=p_membership)
  or exists(
   select 1 from public.organization_memberships m join public.people p on p.organization_id=m.organization_id and p.auth_user_id=m.user_id and p.status<>'rejected'
   where m.id=p_membership and (
    exists(select 1 from public.church_cells c where c.leader_person_id=p.id and c.organization_id=m.organization_id)
    or exists(select 1 from private.scale_members s where s.person_id=p.id and s.organization_id=m.organization_id and s.active)
    or exists(select 1 from private.kids_assignments k where k.person_id=p.id and k.organization_id=m.organization_id and k.active)
    or exists(select 1 from private.pastoral_attendants a where a.person_id=p.id and a.organization_id=m.organization_id and a.active)
    or exists(select 1 from private.people_group_members gm where gm.person_id=p.id and gm.organization_id=m.organization_id)
   ))
$$;
revoke all on function private.membership_is_team(uuid) from public,anon,authenticated;

do $$ declare d text; begin
 d:=pg_get_functiondef('public.staff_directory(uuid)'::regprocedure);
 if position('''team'',private.membership_is_team' in d)=0 then
  if (length(d)-length(replace(d,' ''unit_access'',coalesce(','')))/length(' ''unit_access'',coalesce(')<>1 then raise exception 'staff_directory: trecho não encontrado';end if;
  execute replace(d,' ''unit_access'',coalesce(',' ''team'',private.membership_is_team(m.id),''unit_access'',coalesce(');
 end if;
end $$;

-- ── Igrejas de acesso derivadas das permissões ───────────────────────────────────────────────────
create or replace function private.permission_grant_unit_access() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.unit_id is not null then
  insert into public.membership_unit_access(membership_id,organization_id,unit_id,access_level,include_children)
   select new.membership_id,new.organization_id,new.unit_id,'read',new.include_children
   where not exists(select 1 from public.membership_unit_access a where a.membership_id=new.membership_id and a.unit_id=new.unit_id);
 else
  -- "Todo o ministério": leitura nas igrejas-mãe, com as filhas.
  insert into public.membership_unit_access(membership_id,organization_id,unit_id,access_level,include_children)
   select new.membership_id,new.organization_id,u.id,'read',true from public.organization_units u
   where u.organization_id=new.organization_id and u.parent_unit_id is null and u.status='active'
    and not exists(select 1 from public.membership_unit_access a where a.membership_id=new.membership_id and a.unit_id=u.id);
 end if;
 return new;
end $$;
revoke all on function private.permission_grant_unit_access() from public,anon,authenticated;
drop trigger if exists permission_grant_unit_access on private.permission_grants;
create trigger permission_grant_unit_access after insert or update of unit_id on private.permission_grants for each row execute function private.permission_grant_unit_access();

-- ── Modelos personalizados ───────────────────────────────────────────────────────────────────────
create table if not exists private.permission_custom_templates(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 60),
 description text not null default '' check(length(description)<=240),
 items jsonb not null check(jsonb_typeof(items)='object' and octet_length(items::text)<=8000),
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists permission_custom_templates_name on private.permission_custom_templates(organization_id,lower(name));
alter table private.permission_custom_templates enable row level security;
revoke all on private.permission_custom_templates from public,anon,authenticated;

create or replace function private.permission_custom(p_org uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare tid uuid; tpl private.permission_custom_templates; m public.organization_memberships; item record; v_actions text[]; u uuid; units uuid[]; before jsonb; after jsonb; actor_owner boolean;
begin
 perform private.require_confirmed_self_service_email();
 if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'permission_admin_denied' using errcode='42501';end if;
 actor_owner:=private.has_organization_role(p_org,array['owner']::public.membership_role[]);
 if p_action='custom_templates' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'description',t.description,'items',t.items) order by lower(t.name)) from private.permission_custom_templates t where t.organization_id=p_org),'[]'::jsonb));
 elsif p_action='save_custom_template' then
  if length(btrim(coalesce(p_data->>'name',''))) not between 2 and 60 or length(coalesce(p_data->>'description',''))>240 or jsonb_typeof(p_data->'items')<>'object' or p_data->'items'='{}'::jsonb then raise exception 'invalid_template' using errcode='22023';end if;
  for item in select key,value from jsonb_each(p_data->'items') loop
   if jsonb_typeof(item.value)<>'array' or not exists(select 1 from private.permission_catalog c where c.code=item.key
     and array(select jsonb_array_elements_text(item.value))<@c.actions and jsonb_array_length(item.value)>0 and (actor_owner or not c.owner_only)) then raise exception 'invalid_template' using errcode='22023';end if;
  end loop;
  tid:=nullif(p_data->>'id','')::uuid;
  if tid is null then
   insert into private.permission_custom_templates(organization_id,name,description,items,created_by) values(p_org,btrim(p_data->>'name'),btrim(coalesce(p_data->>'description','')),p_data->'items',auth.uid())
    on conflict(organization_id,lower(name)) do update set description=excluded.description,items=excluded.items,updated_at=clock_timestamp() returning id into tid;
  else
   update private.permission_custom_templates set name=btrim(p_data->>'name'),description=btrim(coalesce(p_data->>'description','')),items=p_data->'items',updated_at=clock_timestamp() where id=tid and organization_id=p_org returning id into tid;
   if tid is null then raise exception 'invalid_template' using errcode='22023';end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'permissions.template_saved','permission_template',tid::text,jsonb_build_object('name',btrim(p_data->>'name')));
  return jsonb_build_object('ok',true,'id',tid);
 elsif p_action='delete_custom_template' then
  delete from private.permission_custom_templates where id=nullif(p_data->>'id','')::uuid and organization_id=p_org;
  return jsonb_build_object('ok',true);
 elsif p_action='apply_custom_template' then
  select * into tpl from private.permission_custom_templates where id=nullif(p_data->>'template','')::uuid and organization_id=p_org;
  if tpl.id is null then raise exception 'invalid_template' using errcode='22023';end if;
  select * into m from public.organization_memberships where id=(p_data->>'membership')::uuid and organization_id=p_org for update;
  if m.id is null then raise exception 'membership_not_found' using errcode='42501';end if;
  if m.role='owner' then raise exception 'owner_has_all_permissions' using errcode='22023';end if;
  if m.role='admin' and not actor_owner then raise exception 'permission_admin_denied' using errcode='42501';end if;
  select coalesce(array_agg(distinct x::uuid),'{}') into units from jsonb_array_elements_text(coalesce(p_data->'units','[]')) x;
  if exists(select 1 from unnest(units) x where not exists(select 1 from public.organization_units o where o.id=x and o.organization_id=p_org)) then raise exception 'invalid_unit' using errcode='22023';end if;
  if cardinality(units)=0 then units:=array[null::uuid];end if;
  select coalesce(jsonb_agg(to_jsonb(g) order by g.permission,g.unit_id),'[]') into before from private.permission_grants g where g.membership_id=m.id;
  foreach u in array units loop
   for item in select key,value from jsonb_each(tpl.items) loop
    if exists(select 1 from private.permission_catalog c where c.code=item.key and (actor_owner or not c.owner_only)) then
     v_actions:=array(select a from jsonb_array_elements_text(item.value) a join private.permission_catalog c on c.code=item.key where a=any(c.actions::text[]));
     if cardinality(v_actions)>0 then
      insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,granted_by)
      values(p_org,m.id,item.key,u,true,v_actions,auth.uid())
      on conflict(membership_id,permission,coalesce(unit_id,'00000000-0000-0000-0000-000000000000'::uuid)) do update
       set actions=array(select distinct a from unnest(private.permission_grants.actions||excluded.actions) a order by a),granted_by=excluded.granted_by,granted_at=now();
     end if;
    end if;
   end loop;
  end loop;
  select coalesce(jsonb_agg(to_jsonb(g) order by g.permission,g.unit_id),'[]') into after from private.permission_grants g where g.membership_id=m.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'permissions.apply_custom_template','organization_membership',m.id::text,jsonb_build_object('before',before,'after',after,'template',tpl.id));
  return jsonb_build_object('membership',m.id,'grants',after);
 end if;
 raise exception 'invalid_action' using errcode='22023';
end $function$;
revoke all on function private.permission_custom(uuid,text,jsonb) from public,anon,authenticated;

do $$ declare d text; begin
 d:=pg_get_functiondef('private.permission_admin(uuid,text,jsonb)'::regprocedure);
 if position('private.permission_custom(' in d)=0 then
  if position(' if p_action=''groups'' then' in d)=0 then raise exception 'permission_admin: trecho não encontrado';end if;
  execute replace(d,' if p_action=''groups'' then',' if p_action in(''custom_templates'',''save_custom_template'',''delete_custom_template'',''apply_custom_template'') then return private.permission_custom(p_org,p_action,p_data);end if;
 if p_action=''groups'' then');
 end if;
end $$;

-- ── Grupos de pessoas (Configurações › Grupos) ───────────────────────────────────────────────────
create or replace function private.people_groups_admin(p_org uuid) returns boolean language sql stable security definer set search_path to '' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor','secretary']::public.membership_role[]) or private.can(p_org,null,'settings.users','edit')
$$;
revoke all on function private.people_groups_admin(uuid) from public,anon,authenticated;

create or replace function public.people_groups(p_org uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare gid uuid; pid uuid; ids uuid[];
begin
 if auth.uid() is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_people_group' using errcode='22023';end if;
 if p_action='list' then
  -- Quem publica ou envia push também lista os grupos para escolher o público.
  if not (private.people_groups_admin(p_org) or private.has_organization_role(p_org,array['leader','finance']::public.membership_role[]) or exists(select 1 from public.organization_units u where u.organization_id=p_org and private.push_unit(p_org,u.id))) then raise exception 'people_group_denied' using errcode='42501';end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'color',g.color,
   'count',(select count(*) from private.people_group_members m where m.group_id=g.id)) order by lower(g.name)) from private.people_groups g where g.organization_id=p_org),'[]'::jsonb));
 end if;
 if not private.people_groups_admin(p_org) then raise exception 'people_group_denied' using errcode='42501';end if;
 if p_action='save' then
  if length(btrim(coalesce(p_data->>'name',''))) not between 2 and 60 or length(coalesce(p_data->>'description',''))>240 or coalesce(p_data->>'color','#285c45') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'invalid_people_group' using errcode='22023';end if;
  gid:=nullif(p_data->>'id','')::uuid;
  if gid is null then
   if (select count(*) from private.people_groups where organization_id=p_org)>=200 then raise exception 'invalid_people_group' using errcode='22023';end if;
   insert into private.people_groups(organization_id,name,description,color,created_by) values(p_org,btrim(p_data->>'name'),btrim(coalesce(p_data->>'description','')),coalesce(p_data->>'color','#285c45'),auth.uid()) returning id into gid;
  else
   update private.people_groups set name=btrim(p_data->>'name'),description=btrim(coalesce(p_data->>'description','')),color=coalesce(p_data->>'color',color),updated_at=clock_timestamp() where id=gid and organization_id=p_org returning id into gid;
   if gid is null then raise exception 'invalid_people_group' using errcode='22023';end if;
  end if;
  return jsonb_build_object('ok',true,'id',gid);
 elsif p_action='delete' then
  delete from private.people_groups where id=nullif(p_data->>'id','')::uuid and organization_id=p_org;
  return jsonb_build_object('ok',true);
 elsif p_action='members' then
  gid:=nullif(p_data->>'id','')::uuid;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'unit',u.name) order by p.full_name) from private.people_group_members m join public.people p on p.id=m.person_id left join public.organization_units u on u.id=p.unit_id where m.group_id=gid and m.organization_id=p_org),'[]'::jsonb));
 elsif p_action in('add','remove') then
  gid:=nullif(p_data->>'id','')::uuid; pid:=nullif(p_data->>'person','')::uuid;
  if not exists(select 1 from private.people_groups where id=gid and organization_id=p_org) or not exists(select 1 from public.people where id=pid and organization_id=p_org) then raise exception 'invalid_people_group' using errcode='22023';end if;
  if p_action='add' then insert into private.people_group_members(group_id,person_id,organization_id,added_by) values(gid,pid,p_org,auth.uid()) on conflict do nothing;
  else delete from private.people_group_members where group_id=gid and person_id=pid;end if;
  return jsonb_build_object('ok',true);
 elsif p_action='person' then
  pid:=nullif(p_data->>'person','')::uuid;
  return jsonb_build_object('items',coalesce((select jsonb_agg(m.group_id) from private.people_group_members m where m.person_id=pid and m.organization_id=p_org),'[]'::jsonb));
 elsif p_action='set_person' then
  pid:=nullif(p_data->>'person','')::uuid;
  if not exists(select 1 from public.people where id=pid and organization_id=p_org) or jsonb_typeof(p_data->'groups')<>'array' then raise exception 'invalid_people_group' using errcode='22023';end if;
  select coalesce(array_agg(distinct x::uuid),'{}') into ids from jsonb_array_elements_text(p_data->'groups') x;
  if exists(select 1 from unnest(ids) x where not exists(select 1 from private.people_groups g where g.id=x and g.organization_id=p_org)) then raise exception 'invalid_people_group' using errcode='22023';end if;
  delete from private.people_group_members where person_id=pid and organization_id=p_org and not group_id=any(ids);
  insert into private.people_group_members(group_id,person_id,organization_id,added_by) select x,pid,p_org,auth.uid() from unnest(ids) x on conflict do nothing;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_people_group' using errcode='22023';
end $function$;
revoke all on function public.people_groups(uuid,text,jsonb) from public,anon;
grant execute on function public.people_groups(uuid,text,jsonb) to authenticated;

-- Push: novo filtro "peopleGroups" (pessoas dos grupos escolhidos).
do $$ declare d text; begin
 d:=pg_get_functiondef('private.push_audience_check(jsonb)'::regprocedure);
 if position('peopleGroups' in d)=0 then
  if position('if k not in(''roles'',' in d)=0 or position('unnest(array[''cells'',''groups''])' in d)=0 then raise exception 'push_audience_check: trecho não encontrado';end if;
  d:=replace(d,'if k not in(''roles'',','if k not in(''peopleGroups'',''roles'',');
  d:=replace(d,'unnest(array[''cells'',''groups''])','unnest(array[''cells'',''groups'',''peopleGroups''])');
  execute d;
 end if;
 d:=pg_get_functiondef('private.push_audience(uuid,uuid[],jsonb)'::regprocedure);
 if position('peopleGroups' in d)=0 then
  if position('and (not p_audience ? ''roles''' in d)=0 or position('?| array[''cells'',''groups'',' in d)=0 then raise exception 'push_audience: trecho não encontrado';end if;
  d:=replace(d,'?| array[''cells'',''groups'',','?| array[''peopleGroups'',''cells'',''groups'',');
  d:=replace(d,'and (not p_audience ? ''roles''','and (not p_audience ? ''peopleGroups'' or exists(select 1 from private.people_group_members pg where pg.person_id=p.id and pg.organization_id=p_org and pg.group_id::text in(select jsonb_array_elements_text(p_audience->''peopleGroups''))))
  and (not p_audience ? ''roles''');
  execute d;
 end if;
end $$;

do $$ declare d text; begin
 d:=pg_get_functiondef('private.push_segments(uuid,uuid,text,jsonb)'::regprocedure);
 if position('''peopleGroups''' in d)=0 then execute replace(d,'array[''roles'',''cells'',','array[''peopleGroups'',''roles'',''cells'',');end if;
end $$;
