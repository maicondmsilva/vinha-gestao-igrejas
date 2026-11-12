-- Vínculos familiares entre pessoas do cadastro.
-- Uma linha (person_id, related_person_id, relation) quer dizer: "related é <relation> de person".
-- O par inverso é mantido junto, para a consulta de qualquer lado ser simples.

alter table public.people add column if not exists marriage_date date;

create or replace function private.relation_inverse(p_relation text) returns text
language sql immutable set search_path to '' as $$
 select case p_relation
  when 'pai_mae' then 'filho' when 'filho' then 'pai_mae'
  when 'avo' then 'neto' when 'neto' then 'avo'
  when 'tio' then 'sobrinho' when 'sobrinho' then 'tio'
  when 'padrasto_madrasta' then 'enteado' when 'enteado' then 'padrasto_madrasta'
  when 'responsavel_legal' then 'tutelado' when 'tutelado' then 'responsavel_legal'
  when 'conjuge' then 'conjuge' when 'irmao' then 'irmao' when 'outro' then 'outro'
  else null end
$$;

create table if not exists private.person_relationships(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 person_id uuid not null,
 related_person_id uuid not null,
 relation text not null check (relation in ('conjuge','pai_mae','filho','irmao','avo','neto','tio','sobrinho','padrasto_madrasta','enteado','responsavel_legal','tutelado','outro')),
 same_household boolean not null default false,
 marriage_date date,
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 version int not null default 1 check (version>0),
 unique(person_id,related_person_id),
 check (person_id<>related_person_id),
 foreign key (person_id,organization_id) references public.people(id,organization_id) on delete cascade,
 foreign key (related_person_id,organization_id) references public.people(id,organization_id) on delete cascade
);
create index if not exists person_relationships_related on private.person_relationships(related_person_id);
alter table private.person_relationships enable row level security;
revoke all on private.person_relationships from public,anon,authenticated,service_role;

-- Mesma regra da política de inclusão em people (papel + igreja, ou permissão concedida).
create or replace function private.person_insert_allowed(p_org uuid, p_unit uuid, p_journey text) returns boolean
language sql stable security definer set search_path to '' as $$
 select (private.has_organization_role(p_org,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
   and exists(select 1 from public.organizations o where o.id=p_org and o.status in ('active','trial'))
   and (private.has_organization_role(p_org,array['owner','pastor','admin']::public.membership_role[])
    or private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[])))
  or private.person_create_permission(p_org,p_unit,p_journey)
$$;

create or replace function private.person_family(p_org uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
 v_person public.people; v_related public.people; r private.person_relationships;
 v_relation text; v_inverse text; v_household boolean; v_marriage date; v_journey text; v_name text;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 p_data:=coalesce(p_data,'{}'::jsonb);
 perform 1 from public.organizations where id=p_org and status in ('active','trial');
 if not found then raise exception 'organization_access_denied' using errcode='42501'; end if;

 if p_action in ('list','suggest_guardians') then
  select * into v_person from public.people where id=nullif(coalesce(p_data->>'person',p_data->>'child'),'')::uuid and organization_id=p_org and status<>'rejected';
  if v_person.id is null or not private.person_record_view(v_person.id) then raise exception 'family_access_denied' using errcode='42501'; end if;
  if p_action='suggest_guardians' then
   return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('person',p.id,'name',p.full_name,'relation',x.relation) order by p.full_name)
    from private.person_relationships x join public.people p on p.id=x.related_person_id
    where x.person_id=v_person.id and x.relation in ('pai_mae','avo','responsavel_legal') and p.status not in ('rejected','deceased')
     and private.person_record_view(p.id)),'[]'::jsonb));
  end if;
  return jsonb_build_object('canEdit',private.person_record_manage(v_person.id),
   'items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'person',p.id,'name',p.full_name,'relation',x.relation,
     'age',case when p.birth_date is null then null else extract(year from age(p.birth_date))::int end,
     'journey',p.journey_status,'unit',u.name,'same_household',x.same_household,'marriage_date',x.marriage_date,'version',x.version)
    order by array_position(array['conjuge','pai_mae','padrasto_madrasta','responsavel_legal','filho','enteado','tutelado','irmao','avo','neto','tio','sobrinho','outro'],x.relation),p.full_name)
    from private.person_relationships x join public.people p on p.id=x.related_person_id left join public.organization_units u on u.id=p.unit_id
    where x.person_id=v_person.id and p.status<>'rejected' and private.person_record_view(p.id)),'[]'::jsonb));
 end if;

 if p_action='remove' then
  select * into r from private.person_relationships where id=nullif(p_data->>'id','')::uuid and organization_id=p_org for update;
  if r.id is null then raise exception 'family_link_not_found' using errcode='P0002'; end if;
  if not (private.person_record_manage(r.person_id) and private.person_record_manage(r.related_person_id)) then raise exception 'family_access_denied' using errcode='42501'; end if;
  if (p_data->>'version')::int is distinct from r.version then raise exception 'family_link_changed' using errcode='40001'; end if;
  delete from private.person_relationships where (person_id,related_person_id) in ((r.person_id,r.related_person_id),(r.related_person_id,r.person_id));
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'people.family.removed','person',r.person_id::text,jsonb_build_object('related',r.related_person_id,'relation',r.relation));
  return jsonb_build_object('ok',true);
 end if;

 if p_action not in ('set','quick_create') then raise exception 'invalid_action' using errcode='22023'; end if;
 v_relation:=p_data->>'relation';
 v_inverse:=private.relation_inverse(v_relation);
 if v_inverse is null then raise exception 'invalid_relation' using errcode='22023'; end if;
 v_household:=coalesce((p_data->>'same_household')::boolean,false);
 v_marriage:=case when v_relation='conjuge' then nullif(p_data->>'marriage_date','')::date else null end;
 select * into v_person from public.people where id=nullif(p_data->>'person','')::uuid and organization_id=p_org and status<>'rejected' for update;
 if v_person.id is null or not private.person_record_manage(v_person.id) then raise exception 'family_access_denied' using errcode='42501'; end if;

 if p_action='quick_create' then
  v_name:=btrim(coalesce(p_data->>'name',''));
  v_journey:=coalesce(nullif(p_data->>'journey',''),'Membro');
  if char_length(v_name) not between 2 and 160 or v_journey not in ('Membro','Em integração','Visitante') then raise exception 'invalid_person' using errcode='22023'; end if;
  if not private.person_insert_allowed(p_org,v_person.unit_id,v_journey) then raise exception 'family_access_denied' using errcode='42501'; end if;
  insert into public.people(organization_id,unit_id,full_name,birth_date,journey_status,status)
   values(p_org,v_person.unit_id,v_name,nullif(p_data->>'birth_date','')::date,v_journey,'active') returning * into v_related;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'people.family.quick_created','person',v_related.id::text,jsonb_build_object('from',v_person.id));
 else
  select * into v_related from public.people where id=nullif(p_data->>'related','')::uuid and organization_id=p_org and status<>'rejected' for update;
  if v_related.id is null then raise exception 'family_access_denied' using errcode='42501'; end if;
  if v_related.id=v_person.id then raise exception 'family_self_link' using errcode='23514'; end if;
  if not private.person_record_manage(v_related.id) then raise exception 'family_access_denied' using errcode='42501'; end if;
 end if;

 select * into r from private.person_relationships where person_id=v_person.id and related_person_id=v_related.id for update;
 if nullif(p_data->>'id','') is not null then
  if r.id is null or r.id<>(p_data->>'id')::uuid then raise exception 'family_link_not_found' using errcode='P0002'; end if;
  if (p_data->>'version')::int is distinct from r.version then raise exception 'family_link_changed' using errcode='40001'; end if;
 elsif r.id is not null or exists(select 1 from private.person_relationships where person_id=v_related.id and related_person_id=v_person.id) then
  raise exception 'family_link_exists' using errcode='23505';
 end if;

 if r.id is null then
  insert into private.person_relationships(organization_id,person_id,related_person_id,relation,same_household,marriage_date,created_by)
   values(p_org,v_person.id,v_related.id,v_relation,v_household,v_marriage,auth.uid()) returning * into r;
  insert into private.person_relationships(organization_id,person_id,related_person_id,relation,same_household,marriage_date,created_by)
   values(p_org,v_related.id,v_person.id,v_inverse,v_household,v_marriage,auth.uid());
 else
  update private.person_relationships set relation=v_relation,same_household=v_household,marriage_date=v_marriage,updated_at=now(),version=version+1
   where id=r.id returning * into r;
  update private.person_relationships set relation=v_inverse,same_household=v_household,marriage_date=v_marriage,updated_at=now(),version=version+1
   where person_id=v_related.id and related_person_id=v_person.id;
 end if;

 if v_relation='conjuge' and v_marriage is not null then
  update public.people set marriage_date=v_marriage where id in (v_person.id,v_related.id);
 end if;
 if v_household and coalesce((p_data->>'copy_address')::boolean,false) then
  insert into public.person_addresses(organization_id,person_id,postal_code,street,number,complement,district,city,state,country_code)
   select p_org,v_related.id,a.postal_code,a.street,a.number,a.complement,a.district,a.city,a.state,a.country_code
   from public.person_addresses a where a.person_id=v_person.id
  on conflict (organization_id,person_id) do update set postal_code=excluded.postal_code,street=excluded.street,number=excluded.number,
   complement=excluded.complement,district=excluded.district,city=excluded.city,state=excluded.state,country_code=excluded.country_code;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'people.family.saved','person',v_person.id::text,jsonb_build_object('related',v_related.id,'relation',v_relation,'sameHousehold',v_household));
 return jsonb_build_object('ok',true,'id',r.id,'version',r.version,'related',v_related.id);
end $$;

create or replace function public.person_family(p_org uuid, p_action text, p_data jsonb) returns jsonb
language sql security invoker set search_path to '' as $$ select private.person_family(p_org,p_action,p_data) $$;

revoke all on function private.relation_inverse(text) from public,anon;
revoke all on function private.person_insert_allowed(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function private.person_family(uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.person_family(uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.relation_inverse(text) to authenticated;
grant execute on function private.person_family(uuid,text,jsonb) to authenticated;
grant execute on function public.person_family(uuid,text,jsonb) to authenticated;
