-- Grupos, Cargos e Funções (análise docs/ANALISE-GRUPOS-CARGOS-FUNCOES.md).
-- Cargo: o que a pessoa é na igreja (vários ao mesmo tempo, com histórico).
-- Função: o que a pessoa faz em um grupo (célula, rede, ministério), com marca de liderança e modelo de acesso.
-- Acesso pela função: sempre proposto; o dono ou um administrador confirma com um clique.

-- ── Catálogos ────────────────────────────────────────────────────────────────────────────────────
create table if not exists private.church_positions(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 60),
 name_female text not null default '' check(length(name_female)<=60),
 pastoral boolean not null default false,
 show_in_app boolean not null default true,
 sort integer not null default 100 check(sort between 0 and 10000),
 active boolean not null default true,
 system_key text check(system_key ~ '^[a-z_]{2,30}$'),
 version integer not null default 1 check(version>0),
 created_at timestamptz not null default now(),
 unique(id,organization_id)
);
create unique index if not exists church_positions_name on private.church_positions(organization_id,lower(btrim(name)));
create unique index if not exists church_positions_key on private.church_positions(organization_id,system_key) where system_key is not null;

create table if not exists private.person_positions(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 person_id uuid not null,
 position_id uuid not null,
 unit_id uuid references public.organization_units(id) on delete set null,
 since date,
 until date,
 created_by uuid,
 created_at timestamptz not null default now(),
 check(until is null or since is null or until>=since),
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete cascade,
 foreign key(position_id,organization_id) references private.church_positions(id,organization_id) on delete restrict
);
create unique index if not exists person_positions_active on private.person_positions(person_id,position_id) where until is null;
create index if not exists person_positions_position on private.person_positions(position_id) where until is null;

create table if not exists private.group_functions(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 kind text not null check(kind in('cell','network','ministry')),
 name text not null check(length(btrim(name)) between 2 and 60),
 name_female text not null default '' check(length(name_female)<=60),
 leadership boolean not null default false,
 template_code text check(template_code is null or length(template_code) between 2 and 80),
 sort integer not null default 100 check(sort between 0 and 10000),
 active boolean not null default true,
 system_key text check(system_key ~ '^[a-z_]{2,30}$'),
 version integer not null default 1 check(version>0),
 created_at timestamptz not null default now(),
 unique(id,organization_id),
 unique(id,organization_id,kind)
);
create unique index if not exists group_functions_name on private.group_functions(organization_id,kind,lower(btrim(name)));
create unique index if not exists group_functions_key on private.group_functions(organization_id,kind,system_key) where system_key is not null;

-- Vínculo pessoa ↔ grupo com a função. Participantes comuns de célula continuam em church_cell_participants.
create table if not exists private.group_assignments(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid references public.organization_units(id) on delete set null,
 kind text not null check(kind in('cell','network','ministry')),
 group_id uuid not null,
 person_id uuid not null,
 function_id uuid not null,
 since date not null default current_date,
 until date,
 source text not null default 'panel' check(source in('panel','app','sync','import')),
 created_by uuid,
 created_at timestamptz not null default now(),
 check(until is null or until>=since),
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete cascade,
 foreign key(function_id,organization_id,kind) references private.group_functions(id,organization_id,kind) on delete restrict
);
create unique index if not exists group_assignments_active on private.group_assignments(kind,group_id,person_id,function_id) where until is null;
create index if not exists group_assignments_person on private.group_assignments(person_id) where until is null;
create index if not exists group_assignments_group on private.group_assignments(group_id) where until is null;
create index if not exists group_assignments_function on private.group_assignments(function_id);

-- Equipe de escala ligada ao ministério (Louvor › Banda, Vocal…).
alter table private.scale_teams add column if not exists ministry_id uuid references private.community_groups(id) on delete set null;
create index if not exists scale_teams_ministry on private.scale_teams(ministry_id) where ministry_id is not null;

-- Acessos propostos pela função: ninguém ganha nem perde acesso sem confirmação.
create table if not exists private.access_proposals(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 assignment_id uuid references private.group_assignments(id) on delete set null,
 person_id uuid not null,
 action text not null check(action in('grant','revoke')),
 template_code text not null,
 kind text not null check(kind in('cell','network','ministry')),
 group_id uuid not null,
 unit_id uuid,
 status text not null default 'pending' check(status in('pending','approved','dismissed')),
 applied jsonb not null default '{}',
 created_at timestamptz not null default now(),
 decided_by uuid,
 decided_at timestamptz,
 foreign key(person_id,organization_id) references public.people(id,organization_id) on delete cascade
);
create index if not exists access_proposals_pending on private.access_proposals(organization_id,created_at desc) where status='pending';
create index if not exists access_proposals_assignment on private.access_proposals(assignment_id);
create unique index if not exists access_proposals_once on private.access_proposals(assignment_id,action) where status='pending';

-- Liderança no app: telefone só com autorização do líder; mensagens pelo app.
create table if not exists private.leader_contact_prefs(
 person_id uuid primary key references public.people(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 show_phone boolean not null default false,
 updated_at timestamptz not null default now()
);
create table if not exists private.leadership_messages(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid,
 from_person uuid not null references public.people(id) on delete cascade,
 to_person uuid not null references public.people(id) on delete cascade,
 reply_to uuid references private.leadership_messages(id) on delete set null,
 body text not null check(length(btrim(body)) between 2 and 1000),
 created_at timestamptz not null default now(),
 read_at timestamptz,
 check(from_person<>to_person)
);
create index if not exists leadership_messages_to on private.leadership_messages(to_person,created_at desc);
create index if not exists leadership_messages_from on private.leadership_messages(from_person,created_at desc);

alter table private.church_positions enable row level security;
alter table private.person_positions enable row level security;
alter table private.group_functions enable row level security;
alter table private.group_assignments enable row level security;
alter table private.access_proposals enable row level security;
alter table private.leader_contact_prefs enable row level security;
alter table private.leadership_messages enable row level security;
revoke all on private.church_positions,private.person_positions,private.group_functions,private.group_assignments,private.access_proposals,private.leader_contact_prefs,private.leadership_messages from public,anon,authenticated;

-- ── Padrões (a igreja edita, arquiva e cria outros) ─────────────────────────────────────────────
create or replace function private.roles_seed(p_org uuid) returns void
language plpgsql security definer set search_path to '' as $$
begin
 if not exists(select 1 from private.church_positions where organization_id=p_org) then
  insert into private.church_positions(organization_id,name,name_female,pastoral,sort,system_key) values
   (p_org,'Pastor','Pastora',true,10,'pastor'),
   (p_org,'Pastor auxiliar','Pastora auxiliar',true,20,'pastor_aux'),
   (p_org,'Presbítero','Presbítera',false,30,'presbitero'),
   (p_org,'Diácono','Diaconisa',false,40,'diacono'),
   (p_org,'Evangelista','',false,50,'evangelista'),
   (p_org,'Missionário','Missionária',false,60,'missionario'),
   (p_org,'Obreiro','Obreira',false,70,'obreiro')
  on conflict do nothing;
 end if;
 if not exists(select 1 from private.group_functions where organization_id=p_org) then
  insert into private.group_functions(organization_id,kind,name,name_female,leadership,template_code,sort,system_key) values
   (p_org,'cell','Líder','',true,'lider_celula',10,'leader'),
   (p_org,'cell','Vice-líder','',true,'lider_celula',20,'vice'),
   (p_org,'cell','Líder em treinamento','',false,null,30,'trainee'),
   (p_org,'cell','Anfitrião','Anfitriã',false,null,40,'host'),
   (p_org,'cell','Participante','',false,null,90,'participant'),
   (p_org,'network','Pastor de rede','Pastora de rede',true,'supervisor_rede',10,'network_pastor'),
   (p_org,'network','Supervisor','Supervisora',true,'supervisor_rede',20,'supervisor'),
   (p_org,'network','Discipulador','Discipuladora',false,null,30,'disciple'),
   (p_org,'ministry','Líder','',true,'lider_escala',10,'leader'),
   (p_org,'ministry','Vice-líder','',true,'lider_escala',20,'vice'),
   (p_org,'ministry','Coordenador','Coordenadora',false,null,30,'coordinator'),
   (p_org,'ministry','Integrante','',false,null,90,'member')
  on conflict do nothing;
 end if;
end $$;
revoke all on function private.roles_seed(uuid) from public,anon,authenticated;

create or replace function private.gendered(p_name text, p_female text, p_gender text) returns text
language sql immutable set search_path to '' as $$
 select case when p_gender='Feminino' and coalesce(btrim(p_female),'')<>'' then p_female else p_name end
$$;

create or replace function private.roles_manage(p_org uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor','secretary']::public.membership_role[])
  or private.can(p_org,null,'settings.users','edit') or private.can(p_org,null,'people.members','edit')
$$;
revoke all on function private.roles_manage(uuid) from public,anon,authenticated;

create or replace function private.group_label(p_kind text, p_group uuid) returns text
language sql stable security definer set search_path to '' as $$
 select case p_kind
  when 'cell' then (select name from public.church_cells where id=p_group)
  when 'network' then (select name from public.church_cell_networks where id=p_group)
  when 'ministry' then (select name from private.community_groups where id=p_group) end
$$;
revoke all on function private.group_label(text,uuid) from public,anon,authenticated;

create or replace function private.group_unit(p_kind text, p_group uuid, p_org uuid) returns uuid
language sql stable security definer set search_path to '' as $$
 select case p_kind
  when 'cell' then (select unit_id from public.church_cells where id=p_group and organization_id=p_org and status='active')
  when 'network' then (select unit_id from public.church_cell_networks where id=p_group and organization_id=p_org and status='active')
  when 'ministry' then (select unit_id from private.community_groups where id=p_group and organization_id=p_org and active) end
$$;
revoke all on function private.group_unit(text,uuid,uuid) from public,anon,authenticated;

-- ── Visão única da pessoa: cargos e todos os grupos ──────────────────────────────────────────────
create or replace function private.person_roles(p_person uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
 with me as (select id,organization_id,gender from public.people where id=p_person)
 select jsonb_build_object(
  'positions',coalesce((select jsonb_agg(jsonb_build_object('id',pp.id,'positionId',c.id,'name',private.gendered(c.name,c.name_female,me.gender),'pastoral',c.pastoral,
    'since',pp.since,'unit',u.name) order by c.sort,c.name) from private.person_positions pp join private.church_positions c on c.id=pp.position_id
    left join public.organization_units u on u.id=pp.unit_id where pp.person_id=me.id and pp.until is null),'[]'::jsonb),
  'groups',coalesce((select jsonb_agg(g order by (g->>'leadership')::boolean desc,g->>'kindOrder',g->>'group') from (
    select jsonb_build_object('id',a.id,'kind',a.kind,'kindOrder',case a.kind when 'network' then 1 when 'cell' then 2 else 3 end,'groupId',a.group_id,'group',private.group_label(a.kind,a.group_id),
     'functionId',f.id,'function',private.gendered(f.name,f.name_female,me.gender),'leadership',f.leadership,'since',a.since,'editable',true) g
    from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.person_id=me.id and a.until is null
    union all
    select jsonb_build_object('id',null,'kind','cell','kindOrder',2,'groupId',c.id,'group',c.name,'functionId',null,'function','Participante','leadership',false,'since',null,'editable',false)
    from public.church_cell_participants cp join public.church_cells c on c.id=cp.cell_id
    where cp.person_id=me.id and cp.status='active' and c.status='active'
     and not exists(select 1 from private.group_assignments a where a.person_id=me.id and a.kind='cell' and a.group_id=c.id and a.until is null)
    union all
    select jsonb_build_object('id',null,'kind','scale','kindOrder',4,'groupId',t.id,'group',coalesce(m.name||' · ','')||t.name,'functionId',null,
     'function',coalesce(r.name,'Integrante'),'leadership',false,'since',null,'editable',false)
    from private.scale_members s join private.scale_teams t on t.id=s.team_id left join private.scale_roles r on r.id=s.role_id left join private.community_groups m on m.id=t.ministry_id
    where s.person_id=me.id and s.active and t.active
    union all
    select jsonb_build_object('id',null,'kind','kids','kindOrder',5,'groupId',null,'group','Área Kids','functionId',null,
     'function',case k.role when 'supervisor' then 'Supervisão' when 'reception' then 'Recepção' when 'teacher' then 'Professor(a)' else 'Auxiliar' end,'leadership',k.role='supervisor','since',null,'editable',false)
    from private.kids_team k where k.person_id=me.id and k.active
  ) x(g)),'[]'::jsonb))
 from me
$$;
revoke all on function private.person_roles(uuid) from public,anon,authenticated;

-- "Grupo" exibido na lista de Pessoas: a liderança principal, senão a célula, senão o ministério.
create or replace function private.person_group_refresh(p_person uuid) returns void
language plpgsql security definer set search_path to '' as $$
declare v text;
begin
 select coalesce(
  (select private.group_label(a.kind,a.group_id) from private.group_assignments a join private.group_functions f on f.id=a.function_id
    where a.person_id=p_person and a.until is null and f.leadership order by case a.kind when 'cell' then 1 when 'network' then 2 else 3 end,a.since limit 1),
  (select c.name from public.church_cell_participants cp join public.church_cells c on c.id=cp.cell_id where cp.person_id=p_person and cp.status='active' and c.status='active' order by cp.created_at limit 1),
  (select private.group_label(a.kind,a.group_id) from private.group_assignments a where a.person_id=p_person and a.until is null order by case a.kind when 'cell' then 1 when 'ministry' then 2 else 3 end,a.since limit 1)) into v;
 if v is not null then update public.people set group_name=v where id=p_person and group_name is distinct from v; end if;
end $$;
revoke all on function private.person_group_refresh(uuid) from public,anon,authenticated;

-- ── Sincronização com Células, Redes, Ministérios e "Pastor" ────────────────────────────────────
create or replace function private.position_pastor_sync() returns trigger
language plpgsql security definer set search_path to '' as $$
declare pid uuid:=coalesce(new.person_id,old.person_id); v boolean;
begin
 select exists(select 1 from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=pid and pp.until is null and c.pastoral) into v;
 update public.people set is_pastor=v where id=pid and is_pastor is distinct from v;
 return null;
end $$;
drop trigger if exists person_positions_pastor on private.person_positions;
create trigger person_positions_pastor after insert or update or delete on private.person_positions for each row execute function private.position_pastor_sync();

-- Quem marca "Pastor" na ficha do usuário ganha o cargo; desmarcar encerra os cargos pastorais.
create or replace function private.people_pastor_flag() returns trigger
language plpgsql security definer set search_path to '' as $$
declare pos uuid;
begin
 if pg_trigger_depth()>1 or new.is_pastor is not distinct from old.is_pastor then return new; end if;
 if new.is_pastor then
  perform private.roles_seed(new.organization_id);
  if not exists(select 1 from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=new.id and pp.until is null and c.pastoral) then
   select id into pos from private.church_positions where organization_id=new.organization_id and system_key='pastor';
   if pos is null then select id into pos from private.church_positions where organization_id=new.organization_id and pastoral and active order by sort limit 1; end if;
   if pos is not null then insert into private.person_positions(organization_id,person_id,position_id,unit_id,since,created_by) values(new.organization_id,new.id,pos,new.unit_id,current_date,auth.uid()) on conflict do nothing; end if;
  end if;
 else
  update private.person_positions pp set until=current_date from private.church_positions c where c.id=pp.position_id and c.pastoral and pp.person_id=new.id and pp.until is null;
 end if;
 return new;
end $$;
drop trigger if exists people_pastor_flag on public.people;
create trigger people_pastor_flag after update of is_pastor on public.people for each row execute function private.people_pastor_flag();

-- Líder da célula e supervisor da rede refletem a função (e vice-versa).
create or replace function private.assignment_after() returns trigger
language plpgsql security definer set search_path to '' as $$
declare f private.group_functions; r private.group_assignments:=coalesce(new,old); nm text;
begin
 select * into f from private.group_functions where id=r.function_id;
 if pg_trigger_depth()=1 then
  if r.kind='cell' and f.system_key='leader' then
   if tg_op<>'DELETE' and new.until is null then
    select full_name into nm from public.people where id=new.person_id;
    update public.church_cells set leader_person_id=new.person_id,leader_name=left(nm,120),version=version+1,updated_at=now()
     where id=new.group_id and leader_person_id is distinct from new.person_id
      and (leader_person_id is null or not exists(select 1 from private.group_assignments x where x.kind='cell' and x.group_id=new.group_id and x.person_id=leader_person_id and x.function_id=f.id and x.until is null and x.id<>new.id));
   else
    update public.church_cells c set leader_person_id=(select x.person_id from private.group_assignments x where x.kind='cell' and x.group_id=r.group_id and x.function_id=f.id and x.until is null and x.id<>r.id order by x.since limit 1),
     leader_name=coalesce((select left(p.full_name,120) from private.group_assignments x join public.people p on p.id=x.person_id where x.kind='cell' and x.group_id=r.group_id and x.function_id=f.id and x.until is null and x.id<>r.id order by x.since limit 1),''),
     version=version+1,updated_at=now() where c.id=r.group_id and c.leader_person_id=r.person_id;
   end if;
  elsif r.kind='network' and f.system_key='supervisor' then
   if tg_op<>'DELETE' and new.until is null then
    select full_name into nm from public.people where id=new.person_id;
    update public.church_cell_networks set supervisor_person_id=new.person_id,supervisor_name=left(nm,120),version=version+1,updated_at=now()
     where id=new.group_id and supervisor_person_id is null;
   else
    update public.church_cell_networks n set supervisor_person_id=(select x.person_id from private.group_assignments x where x.kind='network' and x.group_id=r.group_id and x.function_id=f.id and x.until is null and x.id<>r.id order by x.since limit 1),
     supervisor_name=coalesce((select left(p.full_name,120) from private.group_assignments x join public.people p on p.id=x.person_id where x.kind='network' and x.group_id=r.group_id and x.function_id=f.id and x.until is null and x.id<>r.id order by x.since limit 1),''),
     version=version+1,updated_at=now() where n.id=r.group_id and n.supervisor_person_id=r.person_id;
   end if;
  end if;
 end if;
 -- Acesso proposto: entrou numa função de liderança com modelo → conceder; saiu → retirar o que foi concedido.
 if f.leadership and f.template_code is not null then
  if tg_op='INSERT' and new.until is null then
   insert into private.access_proposals(organization_id,assignment_id,person_id,action,template_code,kind,group_id,unit_id)
   values(new.organization_id,new.id,new.person_id,'grant',f.template_code,new.kind,new.group_id,coalesce(new.unit_id,private.group_unit(new.kind,new.group_id,new.organization_id)))
   on conflict do nothing;
  elsif tg_op='UPDATE' and old.until is null and new.until is not null then
   update private.access_proposals set status='dismissed',decided_at=now(),decided_by=auth.uid() where assignment_id=new.id and action='grant' and status='pending';
   insert into private.access_proposals(organization_id,assignment_id,person_id,action,template_code,kind,group_id,unit_id)
   select new.organization_id,new.id,new.person_id,'revoke',p.template_code,new.kind,new.group_id,p.unit_id
   from private.access_proposals p where p.assignment_id=new.id and p.action='grant' and p.status='approved' limit 1
   on conflict do nothing;
  end if;
 end if;
 perform private.person_group_refresh(r.person_id);
 return null;
end $$;
drop trigger if exists group_assignments_after on private.group_assignments;
create trigger group_assignments_after after insert or update or delete on private.group_assignments for each row execute function private.assignment_after();

create or replace function private.cell_leader_sync() returns trigger
language plpgsql security definer set search_path to '' as $$
declare fid uuid;
begin
 if pg_trigger_depth()>1 or new.leader_person_id is not distinct from (case when tg_op='UPDATE' then old.leader_person_id end) then return null; end if;
 perform private.roles_seed(new.organization_id);
 select id into fid from private.group_functions where organization_id=new.organization_id and kind='cell' and system_key='leader';
 if fid is null then return null; end if;
 if tg_op='UPDATE' and old.leader_person_id is not null then
  update private.group_assignments set until=greatest(since,current_date) where kind='cell' and group_id=new.id and person_id=old.leader_person_id and function_id=fid and until is null;
 end if;
 if new.leader_person_id is not null then
  insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source,created_by)
  values(new.organization_id,new.unit_id,'cell',new.id,new.leader_person_id,fid,'sync',auth.uid()) on conflict do nothing;
 end if;
 return null;
end $$;
drop trigger if exists church_cells_leader_sync on public.church_cells;
create trigger church_cells_leader_sync after insert or update of leader_person_id on public.church_cells for each row execute function private.cell_leader_sync();

create or replace function private.network_supervisor_sync() returns trigger
language plpgsql security definer set search_path to '' as $$
declare fid uuid;
begin
 if pg_trigger_depth()>1 or new.supervisor_person_id is not distinct from (case when tg_op='UPDATE' then old.supervisor_person_id end) then return null; end if;
 perform private.roles_seed(new.organization_id);
 select id into fid from private.group_functions where organization_id=new.organization_id and kind='network' and system_key='supervisor';
 if fid is null then return null; end if;
 if tg_op='UPDATE' and old.supervisor_person_id is not null then
  update private.group_assignments set until=greatest(since,current_date) where kind='network' and group_id=new.id and person_id=old.supervisor_person_id and function_id=fid and until is null;
 end if;
 if new.supervisor_person_id is not null then
  insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source,created_by)
  values(new.organization_id,new.unit_id,'network',new.id,new.supervisor_person_id,fid,'sync',auth.uid()) on conflict do nothing;
 end if;
 return null;
end $$;
drop trigger if exists church_cell_networks_supervisor_sync on public.church_cell_networks;
create trigger church_cell_networks_supervisor_sync after insert or update of supervisor_person_id on public.church_cell_networks for each row execute function private.network_supervisor_sync();

-- Pedido aprovado no app ("Ministérios e departamentos") vira Integrante; saiu, encerra.
create or replace function private.ministry_participation_sync() returns trigger
language plpgsql security definer set search_path to '' as $$
declare fid uuid;
begin
 if new.status is not distinct from (case when tg_op='UPDATE' then old.status end) then return null; end if;
 perform private.roles_seed(new.organization_id);
 select id into fid from private.group_functions where organization_id=new.organization_id and kind='ministry' and system_key='member';
 if fid is null then return null; end if;
 if new.status='approved' then
  if not exists(select 1 from private.group_assignments where kind='ministry' and group_id=new.group_id and person_id=new.person_id and until is null) then
   insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source,created_by)
   values(new.organization_id,new.unit_id,'ministry',new.group_id,new.person_id,fid,'app',auth.uid()) on conflict do nothing;
  end if;
 elsif new.status='left' then
  update private.group_assignments set until=greatest(since,current_date) where kind='ministry' and group_id=new.group_id and person_id=new.person_id and function_id=fid and until is null;
 end if;
 return null;
end $$;
drop trigger if exists community_participation_roles on private.community_participation;
create trigger community_participation_roles after insert or update of status on private.community_participation for each row execute function private.ministry_participation_sync();

create or replace function private.cell_participant_group() returns trigger
language plpgsql security definer set search_path to '' as $$
begin perform private.person_group_refresh(coalesce(new.person_id,old.person_id)); return null; end $$;
drop trigger if exists church_cell_participants_group on public.church_cell_participants;
create trigger church_cell_participants_group after insert or update of status on public.church_cell_participants for each row execute function private.cell_participant_group();

-- ── Aplicar ou retirar um modelo de acesso limitado ao grupo ────────────────────────────────────
create or replace function private.template_items(p_org uuid, p_code text) returns jsonb
language sql stable security definer set search_path to '' as $$
 select coalesce((select items from private.permission_templates where code=p_code),
  (select items from private.permission_custom_templates where organization_id=p_org and p_code='custom:'||id::text))
$$;
revoke all on function private.template_items(uuid,text) from public,anon,authenticated;

create or replace function private.template_label(p_org uuid, p_code text) returns text
language sql stable security definer set search_path to '' as $$
 select coalesce((select label from private.permission_templates where code=p_code),
  (select name from private.permission_custom_templates where organization_id=p_org and p_code='custom:'||id::text))
$$;
revoke all on function private.template_label(uuid,text) from public,anon,authenticated;

create or replace function private.proposal_apply(p private.access_proposals, p_membership uuid) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare items jsonb:=private.template_items(p.organization_id,p.template_code); item record; cat private.permission_catalog; g private.permission_grants;
 v_kind text; v_ids uuid[]; v_actions text[]; done jsonb:='[]'; skipped jsonb:='[]';
begin
 if items is null then raise exception 'template_missing' using errcode='22023'; end if;
 v_kind:=case p.kind when 'ministry' then 'scale_team' else p.kind end;
 v_ids:=case p.kind when 'ministry' then coalesce((select array_agg(t.id) from private.scale_teams t where t.ministry_id=p.group_id and t.active),'{}') else array[p.group_id] end;
 for item in select key,value from jsonb_each(items) loop
  select * into cat from private.permission_catalog where code=item.key;
  if not found or cat.owner_only then continue; end if;
  v_actions:=array(select a from jsonb_array_elements_text(item.value) a where a=any(cat.actions));
  if cardinality(v_actions)=0 then continue; end if;
  select * into g from private.permission_grants where membership_id=p_membership and permission=item.key and unit_id is not distinct from p.unit_id for update;
  if p.action='grant' then
   if cardinality(cat.group_kinds)>0 then
    if not v_kind=any(cat.group_kinds) or cardinality(v_ids)=0 then skipped:=skipped||to_jsonb(item.key); continue; end if;
    if g.id is null then
     insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,group_kind,group_ids,granted_by)
     values(p.organization_id,p_membership,item.key,p.unit_id,true,v_actions,v_kind,v_ids,auth.uid());
    elsif g.group_kind=v_kind then
     update private.permission_grants set group_ids=array(select distinct x from unnest(group_ids||v_ids) x),actions=array(select distinct a from unnest(actions||v_actions) a order by a),granted_by=auth.uid(),granted_at=now(),version=version+1 where id=g.id;
    else skipped:=skipped||to_jsonb(item.key); continue; end if;
   else
    if g.id is null then
     insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,granted_by)
     values(p.organization_id,p_membership,item.key,p.unit_id,true,v_actions,auth.uid());
    elsif g.group_kind is null then
     update private.permission_grants set actions=array(select distinct a from unnest(actions||v_actions) a order by a),granted_by=auth.uid(),granted_at=now(),version=version+1 where id=g.id;
    else skipped:=skipped||to_jsonb(item.key); continue; end if;
   end if;
   done:=done||to_jsonb(item.key);
  else
   -- Retirar: só o que é deste grupo; acessos amplos ou dados à mão continuam.
   if g.id is null then continue; end if;
   if g.group_kind=v_kind then
    if cardinality(array(select x from unnest(g.group_ids) x where not x=any(v_ids)))=0 then delete from private.permission_grants where id=g.id;
    else update private.permission_grants set group_ids=array(select x from unnest(group_ids) x where not x=any(v_ids)),granted_by=auth.uid(),granted_at=now(),version=version+1 where id=g.id; end if;
    done:=done||to_jsonb(item.key);
   elsif g.group_kind is null and cardinality(cat.group_kinds)=0 and p.applied ? 'created' and p.applied->'created' ? item.key then
    delete from private.permission_grants where id=g.id; done:=done||to_jsonb(item.key);
   end if;
  end if;
 end loop;
 return jsonb_build_object('changed',done,'skipped',skipped);
end $$;
revoke all on function private.proposal_apply(private.access_proposals,uuid) from public,anon,authenticated;

-- ── Painel: catálogos, cargos e funções da pessoa, busca de grupos, acessos propostos ────────────
create or replace function public.church_roles(p_org uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare actor uuid:=auth.uid(); manage boolean; pid uuid; gid uuid; fid uuid; v_unit uuid; v_kind text; q text; r jsonb; v int;
 pos private.church_positions; fn private.group_functions; pr private.access_proposals; mid uuid; res jsonb; lbl jsonb;
begin
 if actor is null or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>16000 then raise exception 'invalid_roles' using errcode='22023'; end if;
 if not exists(select 1 from public.organizations where id=p_org and status in('active','trial')) then raise exception 'roles_denied' using errcode='42501'; end if;
 manage:=private.roles_manage(p_org);
 perform private.roles_seed(p_org);

 if p_action='catalog' then
  if not (manage or private.people_list_allowed(p_org,(select id from public.organization_units where organization_id=p_org order by created_at limit 1))
    or private.has_organization_role(p_org,array['owner','admin','pastor','secretary','leader']::public.membership_role[])) then raise exception 'roles_denied' using errcode='42501'; end if;
  select coalesce(labels,'{}') into lbl from public.ministry_language where organization_id=p_org;
  return jsonb_build_object('canManage',manage,'canApprove',private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]),
   'label',coalesce(lbl->>'pessoas.cargo','Cargo'),'labelPlural',coalesce(lbl->>'pessoas.cargos','Cargos'),
   'positions',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'nameFemale',c.name_female,'pastoral',c.pastoral,'showInApp',c.show_in_app,'sort',c.sort,'active',c.active,'system',c.system_key is not null,'version',c.version,
     'count',(select count(*) from private.person_positions pp where pp.position_id=c.id and pp.until is null)) order by c.active desc,c.sort,c.name) from private.church_positions c where c.organization_id=p_org),'[]'),
   'functions',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'kind',f.kind,'name',f.name,'nameFemale',f.name_female,'leadership',f.leadership,'template',f.template_code,'templateLabel',private.template_label(p_org,f.template_code),
     'sort',f.sort,'active',f.active,'system',f.system_key,'version',f.version,'count',(select count(*) from private.group_assignments x where x.function_id=f.id and x.until is null)) order by f.kind,f.active desc,f.sort,f.name)
     from private.group_functions f where f.organization_id=p_org),'[]'),
   'templates',(select coalesce(jsonb_agg(x order by x->>'label'),'[]') from (
     select jsonb_build_object('code',t.code,'label',t.label,'description',t.description) x from private.permission_templates t where t.code<>'tesouraria'
     union all select jsonb_build_object('code','custom:'||c.id,'label',c.name,'description',c.description) from private.permission_custom_templates c where c.organization_id=p_org) y),
   'pendingAccess',(select count(*) from private.access_proposals where organization_id=p_org and status='pending'),
   'toReview',(select count(*) from public.people p where p.organization_id=p_org and p.status='active' and coalesce(btrim(p.group_name),'')<>''
     and not exists(select 1 from private.group_assignments a where a.person_id=p.id and a.until is null)
     and not exists(select 1 from public.church_cell_participants cp where cp.person_id=p.id and cp.status='active')));
 end if;

 if p_action='position.save' then
  if not manage then raise exception 'roles_denied' using errcode='42501'; end if;
  if length(btrim(coalesce(p_data->>'name','')))<2 or length(p_data->>'name')>60 or length(coalesce(p_data->>'nameFemale',''))>60 then raise exception 'invalid_roles' using errcode='22023'; end if;
  if coalesce(p_data->>'id','')='' then
   insert into private.church_positions(organization_id,name,name_female,pastoral,show_in_app,sort)
   values(p_org,btrim(p_data->>'name'),btrim(coalesce(p_data->>'nameFemale','')),coalesce((p_data->>'pastoral')::boolean,false),coalesce((p_data->>'showInApp')::boolean,true),
    coalesce((select max(sort)+10 from private.church_positions where organization_id=p_org),10)) returning * into pos;
  else
   update private.church_positions set name=btrim(p_data->>'name'),name_female=btrim(coalesce(p_data->>'nameFemale','')),pastoral=coalesce((p_data->>'pastoral')::boolean,pastoral),
    show_in_app=coalesce((p_data->>'showInApp')::boolean,show_in_app),active=coalesce((p_data->>'active')::boolean,active),version=version+1
   where id=(p_data->>'id')::uuid and organization_id=p_org and version=coalesce((p_data->>'version')::int,version) returning * into pos;
   if pos.id is null then raise exception 'roles_changed' using errcode='40001'; end if;
   if not pos.active then update private.person_positions set until=current_date where position_id=pos.id and until is null; end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.position_saved','church_position',pos.id::text,to_jsonb(pos));
  return jsonb_build_object('ok',true,'id',pos.id);
 end if;

 if p_action='position.order' then
  if not manage or jsonb_typeof(p_data->'ids')<>'array' or jsonb_array_length(p_data->'ids')>200 then raise exception 'invalid_roles' using errcode='22023'; end if;
  update private.church_positions c set sort=x.n*10 from (select (v)::uuid id,row_number() over() n from jsonb_array_elements_text(p_data->'ids') v) x where c.id=x.id and c.organization_id=p_org;
  return jsonb_build_object('ok',true);
 end if;

 if p_action='function.save' then
  if not manage then raise exception 'roles_denied' using errcode='42501'; end if;
  if length(btrim(coalesce(p_data->>'name','')))<2 or length(p_data->>'name')>60 or length(coalesce(p_data->>'nameFemale',''))>60
   or (nullif(p_data->>'template','') is not null and private.template_items(p_org,p_data->>'template') is null) then raise exception 'invalid_roles' using errcode='22023'; end if;
  if coalesce(p_data->>'id','')='' then
   if coalesce(p_data->>'kind','') not in('cell','network','ministry') then raise exception 'invalid_roles' using errcode='22023'; end if;
   insert into private.group_functions(organization_id,kind,name,name_female,leadership,template_code,sort)
   values(p_org,p_data->>'kind',btrim(p_data->>'name'),btrim(coalesce(p_data->>'nameFemale','')),coalesce((p_data->>'leadership')::boolean,false),
    case when coalesce((p_data->>'leadership')::boolean,false) then nullif(p_data->>'template','') end,
    coalesce((select max(sort)+10 from private.group_functions where organization_id=p_org and kind=p_data->>'kind'),10)) returning * into fn;
  else
   update private.group_functions set name=btrim(p_data->>'name'),name_female=btrim(coalesce(p_data->>'nameFemale','')),leadership=coalesce((p_data->>'leadership')::boolean,leadership),
    template_code=case when coalesce((p_data->>'leadership')::boolean,leadership) then nullif(p_data->>'template','') end,
    active=case when system_key in('leader','supervisor','member','participant') then true else coalesce((p_data->>'active')::boolean,active) end,version=version+1
   where id=(p_data->>'id')::uuid and organization_id=p_org and version=coalesce((p_data->>'version')::int,version) returning * into fn;
   if fn.id is null then raise exception 'roles_changed' using errcode='40001'; end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.function_saved','group_function',fn.id::text,to_jsonb(fn));
  return jsonb_build_object('ok',true,'id',fn.id);
 end if;

 if p_action='person' then
  pid:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=pid and organization_id=p_org) or not private.person_record_view(pid) then raise exception 'roles_denied' using errcode='42501'; end if;
  return private.person_roles(pid)||jsonb_build_object('canEdit',private.person_record_manage(pid));
 end if;

 if p_action in('person.position.add','person.position.end','assign','unassign') then
  if p_action in('person.position.end','unassign') then
   if p_action='unassign' then select person_id into pid from private.group_assignments where id=(p_data->>'id')::uuid and organization_id=p_org;
   else select person_id into pid from private.person_positions where id=(p_data->>'id')::uuid and organization_id=p_org; end if;
  else pid:=(p_data->>'person')::uuid; end if;
  if pid is null or not exists(select 1 from public.people where id=pid and organization_id=p_org) then raise exception 'invalid_roles' using errcode='22023'; end if;
  if not private.person_record_manage(pid) then raise exception 'roles_denied' using errcode='42501'; end if;
  if p_action='person.position.add' then
   select * into pos from private.church_positions where id=(p_data->>'position')::uuid and organization_id=p_org and active;
   if pos.id is null or (coalesce(p_data->>'since','')<>'' and (p_data->>'since') !~ '^\d{4}-\d{2}-\d{2}$') then raise exception 'invalid_roles' using errcode='22023'; end if;
   insert into private.person_positions(organization_id,person_id,position_id,unit_id,since,created_by)
   values(p_org,pid,pos.id,(select unit_id from public.people where id=pid),nullif(p_data->>'since','')::date,actor) on conflict do nothing;
  elsif p_action='person.position.end' then
   update private.person_positions set until=greatest(coalesce(since,current_date),current_date) where id=(p_data->>'id')::uuid and until is null;
  elsif p_action='assign' then
   v_kind:=p_data->>'kind'; gid:=(p_data->>'group')::uuid;
   select * into fn from private.group_functions where id=(p_data->>'function')::uuid and organization_id=p_org and kind=v_kind and active;
   v_unit:=private.group_unit(v_kind,gid,p_org);
   if fn.id is null or v_unit is null then raise exception 'invalid_roles' using errcode='22023'; end if;
   -- Participante de célula fica na lista de participantes da célula (onde Células registra presença).
   if v_kind='cell' and fn.system_key='participant' then
    insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by)
    values(extensions.gen_random_uuid(),p_org,v_unit,gid,pid,'active',actor)
    on conflict(cell_id,person_id) do update set status='active',version=public.church_cell_participants.version+1,updated_at=now();
   else
    insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source,created_by)
    values(p_org,v_unit,v_kind,gid,pid,fn.id,'panel',actor) on conflict do nothing;
    if v_kind='cell' then
     insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by)
     values(extensions.gen_random_uuid(),p_org,v_unit,gid,pid,'active',actor) on conflict(cell_id,person_id) do nothing;
    end if;
   end if;
  else
   update private.group_assignments set until=greatest(since,current_date) where id=(p_data->>'id')::uuid and until is null;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.'||p_action,'person',pid::text,p_data);
  perform private.person_group_refresh(pid);
  return private.person_roles(pid)||jsonb_build_object('canEdit',true);
 end if;

 if p_action='cell.leave' then
  pid:=(p_data->>'person')::uuid; gid:=(p_data->>'group')::uuid;
  if not private.person_record_manage(pid) then raise exception 'roles_denied' using errcode='42501'; end if;
  update public.church_cell_participants set status='inactive',version=version+1,updated_at=now() where cell_id=gid and person_id=pid and organization_id=p_org and status='active';
  update private.group_assignments set until=greatest(since,current_date) where kind='cell' and group_id=gid and person_id=pid and until is null;
  perform private.person_group_refresh(pid);
  return private.person_roles(pid)||jsonb_build_object('canEdit',true);
 end if;

 if p_action='groups.search' then
  q:=lower(btrim(coalesce(p_data->>'q','')));
  if length(q)>80 then raise exception 'invalid_roles' using errcode='22023'; end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(x order by x->>'kindOrder',x->>'name') from (
   select jsonb_build_object('kind','cell','kindOrder',2,'id',c.id,'name',c.name,'unit',u.name,'detail',coalesce(nullif(c.leader_name,''),'Sem líder')) x
    from public.church_cells c join public.organization_units u on u.id=c.unit_id where c.organization_id=p_org and c.status='active' and (q='' or lower(c.name) like '%'||q||'%')
   union all select jsonb_build_object('kind','network','kindOrder',1,'id',n.id,'name',n.name,'unit',u.name,'detail',coalesce(nullif(n.supervisor_name,''),'Sem supervisor'))
    from public.church_cell_networks n join public.organization_units u on u.id=n.unit_id where n.organization_id=p_org and n.status='active' and (q='' or lower(n.name) like '%'||q||'%')
   union all select jsonb_build_object('kind','ministry','kindOrder',3,'id',g.id,'name',g.name,'unit',u.name,'detail',case g.kind when 'ministry' then 'Ministério' else 'Departamento' end)
    from private.community_groups g join public.organization_units u on u.id=g.unit_id where g.organization_id=p_org and g.active and (q='' or lower(g.name) like '%'||q||'%')
   limit 60) y(x)),'[]'));
 end if;

 if p_action='ministries' then
  if not manage then raise exception 'roles_denied' using errcode='42501'; end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'kind',g.kind,'unit',u.name,'unitId',g.unit_id,
    'leaders',coalesce((select jsonb_agg(jsonb_build_object('person',p.id,'name',p.full_name,'function',private.gendered(f.name,f.name_female,p.gender)) order by f.sort) from private.group_assignments a join private.group_functions f on f.id=a.function_id join public.people p on p.id=a.person_id
      where a.kind='ministry' and a.group_id=g.id and a.until is null and f.leadership),'[]'),
    'members',(select count(*) from private.group_assignments a where a.kind='ministry' and a.group_id=g.id and a.until is null),
    'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name) order by t.name) from private.scale_teams t where t.ministry_id=g.id and t.active),'[]')) order by u.name,g.name)
   from private.community_groups g join public.organization_units u on u.id=g.unit_id where g.organization_id=p_org and g.active),'[]'),
   'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'unitId',t.unit_id,'ministry',t.ministry_id) order by t.name) from private.scale_teams t where t.organization_id=p_org and t.active),'[]'));
 end if;

 if p_action='ministry.teams' then
  if not manage or jsonb_typeof(p_data->'teams')<>'array' then raise exception 'invalid_roles' using errcode='22023'; end if;
  gid:=(p_data->>'ministry')::uuid;
  if not exists(select 1 from private.community_groups where id=gid and organization_id=p_org) then raise exception 'invalid_roles' using errcode='22023'; end if;
  update private.scale_teams set ministry_id=null where ministry_id=gid and organization_id=p_org and not id in(select (x)::uuid from jsonb_array_elements_text(p_data->'teams') x);
  update private.scale_teams set ministry_id=gid where organization_id=p_org and id in(select (x)::uuid from jsonb_array_elements_text(p_data->'teams') x)
   and unit_id=(select unit_id from private.community_groups where id=gid);
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.ministry_teams','community_group',gid::text,p_data);
  return jsonb_build_object('ok',true);
 end if;

 if p_action='members' then
  -- Pessoas de um grupo com a função (para gerenciar pelo grupo).
  v_kind:=p_data->>'kind'; gid:=(p_data->>'group')::uuid;
  if not manage then raise exception 'roles_denied' using errcode='42501'; end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'person',p.id,'name',p.full_name,'function',private.gendered(f.name,f.name_female,p.gender),'leadership',f.leadership,'since',a.since) order by f.sort,p.full_name)
   from private.group_assignments a join private.group_functions f on f.id=a.function_id join public.people p on p.id=a.person_id where a.kind=v_kind and a.group_id=gid and a.until is null and a.organization_id=p_org),'[]'));
 end if;

 if p_action in('access.list','access.approve','access.dismiss') then
  if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'roles_denied' using errcode='42501'; end if;
  if p_action='access.list' then
   return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'action',x.action,'person',p.id,'name',p.full_name,'template',private.template_label(p_org,x.template_code),
     'kind',x.kind,'group',private.group_label(x.kind,x.group_id),'createdAt',x.created_at,
     'hasUser',exists(select 1 from public.organization_memberships m where m.organization_id=p_org and m.user_id=p.auth_user_id and m.status='active'),
     'function',(select private.gendered(f.name,f.name_female,p.gender) from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.id=x.assignment_id)) order by x.created_at desc)
    from private.access_proposals x join public.people p on p.id=x.person_id where x.organization_id=p_org and x.status='pending'),'[]'));
  end if;
  select * into pr from private.access_proposals where id=(p_data->>'id')::uuid and organization_id=p_org and status='pending' for update;
  if pr.id is null then raise exception 'roles_changed' using errcode='40001'; end if;
  if p_action='access.dismiss' then
   update private.access_proposals set status='dismissed',decided_by=actor,decided_at=now() where id=pr.id;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.access_dismissed','access_proposal',pr.id::text,to_jsonb(pr));
   return jsonb_build_object('ok',true);
  end if;
  perform private.require_confirmed_self_service_email();
  select m.id into mid from public.organization_memberships m join public.people p on p.auth_user_id=m.user_id
   where p.id=pr.person_id and m.organization_id=p_org and m.status='active' and m.role not in('owner');
  if mid is null then raise exception 'roles_no_user' using errcode='22023'; end if;
  if pr.action='revoke' then
   select applied into pr.applied from private.access_proposals where assignment_id=pr.assignment_id and action='grant' and status='approved' order by decided_at desc limit 1;
  end if;
  res:=private.proposal_apply(pr,mid);
  update private.access_proposals set status='approved',decided_by=actor,decided_at=now(),applied=res||jsonb_build_object('membership',mid,'created',res->'changed') where id=pr.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.access_'||pr.action,'organization_membership',mid::text,jsonb_build_object('proposal',pr.id,'result',res));
  return jsonb_build_object('ok',true)||res;
 end if;

 if p_action in('review.list','review.link','review.clear') then
  if not manage then raise exception 'roles_denied' using errcode='42501'; end if;
  if p_action='review.list' then
   return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('person',p.id,'name',p.full_name,'text',p.group_name,'unit',u.name,
     'match',(select jsonb_build_object('kind',k.kind,'id',k.id,'name',k.name) from (
       select 'cell' kind,c.id,c.name,1 o from public.church_cells c where c.organization_id=p_org and c.unit_id=p.unit_id and c.status='active' and lower(btrim(c.name))=lower(btrim(p.group_name))
       union all select 'ministry',g.id,g.name,2 from private.community_groups g where g.organization_id=p_org and g.unit_id=p.unit_id and g.active and lower(btrim(g.name))=lower(btrim(p.group_name))
       union all select 'network',n.id,n.name,3 from public.church_cell_networks n where n.organization_id=p_org and n.unit_id=p.unit_id and n.status='active' and lower(btrim(n.name))=lower(btrim(p.group_name))) k order by k.o limit 1))
     order by lower(p.group_name),p.full_name)
    from public.people p left join public.organization_units u on u.id=p.unit_id
    where p.organization_id=p_org and p.status='active' and coalesce(btrim(p.group_name),'')<>''
     and not exists(select 1 from private.group_assignments a where a.person_id=p.id and a.until is null)
     and not exists(select 1 from public.church_cell_participants cp where cp.person_id=p.id and cp.status='active')
    limit 500),'[]'));
  end if;
  pid:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=pid and organization_id=p_org) then raise exception 'invalid_roles' using errcode='22023'; end if;
  if p_action='review.clear' then
   update public.people set group_name=null where id=pid;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'roles.review_clear','person',pid::text,'{}');
   return jsonb_build_object('ok',true);
  end if;
  v_kind:=p_data->>'kind';
  select id into fid from private.group_functions where organization_id=p_org and kind=v_kind and system_key=case v_kind when 'cell' then 'participant' when 'network' then 'disciple' else 'member' end;
  return public.church_roles(p_org,'assign',jsonb_build_object('person',pid,'kind',v_kind,'group',p_data->>'group','function',fid));
 end if;

 raise exception 'invalid_roles' using errcode='22023';
end $function$;
revoke all on function public.church_roles(uuid,text,jsonb) from public,anon;
grant execute on function public.church_roles(uuid,text,jsonb) to authenticated;

-- ── App da igreja: minhas funções, liderança, mensagens ──────────────────────────────────────────
create or replace function public.member_roles(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare actor uuid:=auth.uid(); me uuid; leader uuid; msg private.leadership_messages; lbl jsonb;
begin
 if actor is null then raise exception 'member_login_required' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>4000 then raise exception 'invalid_roles' using errcode='22023'; end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and o.status in('active','trial')) then raise exception 'roles_denied' using errcode='42501'; end if;
 select id into me from public.people where organization_id=p_org and auth_user_id=actor and status='active' order by (unit_id=p_unit) desc limit 1;
 perform private.roles_seed(p_org);
 select coalesce(labels,'{}') into lbl from public.ministry_language where organization_id=p_org;

 if p_action='mine' then
  if me is null then return jsonb_build_object('positions','[]'::jsonb,'groups','[]'::jsonb,'label',coalesce(lbl->>'pessoas.cargo','Cargo'),'leader',false); end if;
  return private.person_roles(me)||jsonb_build_object('label',coalesce(lbl->>'pessoas.cargo','Cargo'),'labelPlural',coalesce(lbl->>'pessoas.cargos','Cargos'),
   'leader',exists(select 1 from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.person_id=me and a.until is null and f.leadership)
    or exists(select 1 from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=me and pp.until is null and c.show_in_app),
   'showPhone',coalesce((select show_phone from private.leader_contact_prefs where person_id=me),false));
 end if;

 if p_action='leadership' then
  -- Pastores e líderes da igreja selecionada. Telefone só de quem autorizou.
  return jsonb_build_object('label',coalesce(lbl->>'pessoas.cargo','Cargo'),'items',coalesce((select jsonb_agg(x order by (x->>'rank')::int,x->>'name') from (
   select jsonb_build_object('person',p.id,'name',p.full_name,'self',p.id=me,
    'rank',coalesce((select min(c.sort) from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=p.id and pp.until is null and c.show_in_app and c.active),10000)
     +case when exists(select 1 from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=p.id and pp.until is null and c.pastoral) then 0 else 20000 end,
    'positions',coalesce((select jsonb_agg(private.gendered(c.name,c.name_female,p.gender) order by c.sort) from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=p.id and pp.until is null and c.show_in_app and c.active),'[]'),
    'functions',coalesce((select jsonb_agg(private.gendered(f.name,f.name_female,p.gender)||' · '||private.group_label(a.kind,a.group_id) order by f.sort) from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.person_id=p.id and a.until is null and f.leadership and f.active),'[]'),
    'phone',case when coalesce((select show_phone from private.leader_contact_prefs where person_id=p.id),false) then coalesce(p.phone,'') else '' end) x
   from public.people p where p.organization_id=p_org and p.unit_id=p_unit and p.status='active' and p.auth_user_id is not null and (
    exists(select 1 from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=p.id and pp.until is null and c.show_in_app and c.active)
    or exists(select 1 from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.person_id=p.id and a.until is null and f.leadership and f.active))
   limit 300) y),'[]'));
 end if;

 if me is null then raise exception 'member_profile_required' using errcode='42501'; end if;

 if p_action='privacy' then
  if jsonb_typeof(p_data->'showPhone')<>'boolean' then raise exception 'invalid_roles' using errcode='22023'; end if;
  insert into private.leader_contact_prefs(person_id,organization_id,show_phone) values(me,p_org,(p_data->>'showPhone')::boolean)
  on conflict(person_id) do update set show_phone=excluded.show_phone,updated_at=now();
  return jsonb_build_object('ok',true,'showPhone',(p_data->>'showPhone')::boolean);
 end if;

 if p_action='send' then
  leader:=(p_data->>'to')::uuid;
  if leader is null or leader=me or length(btrim(coalesce(p_data->>'body','')))<2 or length(p_data->>'body')>1000 then raise exception 'invalid_roles' using errcode='22023'; end if;
  -- Para um líder, ou resposta a quem escreveu para mim.
  if not (exists(select 1 from public.people p where p.id=leader and p.organization_id=p_org and p.status='active' and (
      exists(select 1 from private.person_positions pp join private.church_positions c on c.id=pp.position_id where pp.person_id=p.id and pp.until is null and c.show_in_app and c.active)
      or exists(select 1 from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.person_id=p.id and a.until is null and f.leadership)))
    or exists(select 1 from private.leadership_messages m where m.from_person=leader and m.to_person=me)) then raise exception 'roles_denied' using errcode='42501'; end if;
  if (select count(*) from private.leadership_messages where from_person=me and created_at>now()-interval '1 hour')>=10 then raise exception 'roles_rate_limited' using errcode='54000'; end if;
  insert into private.leadership_messages(organization_id,unit_id,from_person,to_person,reply_to,body)
  values(p_org,p_unit,me,leader,nullif(p_data->>'replyTo','')::uuid,btrim(p_data->>'body')) returning * into msg;
  return jsonb_build_object('ok',true,'id',msg.id);
 end if;

 if p_action='messages' then
  update private.leadership_messages set read_at=now() where to_person=me and read_at is null;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'mine',m.from_person=me,'with',case when m.from_person=me then m.to_person else m.from_person end,
    'name',(select full_name from public.people where id=case when m.from_person=me then m.to_person else m.from_person end),'body',m.body,'at',m.created_at) order by m.created_at desc)
   from (select * from private.leadership_messages where (from_person=me or to_person=me) and organization_id=p_org order by created_at desc limit 200) m),'[]'));
 end if;

 raise exception 'invalid_roles' using errcode='22023';
end $function$;
revoke all on function public.member_roles(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.member_roles(uuid,uuid,text,jsonb) to authenticated;

-- Mensagem nova aparece na caixa de notificações (e no push) de quem recebe.
do $$ begin
 if to_regprocedure('private.member_inbox_before_roles(uuid,uuid)') is null then
  alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_roles;
 end if;
end $$;
create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from private.member_inbox_before_roles(p_org,p_unit)
  union all
  select 'leader-msg:'||m.id::text,'Mensagem de '||split_part(f.full_name,' ',1),left(m.body,140),m.created_at,'leadership'::text,m.id
  from private.leadership_messages m join public.people me on me.id=m.to_person join public.people f on f.id=m.from_person
  where m.organization_id=p_org and me.auth_user_id=auth.uid() and m.created_at>now()-interval '60 days'
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;

-- ── Lista de Pessoas: filtros por cargo, ministério e liderança ──────────────────────────────────
do $$ declare d text; s text; begin
 for s in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='people_search' loop
  d:=pg_get_functiondef(s::regprocedure);
  if position('''converts''' in d)=0 or position('''position''' in d)>0 then continue; end if;
  if position('''converts'']<>''{}''::jsonb' in d)=0 then raise exception 'people_search: lista de filtros não encontrada'; end if;
  d:=replace(d,'''converts'']<>''{}''::jsonb','''converts'',''position'',''ministry'',''leaders'']<>''{}''::jsonb');
  if position(' if not private.people_list_allowed(p_org,p_unit)' in d)=0 then raise exception 'people_search: checagem de acesso não encontrada'; end if;
  d:=replace(d,' if not private.people_list_allowed(p_org,p_unit)',
   ' if (f ? ''position'' and coalesce(f->>''position'','''') !~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'') or (f ? ''ministry'' and coalesce(f->>''ministry'','''') !~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'') or (f ? ''leaders'' and jsonb_typeof(f->''leaders'')<>''boolean'') then raise exception ''invalid_filters'' using errcode=''22023''; end if;'||chr(10)||' if not private.people_list_allowed(p_org,p_unit)');
  if position('and (not coalesce((f->>''converts'')::boolean,false) or p.converted_at is not null)' in d)=0 then raise exception 'people_search: filtro de convertidos não encontrado'; end if;
  d:=replace(d,'and (not coalesce((f->>''converts'')::boolean,false) or p.converted_at is not null)',
   'and (not coalesce((f->>''converts'')::boolean,false) or p.converted_at is not null)
   and (not f ? ''position'' or exists(select 1 from private.person_positions pp where pp.person_id=p.id and pp.until is null and pp.position_id=(f->>''position'')::uuid))
   and (not f ? ''ministry'' or exists(select 1 from private.group_assignments ga where ga.person_id=p.id and ga.until is null and ga.kind=''ministry'' and ga.group_id=(f->>''ministry'')::uuid))
   and (not coalesce((f->>''leaders'')::boolean,false) or exists(select 1 from private.group_assignments ga join private.group_functions gf on gf.id=ga.function_id where ga.person_id=p.id and ga.until is null and gf.leadership)
        or exists(select 1 from private.person_positions pp where pp.person_id=p.id and pp.until is null))');
  execute d;
 end loop;
end $$;

-- ── Dados que já existem: pastores, líderes de célula, supervisores, integrantes aprovados ──────
do $$ declare o record; begin
 for o in select id from public.organizations loop perform private.roles_seed(o.id); end loop;
end $$;
insert into private.person_positions(organization_id,person_id,position_id,unit_id,since)
select p.organization_id,p.id,c.id,p.unit_id,null from public.people p join private.church_positions c on c.organization_id=p.organization_id and c.system_key='pastor'
where p.is_pastor on conflict do nothing;
insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source)
select c.organization_id,c.unit_id,'cell',c.id,c.leader_person_id,f.id,'sync' from public.church_cells c join private.group_functions f on f.organization_id=c.organization_id and f.kind='cell' and f.system_key='leader'
where c.leader_person_id is not null and c.status='active' on conflict do nothing;
insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source)
select n.organization_id,n.unit_id,'network',n.id,n.supervisor_person_id,f.id,'sync' from public.church_cell_networks n join private.group_functions f on f.organization_id=n.organization_id and f.kind='network' and f.system_key='supervisor'
where n.supervisor_person_id is not null and n.status='active' on conflict do nothing;
insert into private.group_assignments(organization_id,unit_id,kind,group_id,person_id,function_id,source)
select cp.organization_id,cp.unit_id,'ministry',cp.group_id,cp.person_id,f.id,'app' from private.community_participation cp join private.group_functions f on f.organization_id=cp.organization_id and f.kind='ministry' and f.system_key='member'
where cp.status='approved' and not exists(select 1 from private.group_assignments a where a.kind='ministry' and a.group_id=cp.group_id and a.person_id=cp.person_id and a.until is null)
on conflict do nothing;
-- Quem já era líder antes desta versão já tem o acesso combinado: nada de pedidos antigos.
delete from private.access_proposals where status='pending' and assignment_id in(select id from private.group_assignments where source in('sync','app'));

-- Nome do conceito personalizável (Cargo, Título, Ofício…) pela linguagem ministerial.
do $$ declare d text; s text; begin
 for s in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='ministry_language_save' loop
  d:=pg_get_functiondef(s::regprocedure);
  if position('''pessoas.cargo''' in d)>0 or position('array[''inicio'',' in d)=0 then continue; end if;
  execute replace(d,'array[''inicio'',','array[''pessoas.cargo'',''pessoas.cargos'',''inicio'',');
 end loop;
end $$;
