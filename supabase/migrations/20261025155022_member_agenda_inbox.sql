set local lock_timeout='5s';
create table private.church_app_events(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 title text not null check(length(title) between 2 and 160),description text not null default '' check(length(description)<=4000),kind text not null check(kind in('event','service')),
 starts_at timestamptz not null,ends_at timestamptz not null,location text not null default '' check(length(location)<=160),address text not null default '' check(length(address)<=300),
 capacity integer not null check(capacity between 1 and 50000),status text not null default 'draft' check(status in('draft','published','cancelled')),version integer not null default 1,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),published_at timestamptz,
 check(ends_at>starts_at),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),unique(id,organization_id,unit_id)
);
create index church_app_events_scope on private.church_app_events(organization_id,unit_id,status,starts_at,id);
create table private.church_app_registrations(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,event_id uuid not null,
 user_id uuid not null references auth.users(id),person_id uuid not null references public.people(id),name text not null,
 status text not null default 'confirmed' check(status in('confirmed','cancelled')),code uuid not null unique default extensions.gen_random_uuid(),
 checked_in_at timestamptz,checked_in_by uuid references auth.users(id),version integer not null default 1,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 unique(event_id,user_id),foreign key(event_id,organization_id,unit_id) references private.church_app_events(id,organization_id,unit_id)
);
create index church_app_registrations_user on private.church_app_registrations(organization_id,user_id,created_at,id);
create index church_app_registrations_event on private.church_app_registrations(event_id,status);
create index church_app_registrations_person on private.church_app_registrations(person_id);
create index church_app_registrations_checker on private.church_app_registrations(checked_in_by);
create index church_app_registrations_unit on private.church_app_registrations(unit_id,organization_id);
create table private.member_inbox_reads(
 organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),message_key text not null check(length(message_key)<=150),
 read_at timestamptz not null default clock_timestamp(),primary key(organization_id,user_id,message_key)
);
create index member_inbox_reads_user on private.member_inbox_reads(user_id);
alter table private.church_app_events enable row level security;
alter table private.church_app_registrations enable row level security;
alter table private.member_inbox_reads enable row level security;
revoke all on private.church_app_events,private.church_app_registrations,private.member_inbox_reads from public,anon,authenticated,service_role;

-- Contract eligibility only, without giving a public viewer any unit permission.
create function private.member_event_enabled(p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations o join public.organization_units u on u.organization_id=o.id where o.id=p_org and o.status in('active','trial') and u.id=p_unit and u.status='active')
 and exists(select 1 from public.saas_module_catalog where code='events')
 and not exists(select 1 from public.saas_unit_contracts c where c.organization_id=p_org and c.unit_id=p_unit and c.status<>'draft'
  and not(c.status='active' and case when c.module_decisions ? 'events' then c.module_decisions->'events'='true'::jsonb else exists(select 1 from public.saas_plan_modules pm where pm.plan_id=c.plan_id and pm.module_code='events' and pm.included) end));
$$;
revoke all on function private.member_event_enabled(uuid,uuid) from public,anon,authenticated,service_role;

create function member_app_api.agenda(p_org uuid,p_unit uuid,p_past boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_event_enabled(p_org,p_unit) then return jsonb_build_object('unitId',p_unit,'available',false,'items','[]'::jsonb);end if;
 return jsonb_build_object('unitId',p_unit,'available',true,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from(
  select e.id,e.title,e.description,e.kind,e.starts_at,e.ends_at,e.location,e.address,e.capacity,e.status,e.version,
  greatest(0,e.capacity-(select count(*) from private.church_app_registrations r where r.event_id=e.id and r.status='confirmed')) as remaining
  from private.church_app_events e where e.organization_id=p_org and e.unit_id=p_unit and e.status in('published','cancelled')
  and case when p_past then e.ends_at<now() and e.ends_at>now()-interval '1 year' else e.ends_at>=now() end order by e.starts_at limit 100)x),'[]'));
end $$;
revoke all on function member_app_api.agenda(uuid,uuid,boolean) from public,service_role;
grant execute on function member_app_api.agenda(uuid,uuid,boolean) to anon,authenticated;
create function public.member_agenda(p_org uuid,p_unit uuid,p_past boolean default false) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.agenda(p_org,p_unit,p_past)$$;
revoke all on function public.member_agenda(uuid,uuid,boolean) from public,service_role;
grant execute on function public.member_agenda(uuid,uuid,boolean) to anon,authenticated;

create function private.member_inbox_rows(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $$
 select * from(
 select 'post:'||p.id as message_key,p.title,p.body,p.created_at as occurred_at,'content'::text as target,p.id as target_id from private.member_publications p
 join public.organization_units u on u.id=p.unit_id and u.organization_id=p.organization_id and u.status='active'
 where p.organization_id=p_org and p.unit_id=p_unit and p.published and p.created_at>now()-interval '90 days'
 union all
 select 'event:'||e.id||':'||e.version,e.title,case when e.status='cancelled' then 'Evento cancelado pela igreja.' else 'Programação publicada ou atualizada. Confira data e local.' end,e.updated_at,'agenda',e.id
 from private.church_app_events e where e.organization_id=p_org and e.unit_id=p_unit and e.status in('published','cancelled') and e.updated_at>now()-interval '90 days' and private.member_event_enabled(p_org,p_unit)
 union all
 select 'ticket:'||r.id||':'||r.version||':'||e.version,e.title,case when e.status='cancelled' then 'Evento cancelado. Seu ticket não permite entrada.' when r.status='cancelled' then 'Sua inscrição foi cancelada.' when r.checked_in_at is not null then 'Sua entrada foi confirmada.' else 'Sua inscrição gratuita está confirmada. Consulte seu ticket.' end,greatest(r.updated_at,e.updated_at),'ticket',r.id
 from private.church_app_registrations r join private.church_app_events e on e.id=r.event_id where r.organization_id=p_org and r.user_id=auth.uid()
 union all
 select 'profile:'||r.id||':'||r.status,'Revisão do cadastro',coalesce(r.reason,'Sua solicitação foi revisada.'),r.reviewed_at,'profile',r.id from private.member_profile_requests r where r.organization_id=p_org and r.user_id=auth.uid() and r.status<>'pending'
 union all
 select 'transfer:'||r.id||':'||r.status,'Transferência de igreja',case when r.status='approved' then 'Transferência aprovada. ' when r.status='rejected' then 'Transferência recusada. ' else 'Solicitação cancelada. ' end||r.reason,r.reviewed_at,'church',r.id from private.member_church_transfers r where r.organization_id=p_org and r.user_id=auth.uid() and r.status<>'pending'
 )q order by occurred_at desc nulls last,message_key limit 100;
$$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated,service_role;

create function private.member_agenda_self(p_org uuid,p_action text,p_unit uuid default null,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;person public.people;e private.church_app_events;r private.church_app_registrations;keys text[];
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in('active','trial') for update;
 if not found then raise exception 'member_agenda_denied' using errcode='42501';end if;
 select * into m from public.organization_memberships where organization_id=p_org and user_id=auth.uid() for update;
 if m.status in('suspended','revoked') then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_unit is not null and not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active') then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_action='inbox' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q)||jsonb_build_object('read',exists(select 1 from private.member_inbox_reads x where x.organization_id=p_org and x.user_id=auth.uid() and x.message_key=q.message_key)) order by q.occurred_at desc nulls last,q.message_key) from private.member_inbox_rows(p_org,p_unit)q),'[]'));
 elsif p_action='read' then
  if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['keys']<>'{}' or jsonb_typeof(p_data->'keys') is distinct from 'array' or jsonb_array_length(p_data->'keys') not between 1 and 100 or exists(select 1 from jsonb_array_elements(p_data->'keys')v where jsonb_typeof(v)<>'string') then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  select array_agg(v) into keys from jsonb_array_elements_text(p_data->'keys')v;
  if cardinality(keys)<>(select count(distinct v) from unnest(keys)v) or (select count(*) from private.member_inbox_rows(p_org,p_unit)q where q.message_key=any(keys))<>cardinality(keys) then raise exception 'member_inbox_changed' using errcode='40001';end if;
  insert into private.member_inbox_reads(organization_id,user_id,message_key) select p_org,auth.uid(),v from unnest(keys)v on conflict do nothing;
  return jsonb_build_object('ok',true);
 elsif p_action='tickets' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q) order by q.starts_at desc) from(
   select reg.id,reg.event_id,reg.unit_id,reg.name,reg.status,reg.checked_in_at,reg.version,evt.title,evt.starts_at,evt.ends_at,evt.location,evt.address,evt.status as event_status,
    case when reg.status='confirmed' and evt.status='published' and evt.ends_at+interval '6 hours'>clock_timestamp() and private.member_event_enabled(p_org,reg.unit_id) then reg.code else null end as code
   from private.church_app_registrations reg join private.church_app_events evt on evt.id=reg.event_id where reg.organization_id=p_org and reg.user_id=auth.uid() order by evt.starts_at desc limit 100)q),'[]'));
 elsif p_action not in('register','cancel') or p_action is null or p_data<>'{}'::jsonb then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 if p_action='register' then
  select * into e from private.church_app_events where id=p_id and organization_id=p_org for update;
  if not found or e.status<>'published' or e.starts_at<=clock_timestamp() or not private.member_event_enabled(p_org,e.unit_id) then raise exception 'member_event_closed' using errcode='40001';end if;
  if m.status is distinct from 'active' then raise exception 'member_registration_identity' using errcode='42501';end if;
  if (select count(*) from public.people where organization_id=p_org and auth_user_id=auth.uid() and status='active')<>1 then raise exception 'member_registration_identity' using errcode='42501';end if;
  select * into person from public.people where organization_id=p_org and auth_user_id=auth.uid() and status='active' for share;
  select * into r from private.church_app_registrations where event_id=e.id and user_id=auth.uid() for update;
  if r.status='confirmed' then return jsonb_build_object('ok',true,'id',r.id);end if;
  if (select count(*) from private.church_app_registrations where event_id=e.id and status='confirmed')>=e.capacity then raise exception 'member_event_full' using errcode='40001';end if;
  if r.id is null then insert into private.church_app_registrations(organization_id,unit_id,event_id,user_id,person_id,name) values(p_org,e.unit_id,e.id,auth.uid(),person.id,person.full_name) returning * into r;
  else update private.church_app_registrations set status='confirmed',name=person.full_name,code=extensions.gen_random_uuid(),version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;end if;
 else
  select * into r from private.church_app_registrations where id=p_id and organization_id=p_org and user_id=auth.uid();
  if not found then raise exception 'member_agenda_denied' using errcode='42501';end if;
  select * into e from private.church_app_events where id=r.event_id and organization_id=p_org for update;
  select * into r from private.church_app_registrations where id=p_id and user_id=auth.uid() for update;
  if r.status='cancelled' then return jsonb_build_object('ok',true,'id',r.id);end if;
  if r.checked_in_at is not null or e.starts_at<=clock_timestamp() then raise exception 'member_cancel_closed' using errcode='40001';end if;
  update private.church_app_registrations set status='cancelled',code=extensions.gen_random_uuid(),version=version+1,updated_at=clock_timestamp() where id=r.id;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.agenda.'||p_action,'church_app_registration',r.id);
 return jsonb_build_object('ok',true,'id',r.id);
end $$;
revoke all on function private.member_agenda_self(uuid,text,uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function private.member_agenda_self(uuid,text,uuid,uuid,jsonb) to authenticated;
create function public.member_agenda_self(p_org uuid,p_action text,p_unit uuid default null,p_id uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_agenda_self(p_org,p_action,p_unit,p_id,p_data)$$;
revoke all on function public.member_agenda_self(uuid,text,uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.member_agenda_self(uuid,text,uuid,uuid,jsonb) to authenticated;

create function private.member_agenda_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;r private.church_app_registrations;start_time timestamptz;end_time timestamptz;seats integer;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in('active','trial') for update;
 if not found or not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) or not private.member_event_enabled(p_org,p_unit) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_action='list' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q) order by q.starts_at desc) from(select e1.*,(select count(*) from private.church_app_registrations r1 where r1.event_id=e1.id and r1.status='confirmed') registrations from private.church_app_events e1 where e1.organization_id=p_org and e1.unit_id=p_unit order by e1.starts_at desc limit 100)q),'[]'));end if;
 if p_action<>'create' then
  select * into e from private.church_app_events where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'member_agenda_denied' using errcode='42501';end if;
  if p_action='attendees' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q)) from(select id,name,status,checked_in_at,created_at from private.church_app_registrations where event_id=e.id order by name limit 500)q),'[]'));end if;
  if p_action='checkin' then
   if p_data-array['code']<>'{}'::jsonb or e.status<>'published' or clock_timestamp() not between e.starts_at-interval '2 hours' and e.ends_at+interval '6 hours' then raise exception 'member_checkin_closed' using errcode='40001';end if;
   select * into r from private.church_app_registrations where event_id=e.id and code=(p_data->>'code')::uuid and status='confirmed' for update;
   if not found then raise exception 'member_ticket_invalid' using errcode='42501';end if;
   if not exists(select 1 from public.organization_memberships m join auth.users a on a.id=m.user_id join public.people p on p.auth_user_id=a.id and p.id=r.person_id and p.organization_id=m.organization_id
    where m.organization_id=p_org and m.user_id=r.user_id and m.status='active' and p.status='active' and a.email_confirmed_at is not null and a.deleted_at is null and not coalesce(a.is_anonymous,false) and (a.banned_until is null or a.banned_until<=clock_timestamp())) then raise exception 'member_ticket_invalid' using errcode='42501';end if;
   if r.checked_in_at is not null then return jsonb_build_object('ok',true,'id',r.id,'already',true,'name',r.name);end if;
   update private.church_app_registrations set checked_in_at=clock_timestamp(),checked_in_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=r.id;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.agenda.checkin','church_app_registration',r.id);
   return jsonb_build_object('ok',true,'id',r.id,'name',r.name);
  end if;
  if p_version is distinct from e.version then raise exception 'member_event_changed' using errcode='40001';end if;
 end if;
 if p_action in('create','edit') then
  if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['title','description','kind','startsLocal','endsLocal','location','address','capacity']<>'{}'::jsonb
   or not(p_data ?& array['title','description','kind','startsLocal','endsLocal','location','address','capacity'])
   or exists(select 1 from jsonb_each(p_data)j where j.key<>'capacity' and jsonb_typeof(j.value)<>'string')
   or length(btrim(p_data->>'title')) not between 2 and 160 or length(p_data->>'description')>4000 or p_data->>'kind' not in('event','service')
   or length(p_data->>'location')>160 or length(p_data->>'address')>300 or p_data->>'capacity' !~ '^[0-9]{1,5}$'
   or p_data->>'startsLocal' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' or p_data->>'endsLocal' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  seats:=(p_data->>'capacity')::integer;start_time:=(p_data->>'startsLocal')::timestamp at time zone 'America/Sao_Paulo';end_time:=(p_data->>'endsLocal')::timestamp at time zone 'America/Sao_Paulo';
  if seats not between 1 and 50000 or end_time<=start_time or start_time>now()+interval '2 years' or (p_action='create' or start_time is distinct from e.starts_at) and start_time<=now() or seats<(select count(*) from private.church_app_registrations where event_id=e.id and status='confirmed') then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  if p_action='create' then insert into private.church_app_events(organization_id,unit_id,title,description,kind,starts_at,ends_at,location,address,capacity) values(p_org,p_unit,btrim(p_data->>'title'),p_data->>'description',p_data->>'kind',start_time,end_time,p_data->>'location',p_data->>'address',seats) returning * into e;
  else
   if e.status='cancelled' or e.ends_at<=now() then raise exception 'member_event_closed' using errcode='40001';end if;
   update private.church_app_events set title=btrim(p_data->>'title'),description=p_data->>'description',kind=p_data->>'kind',starts_at=start_time,ends_at=end_time,location=p_data->>'location',address=p_data->>'address',capacity=seats,version=version+1,updated_at=clock_timestamp() where id=e.id returning * into e;
  end if;
 elsif p_action in('publish','cancel') then
  if p_data<>'{}'::jsonb or e.status='cancelled' or e.starts_at<=clock_timestamp() then raise exception 'member_event_closed' using errcode='40001';end if;
  update private.church_app_events set status=case when p_action='publish' then 'published' else 'cancelled' end,published_at=case when p_action='publish' then coalesce(published_at,clock_timestamp()) else published_at end,updated_at=clock_timestamp(),version=version+1 where id=e.id returning * into e;
 else raise exception 'invalid_member_agenda' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.agenda.'||p_action,'church_app_event',e.id);
 return jsonb_build_object('ok',true,'id',e.id,'version',e.version);
end $$;
revoke all on function private.member_agenda_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.member_agenda_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.member_agenda_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_agenda_admin(p_org,p_unit,p_action,p_id,p_version,p_data)$$;
revoke all on function public.member_agenda_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.member_agenda_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
