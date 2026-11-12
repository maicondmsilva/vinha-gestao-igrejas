-- Usuários: ficha que edita o mesmo cadastro do membro, sem convite.
-- Excluir = tirar o acesso (vínculo revogado e permissões avulsas removidas); login e membro continuam.
-- O login (Supabase Auth) é criado pela rota do servidor só depois que esta função autoriza.

alter table public.people add column if not exists marriage_date date;
alter table public.people add column if not exists is_pastor boolean not null default false;
alter table public.organization_memberships add column if not exists password_change_required boolean not null default false;

-- Convites deixam de existir: os pendentes são cancelados e não se criam novos.
update public.staff_invitations set status='revoked' where status='pending';

create or replace function public.create_staff_invitation(p_organization uuid, p_unit uuid, p_email text, p_name text, p_role public.membership_role)
returns jsonb language plpgsql security definer set search_path to '' as $$
begin
 raise exception 'staff_invitations_disabled' using errcode='0A000';
end $$;

-- Ordem dos papéis: ninguém mexe em quem está no mesmo nível ou acima (o dono mexe em todos).
create or replace function private.staff_role_rank(p_role public.membership_role) returns int
language sql immutable set search_path to '' as $$
 select case p_role when 'owner' then 6 when 'admin' then 5 when 'pastor' then 4
  when 'secretary' then 3 when 'finance' then 3 when 'leader' then 3 when 'member' then 2 else 1 end
$$;

-- Versão da ficha: resumo do conteúdo do vínculo, do membro e do endereço. Qualquer alteração muda a versão.
create or replace function private.staff_user_version(p_membership uuid, p_person uuid) returns text
language sql stable security definer set search_path to '' as $$
 select md5(coalesce((select row(m.*)::text from public.organization_memberships m where m.id=p_membership),'-')
  ||'|'||coalesce((select row(p.*)::text from public.people p where p.id=p_person),'-')
  ||'|'||coalesce((select row(a.*)::text from public.person_addresses a where a.person_id=p_person),'-'))
$$;

create or replace function private.staff_user_mask_cpf(p_cpf text) returns text
language sql immutable set search_path to '' as $$
 select case when length(d)=11 then '***.'||substr(d,4,3)||'.'||substr(d,7,3)||'-**' else null end
 from (select regexp_replace(coalesce(p_cpf,''),'\D','','g') d) x
$$;

create or replace function private.staff_user(p_org uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
 actor public.organization_memberships;
 actor_rank int;
 m public.organization_memberships;
 person public.people;
 v_role public.membership_role;
 v_unit uuid;
 v_email text;
 v_login uuid;
 v_address jsonb;
 v_extra jsonb;
 v_account jsonb;
 q text;
 digits text;
 result jsonb;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if p_action is null or p_action not in ('get','search','save','remove','link_login') then raise exception 'invalid_action' using errcode='22023'; end if;
 p_data:=coalesce(p_data,'{}'::jsonb);
 perform 1 from public.organizations where id=p_org and status in ('active','trial');
 if not found then raise exception 'organization_access_denied' using errcode='42501'; end if;
 select * into actor from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active';
 if actor.id is null or not (actor.role in ('owner','admin','pastor')
  or private.permission_any(p_org, case when p_action in ('get','search') then array['settings.users:view','settings.users:edit'] else array['settings.users:edit'] end)) then
  raise exception 'staff_access_denied' using errcode='42501';
 end if;
 actor_rank:=private.staff_role_rank(actor.role);

 if p_action='search' then
  q:=btrim(coalesce(p_data->>'q',''));
  digits:=regexp_replace(q,'\D','','g');
  if char_length(q)<1 then return jsonb_build_object('items','[]'::jsonb); end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(row_to_json(x)::jsonb order by x.name) from (
   select p.id person, p.full_name name, p.email, private.staff_user_mask_cpf(p.cpf) cpf_masked, u.name unit,
    p.auth_user_id is not null "hasLogin", om.id membership, om.status membership_status,
    private.staff_user_version(om.id,p.id) version
   from public.people p
   left join public.organization_units u on u.id=p.unit_id
   left join public.organization_memberships om on om.organization_id=p.organization_id and om.user_id=p.auth_user_id
   where p.organization_id=p_org and p.status<>'rejected'
    and (p.full_name ilike '%'||q||'%' or p.email ilike '%'||q||'%'
     or (char_length(digits)>=3 and regexp_replace(coalesce(p.cpf,''),'\D','','g') like '%'||digits||'%'))
   order by p.full_name limit 20) x),'[]'::jsonb));
 end if;

 if p_action='get' then
  select * into m from public.organization_memberships where id=(p_data->>'membership')::uuid and organization_id=p_org;
  if m.id is null then raise exception 'membership_not_found' using errcode='P0002'; end if;
  select * into person from public.people where organization_id=p_org and auth_user_id=m.user_id and status<>'rejected' order by created_at limit 1;
  return jsonb_build_object(
   'membership',jsonb_build_object('id',m.id,'role',m.role,'status',m.status,'unit_id',m.default_unit_id,
     'password_change_required',m.password_change_required,'version',private.staff_user_version(m.id,person.id),
     'editable',(actor.role='owner' or (m.user_id<>auth.uid() and private.staff_role_rank(m.role)<actor_rank))),
   'person',case when person.id is null then null else jsonb_build_object('id',person.id,'full_name',person.full_name,'phone',person.phone,
     'email',person.email,'gender',person.gender,'cpf',person.cpf,'birth_date',person.birth_date,'marriage_date',person.marriage_date,
     'baptism_date',person.baptism_date,'is_pastor',person.is_pastor,'unit_id',person.unit_id,'journey_status',person.journey_status,
     'address',(select jsonb_build_object('postal_code',a.postal_code,'street',a.street,'number',a.number,'complement',a.complement,
       'district',a.district,'city',a.city,'state',a.state) from public.person_addresses a where a.person_id=person.id)) end,
   'groups',jsonb_build_object(
     'cells',coalesce((select jsonb_agg(distinct c.name) from public.church_cell_participants cp join public.church_cells c on c.id=cp.cell_id
       where cp.person_id=person.id and cp.status='active'),'[]'::jsonb),
     'teams',coalesce((select jsonb_agg(distinct t.name) from private.scale_members sm join private.scale_teams t on t.id=sm.team_id
       where sm.person_id=person.id and sm.active),'[]'::jsonb),
     'kids','[]'::jsonb),
   'hasLogin',true,
   'email',(select email from auth.users where id=m.user_id));
 end if;

 if p_action='remove' then
  select * into m from public.organization_memberships where id=(p_data->>'membership')::uuid and organization_id=p_org for update;
  if m.id is null then raise exception 'membership_not_found' using errcode='P0002'; end if;
  if m.user_id=auth.uid() then raise exception 'cannot_remove_self' using errcode='42501'; end if;
  if m.role='owner' then raise exception 'cannot_remove_owner' using errcode='42501'; end if;
  if actor.role<>'owner' and private.staff_role_rank(m.role)>=actor_rank then raise exception 'membership_role_grant_denied' using errcode='42501'; end if;
  update public.organization_memberships set status='revoked', password_change_required=false where id=m.id;
  delete from private.permission_grants where membership_id=m.id;
  delete from private.scale_grants where membership_id=m.id;
  delete from public.membership_unit_access where membership_id=m.id;
  delete from private.staff_grants where organization_id=p_org and user_id=m.user_id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'staff.user.removed','organization_membership',m.id::text,jsonb_build_object('role',m.role));
  return jsonb_build_object('ok',true);
 end if;

 -- save e link_login: papel e igreja
 begin v_role:=(p_data->>'role')::public.membership_role; exception when others then raise exception 'invalid_role' using errcode='22023'; end;
 if v_role is null then raise exception 'invalid_role' using errcode='22023'; end if;
 v_unit:=nullif(p_data->>'unit','')::uuid;
 if v_unit is not null and not exists(select 1 from public.organization_units where id=v_unit and organization_id=p_org) then
  raise exception 'invalid_unit' using errcode='22023';
 end if;

 if p_action='link_login' then
  if v_role='owner' or (actor.role<>'owner' and private.staff_role_rank(v_role)>=actor_rank) then raise exception 'membership_role_grant_denied' using errcode='42501'; end if;
  select * into person from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and status<>'rejected' for update;
  if person.id is null then raise exception 'person_not_found' using errcode='P0002'; end if;
  v_login:=(p_data->>'user')::uuid;
  if person.auth_user_id is not null and person.auth_user_id<>v_login then raise exception 'person_has_login' using errcode='42501'; end if;
  if not exists(select 1 from auth.users where id=v_login and lower(email)=lower(person.email)) then raise exception 'login_email_mismatch' using errcode='42501'; end if;
  if exists(select 1 from public.people where organization_id=p_org and auth_user_id=v_login and id<>person.id) then raise exception 'login_in_use' using errcode='42501'; end if;
  update public.people set auth_user_id=v_login where id=person.id;
  insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id,password_change_required)
   values(p_org,v_login,v_role,'active',coalesce(v_unit,person.unit_id),coalesce((p_data->>'passwordSet')::boolean,false))
   on conflict (organization_id,user_id) do update set role=excluded.role,status='active',default_unit_id=excluded.default_unit_id,
    password_change_required=excluded.password_change_required
   returning * into m;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'staff.user.saved','organization_membership',m.id::text,jsonb_build_object('role',v_role,'login','created'));
  return jsonb_build_object('ok',true,'membership',m.id);
 end if;

 -- save
 v_account:=coalesce(p_data->'account','{}'::jsonb);
 v_address:=p_data->'address';
 v_extra:=coalesce(p_data->'extra','{}'::jsonb);
 v_email:=lower(btrim(coalesce(v_account->>'email','')));
 if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid_email' using errcode='22023'; end if;
 if char_length(btrim(coalesce(v_account->>'name','')))<2 then raise exception 'invalid_name' using errcode='22023'; end if;
 if v_role='owner' then raise exception 'membership_role_grant_denied' using errcode='42501'; end if;

 if p_data ? 'membership' and nullif(p_data->>'membership','') is not null then
  select * into m from public.organization_memberships where id=(p_data->>'membership')::uuid and organization_id=p_org for update;
  if m.id is null then raise exception 'membership_not_found' using errcode='P0002'; end if;
  select * into person from public.people where organization_id=p_org and auth_user_id=m.user_id and status<>'rejected' order by created_at limit 1 for update;
 elsif nullif(p_data->>'person','') is not null then
  select * into person from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and status<>'rejected' for update;
  if person.id is null then raise exception 'person_not_found' using errcode='P0002'; end if;
  if person.auth_user_id is not null then
   select * into m from public.organization_memberships where organization_id=p_org and user_id=person.auth_user_id for update;
  end if;
 end if;

 if (m.id is not null or person.id is not null) and p_data->>'version' is distinct from private.staff_user_version(m.id,person.id) then
  raise exception 'stale_version' using errcode='40001';
 end if;

 -- Papel: o dono mexe em todos; os demais só abaixo do próprio nível e nunca no próprio papel.
 if m.id is not null then
  if m.user_id=auth.uid() then
   if v_role<>m.role then raise exception 'membership_role_grant_denied' using errcode='42501'; end if;
  elsif m.role='owner' then
   raise exception 'membership_role_grant_denied' using errcode='42501';
  elsif actor.role<>'owner' and (private.staff_role_rank(m.role)>=actor_rank or private.staff_role_rank(v_role)>=actor_rank) then
   raise exception 'membership_role_grant_denied' using errcode='42501';
  end if;
 elsif actor.role<>'owner' and private.staff_role_rank(v_role)>=actor_rank then
  raise exception 'membership_role_grant_denied' using errcode='42501';
 end if;

 v_login:=coalesce(m.user_id,person.auth_user_id);
 if exists(select 1 from auth.users where lower(email)=v_email and id is distinct from v_login)
  or exists(select 1 from public.people where organization_id=p_org and lower(email)=v_email and id is distinct from person.id) then
  raise exception 'email_in_use' using errcode='23505';
 end if;

 if person.id is null then
  insert into public.people(organization_id,unit_id,full_name,email,phone,status,journey_status)
   values(p_org,coalesce(v_unit,actor.default_unit_id),btrim(v_account->>'name'),v_email,nullif(btrim(coalesce(v_account->>'phone','')),''),'active','Membro')
   returning * into person;
 end if;
 update public.people set
  full_name=btrim(v_account->>'name'),
  email=v_email,
  phone=case when v_account ? 'phone' then nullif(btrim(coalesce(v_account->>'phone','')),'') else phone end,
  gender=case when v_extra ? 'gender' then nullif(v_extra->>'gender','') else gender end,
  cpf=case when v_extra ? 'cpf' then nullif(btrim(coalesce(v_extra->>'cpf','')),'') else cpf end,
  birth_date=case when v_extra ? 'birth_date' then nullif(v_extra->>'birth_date','')::date else birth_date end,
  marriage_date=case when v_extra ? 'marriage_date' then nullif(v_extra->>'marriage_date','')::date else marriage_date end,
  baptism_date=case when v_extra ? 'baptism_date' then nullif(v_extra->>'baptism_date','')::date else baptism_date end,
  is_pastor=case when v_extra ? 'is_pastor' then coalesce((v_extra->>'is_pastor')::boolean,false) else is_pastor end
 where id=person.id returning * into person;
 if jsonb_typeof(v_address)='object' then
  insert into public.person_addresses(organization_id,person_id,postal_code,street,number,complement,district,city,state)
   values(p_org,person.id,nullif(v_address->>'postal_code',''),nullif(v_address->>'street',''),nullif(v_address->>'number',''),
    nullif(v_address->>'complement',''),nullif(v_address->>'district',''),nullif(v_address->>'city',''),nullif(v_address->>'state',''))
   on conflict (organization_id,person_id) do update set postal_code=excluded.postal_code,street=excluded.street,number=excluded.number,
    complement=excluded.complement,district=excluded.district,city=excluded.city,state=excluded.state;
 end if;

 if v_login is not null then
  insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
   values(p_org,v_login,v_role,'active',coalesce(v_unit,person.unit_id))
   on conflict (organization_id,user_id) do update set role=excluded.role,status='active',
    default_unit_id=coalesce(v_unit,public.organization_memberships.default_unit_id)
   returning * into m;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'staff.user.saved',case when m.id is null then 'person' else 'organization_membership' end,
   coalesce(m.id,person.id)::text,jsonb_build_object('role',v_role,'person',person.id));
 return jsonb_build_object('ok',true,'membership',m.id,'person',person.id,'needsLogin',v_login is null,'loginUser',v_login,
  'version',private.staff_user_version(m.id,person.id));
end $$;

create or replace function public.staff_user(p_org uuid, p_action text, p_data jsonb) returns jsonb
language sql security invoker set search_path to '' as $$ select private.staff_user(p_org,p_action,p_data) $$;

create or replace function public.password_change_done() returns void
language sql security definer set search_path to '' as $$
 update public.organization_memberships set password_change_required=false where user_id=auth.uid() and password_change_required
$$;

revoke all on function private.staff_user(uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.staff_user(uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.password_change_done() from public,anon,service_role;
revoke all on function private.staff_user_version(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function private.staff_role_rank(public.membership_role) from public,anon,authenticated,service_role;
revoke all on function private.staff_user_mask_cpf(text) from public,anon,authenticated,service_role;
grant execute on function private.staff_user(uuid,text,jsonb) to authenticated;
grant execute on function public.staff_user(uuid,text,jsonb) to authenticated;
grant execute on function public.password_change_done() to authenticated;

-- A lista de usuários deixa de mostrar quem perdeu o acesso.
do $mig$
declare def text; n int;
begin
 def:=pg_get_functiondef('public.staff_directory(uuid)'::regprocedure);
 if position('m.status<>''revoked''' in def)>0 then return; end if;
 n:=(length(def)-length(replace(def,'where m.organization_id=p_organization),''[]''','')))/length('where m.organization_id=p_organization),''[]''');
 if n<>1 then raise exception 'staff_directory: trecho esperado % vez(es)',n; end if;
 def:=replace(def,'where m.organization_id=p_organization),''[]''','where m.organization_id=p_organization and m.status<>''revoked''),''[]''');
 execute def;
end $mig$;
