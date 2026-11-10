-- Production migration receipt: 20261024213655.
set local lock_timeout='5s';
create table private.member_profile_requests(
 id uuid primary key default extensions.gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 unit_id uuid not null, user_id uuid not null references auth.users(id), person_id uuid references public.people(id),
 kind text not null check(kind in ('registration','update')), payload jsonb not null, baseline jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','partial','rejected')),
 accepted_fields text[] not null default '{}', reason text, reviewed_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp(), reviewed_at timestamptz,
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create unique index member_request_pending on private.member_profile_requests(organization_id,user_id) where status='pending';
create index member_request_unit on private.member_profile_requests(unit_id,organization_id);
create index member_request_user on private.member_profile_requests(user_id);
create index member_request_person on private.member_profile_requests(person_id);
create index member_request_reviewer on private.member_profile_requests(reviewed_by);
alter table private.member_profile_requests enable row level security;
revoke all on private.member_profile_requests from public,anon,authenticated,service_role;

create function private.member_profile_snapshot(p_person uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('full_name',p.full_name,'phone',coalesce(p.phone,''),'birth_date',coalesce(p.birth_date::text,''),'gender',coalesce(p.gender,''),'marital_status',coalesce(p.marital_status,''),'cpf',coalesce(p.cpf,''),
 'postal_code',coalesce(a.postal_code,''),'street',coalesce(a.street,''),'number',coalesce(a.number,''),'complement',coalesce(a.complement,''),'district',coalesce(a.district,''),'city',coalesce(a.city,''),'state',coalesce(a.state,''))
 from public.people p left join public.person_addresses a on a.person_id=p.id and a.organization_id=p.organization_id where p.id=p_person;
$$;
revoke all on function private.member_profile_snapshot(uuid) from public,anon,authenticated,service_role;

create schema if not exists member_app_api;
revoke all on schema member_app_api from public;
grant usage on schema member_app_api to anon,authenticated;
create function member_app_api.config(p_slug text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.organizations;
begin
 select * into o from public.organizations where slug=p_slug and status in ('active','trial');
 if not found then raise exception 'app_unavailable' using errcode='42501'; end if;
 return jsonb_build_object('id',o.id,'name',o.name,'appName',coalesce(o.app_name,o.name),'primary',o.primary_color,'accent',o.accent_color,
 'logo',(select logo_png from private.church_branding where scope_id=o.id),
 'units',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'city',address->>'city') order by name) from public.organization_units where organization_id=o.id and status='active'),'[]'));
end $$;
revoke all on function member_app_api.config(text) from public;
grant execute on function member_app_api.config(text) to anon,authenticated;
create function public.member_app_config(p_slug text) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.config(p_slug)$$;
revoke all on function public.member_app_config(text) from public;
grant execute on function public.member_app_config(text) to anon,authenticated;

create function private.member_self_service(p_org uuid,p_action text,p_unit uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare account_email text; m public.organization_memberships; person public.people; request private.member_profile_requests; kind text; k text;
 allowed text[]:=array['full_name','phone','birth_date','gender','marital_status','cpf','postal_code','street','number','complement','district','city','state'];
begin
 account_email:=private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in ('active','trial') for update;
 if not found then raise exception 'member_app_denied' using errcode='42501'; end if;
 select * into m from public.organization_memberships where organization_id=p_org and user_id=auth.uid() for update;
 if found and m.status in ('suspended','revoked') then raise exception 'member_app_denied' using errcode='42501'; end if;
 if (select count(*) from public.people where organization_id=p_org and auth_user_id=auth.uid() and status<>'rejected')>1 then raise exception 'member_identity_ambiguous' using errcode='40001'; end if;
 select * into person from public.people where organization_id=p_org and auth_user_id=auth.uid() and status<>'rejected' for update;
 if p_action='profile' then
  return jsonb_build_object('personId',person.id,'unitId',coalesce(person.unit_id,m.default_unit_id),'profile',private.member_profile_snapshot(person.id),'membershipStatus',m.status,
   'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'kind',r.kind,'status',r.status,'payload',r.payload,'acceptedFields',r.accepted_fields,'reason',r.reason,'createdAt',r.created_at) order by created_at desc) from (select * from private.member_profile_requests where organization_id=p_org and user_id=auth.uid() order by created_at desc limit 20) r),'[]'));
 end if;
 if p_action is distinct from 'submit' or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>6000 or p_data='{}'::jsonb then raise exception 'invalid_member_profile' using errcode='22023'; end if;
 for k in select jsonb_object_keys(p_data) loop
  if not k=any(allowed) or jsonb_typeof(p_data->k)<>'string' or length(p_data->>k)>200 then raise exception 'invalid_member_profile' using errcode='22023'; end if;
 end loop;
 if p_data ? 'full_name' and length(trim(p_data->>'full_name')) not between 2 and 160
 or coalesce(p_data->>'birth_date','')<>'' and (p_data->>'birth_date' !~ '^\d{4}-\d{2}-\d{2}$' or (p_data->>'birth_date')::date>current_date)
 or coalesce(p_data->>'cpf','')<>'' and p_data->>'cpf' !~ '^\d{11}$'
 or coalesce(p_data->>'state','')<>'' and p_data->>'state' !~ '^[A-Z]{2}$' then raise exception 'invalid_member_profile' using errcode='22023'; end if;
 select * into request from private.member_profile_requests where organization_id=p_org and user_id=auth.uid() and status='pending' for update;
 if found then
  if request.payload=p_data and request.unit_id=coalesce(p_unit,person.unit_id) then return jsonb_build_object('ok',true,'id',request.id,'pending',true); end if;
  raise exception 'member_request_pending' using errcode='40001';
 end if;
 kind:=case when person.id is null or m.status='pending' then 'registration' else 'update' end;
 if (select count(*) from private.member_profile_requests where user_id=auth.uid() and created_at>clock_timestamp()-interval '1 day')>=20 then raise exception 'member_daily_limit' using errcode='54000'; end if;
 if person.id is null then
  if length(trim(coalesce(p_data->>'full_name','')))<2 then raise exception 'invalid_member_profile' using errcode='22023'; end if;
  perform 1 from public.organization_units where organization_id=p_org and id=p_unit and status='active' for share;
  if not found then raise exception 'member_unit_denied' using errcode='42501'; end if;
  -- A matching email is only a candidate for human review; never auto-link identity.
  if (select count(*) from public.people where organization_id=p_org and (lower(email)=account_email or nullif(p_data->>'cpf','') is not null and cpf=p_data->>'cpf') and status not in ('rejected','deceased'))>1 then raise exception 'member_identity_ambiguous' using errcode='40001'; end if;
  select * into person from public.people where organization_id=p_org and (lower(email)=account_email or nullif(p_data->>'cpf','') is not null and cpf=p_data->>'cpf') and status not in ('rejected','deceased') for update;
  if person.id is null then
   insert into public.people(organization_id,unit_id,auth_user_id,full_name,email,status) values(p_org,p_unit,auth.uid(),trim(p_data->>'full_name'),account_email,'pending') returning * into person;
  end if;
 end if;
 if kind='update' then p_unit:=person.unit_id; end if;
 if p_unit is null or not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active') then raise exception 'member_unit_denied' using errcode='42501'; end if;
 if m.id is null then
  insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(p_org,auth.uid(),p_unit,'member','pending') returning * into m;
 end if;
 insert into private.member_profile_requests(organization_id,unit_id,user_id,person_id,kind,payload,baseline)
 values(p_org,p_unit,auth.uid(),person.id,kind,p_data,private.member_profile_snapshot(person.id)) returning * into request;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.profile.submitted','member_profile_request',request.id,jsonb_build_object('kind',kind));
 return jsonb_build_object('ok',true,'id',request.id,'pending',true);
end $$;
revoke all on function private.member_self_service(uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function private.member_self_service(uuid,text,uuid,jsonb) to authenticated;
create function public.member_self_service(p_org uuid,p_action text,p_unit uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_self_service(p_org,p_action,p_unit,p_data)$$;
revoke all on function public.member_self_service(uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function public.member_self_service(uuid,text,uuid,jsonb) to authenticated;

create function private.member_profile_review(p_org uuid,p_action text,p_id uuid default null,p_fields text[] default '{}',p_reason text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.member_profile_requests; person public.people; current_profile jsonb; k text; account_email text; m public.organization_memberships;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in ('active','trial') for update;
 if not found or not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'member_review_denied' using errcode='42501'; end if;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active' for share;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q) order by created_at) from (select req.*,u.name as unit_name,p.full_name as person_name from private.member_profile_requests req join public.organization_units u on u.id=req.unit_id left join public.people p on p.id=req.person_id where req.organization_id=p_org and req.status='pending' order by req.created_at limit 100) q),'[]'));
 end if;
 if p_action is distinct from 'review' or p_reason is null or length(trim(p_reason)) not between 5 and 1000 then raise exception 'invalid_member_review' using errcode='22023'; end if;
 select * into r from private.member_profile_requests where organization_id=p_org and id=p_id for update;
 if not found or r.status<>'pending' then raise exception 'member_request_changed' using errcode='40001'; end if;
 if p_fields is null or cardinality(p_fields)<>(select count(distinct field) from unnest(p_fields) field) or exists(select 1 from unnest(p_fields) field where field is null or not r.payload ? field) then raise exception 'invalid_member_review' using errcode='22023'; end if;
 if cardinality(p_fields)>0 then
  select email into account_email from auth.users where id=r.user_id and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=clock_timestamp()) for share;
  if not found then raise exception 'member_review_denied' using errcode='42501'; end if;
  select * into m from public.organization_memberships where organization_id=p_org and user_id=r.user_id for update;
  if not found or m.status in ('suspended','revoked') then raise exception 'member_review_denied' using errcode='42501'; end if;
  select * into person from public.people where id=r.person_id and organization_id=p_org for update;
  if not found or person.status in ('rejected','deceased','inactive') or person.auth_user_id is not null and person.auth_user_id<>r.user_id
   or person.auth_user_id is null and (lower(person.email) is distinct from lower(account_email) or person.unit_id is distinct from r.unit_id)
   or exists(select 1 from public.people where organization_id=p_org and auth_user_id=r.user_id and id<>person.id and status<>'rejected') then raise exception 'member_identity_conflict' using errcode='40001'; end if;
  if r.kind='registration' and not 'full_name'=any(p_fields) then raise exception 'invalid_member_review' using errcode='22023'; end if;
  current_profile:=private.member_profile_snapshot(person.id);
  foreach k in array p_fields loop
   if (current_profile->k) is distinct from (r.baseline->k) then raise exception 'member_profile_changed' using errcode='40001'; end if;
   if k in ('full_name','phone','gender','marital_status','cpf') then execute format('update public.people set %I=$1 where id=$2 and organization_id=$3',k) using nullif(trim(r.payload->>k),''),person.id,p_org;
   elsif k='birth_date' then update public.people set birth_date=nullif(r.payload->>k,'')::date where id=person.id and organization_id=p_org;
   else
    insert into public.person_addresses(organization_id,person_id) values(p_org,person.id) on conflict(organization_id,person_id) do nothing;
    execute format('update public.person_addresses set %I=$1 where person_id=$2 and organization_id=$3',k) using nullif(trim(r.payload->>k),''),person.id,p_org;
   end if;
  end loop;
  if r.kind='registration' then
   update public.people set auth_user_id=r.user_id,status=case when status='pending' then 'active' else status end where id=person.id and organization_id=p_org;
   update public.organization_memberships set status='active' where id=m.id and status='pending' and role='member';
  end if;
 end if;
 update private.member_profile_requests set status=case when cardinality(p_fields)=0 then 'rejected' when cardinality(p_fields)=(select count(*) from jsonb_object_keys(r.payload)) then 'approved' else 'partial' end,accepted_fields=p_fields,reason=trim(p_reason),reviewed_by=auth.uid(),reviewed_at=clock_timestamp() where id=r.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.profile.reviewed','member_profile_request',r.id,jsonb_build_object('acceptedFields',p_fields));
 return jsonb_build_object('ok',true,'id',r.id);
end $$;
revoke all on function private.member_profile_review(uuid,text,uuid,text[],text) from public,anon,service_role;
grant execute on function private.member_profile_review(uuid,text,uuid,text[],text) to authenticated;
create function public.member_profile_review(p_org uuid,p_action text,p_id uuid default null,p_fields text[] default '{}',p_reason text default '') returns jsonb language sql security invoker set search_path='' as $$select private.member_profile_review(p_org,p_action,p_id,p_fields,p_reason)$$;
revoke all on function public.member_profile_review(uuid,text,uuid,text[],text) from public,anon,service_role;
grant execute on function public.member_profile_review(uuid,text,uuid,text[],text) to authenticated;

-- Extend the existing manager-only directory, preserving its established access checks.
do $$declare definition text; anchor text:='''id'',m.id,''name'',coalesce(p.full_name,a.email,''Usuário'')'; begin
 definition:=pg_get_functiondef('public.staff_directory(uuid)'::regprocedure);
 if position('''person_id''' in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'staff_directory_definition_changed'; end if;
 definition:=replace(definition,anchor,'''id'',m.id,''person_id'',(select person.id from public.people person where person.organization_id=m.organization_id and person.auth_user_id=m.user_id and person.status<>''rejected'' order by person.created_at limit 1),''name'',coalesce((select person.full_name from public.people person where person.organization_id=m.organization_id and person.auth_user_id=m.user_id and person.status<>''rejected'' order by person.created_at limit 1),p.full_name,a.email,''Usuário'')');
 execute definition;
end $$;
