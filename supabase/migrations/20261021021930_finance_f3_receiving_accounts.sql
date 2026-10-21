-- F3 receiving connections. No payment/checkout/charge activation (F4).
set local lock_timeout='5s';
create table private.finance_receivers (
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 provider text not null check(provider in('mercado_pago','asaas','safe2pay')),environment text not null check(environment in('sandbox','production')),
 status text not null check(status in('opening_external','connected','configured','revoked','blocked','reauthorize')),
 external_id text,holder text,provider_status text,expires_at timestamptz,account_id uuid,beneficiary_units uuid[] not null default '{}',methods text[] not null default '{}',holder_confirmed boolean not null default false,
 version integer not null default 1,updated_at timestamptz not null default now(),created_by uuid not null references auth.users(id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(account_id,organization_id) references private.finance_catalog(id,organization_id),unique(organization_id,unit_id,provider,environment),unique(id,organization_id,unit_id)
);
create index finance_receivers_unit on private.finance_receivers(unit_id,organization_id);
create index finance_receivers_account on private.finance_receivers(account_id,organization_id);
create index finance_receivers_creator on private.finance_receivers(created_by);
create table private.finance_receiver_secrets (
 receiver_id uuid primary key references private.finance_receivers(id),sealed text not null,updated_at timestamptz not null default now()
);
create table private.finance_receiver_attempts (
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,actor uuid not null references auth.users(id),environment text not null check(environment in('sandbox','production')),
 state_hash text not null unique,verifier_sealed text not null,base_version integer not null,expires_at timestamptz not null,claimed_at timestamptz,completed_at timestamptz,
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index finance_receiver_attempts_unit on private.finance_receiver_attempts(unit_id,organization_id);
create index finance_receiver_attempts_org on private.finance_receiver_attempts(organization_id);
create index finance_receiver_attempts_actor on private.finance_receiver_attempts(actor,expires_at);
create table private.finance_receiver_events (
 id uuid primary key default extensions.gen_random_uuid(),receiver_id uuid not null references private.finance_receivers(id),actor uuid not null references auth.users(id),action text not null,details jsonb not null,happened_at timestamptz not null default now()
);
create index finance_receiver_events_receiver on private.finance_receiver_events(receiver_id,happened_at);
create index finance_receiver_events_actor on private.finance_receiver_events(actor);
alter table private.finance_receivers enable row level security;
alter table private.finance_receiver_secrets enable row level security;
alter table private.finance_receiver_attempts enable row level security;
alter table private.finance_receiver_events enable row level security;
create policy finance_receivers_deny on private.finance_receivers as restrictive for all using(false) with check(false);
create policy finance_receiver_secrets_deny on private.finance_receiver_secrets as restrictive for all using(false) with check(false);
create policy finance_receiver_attempts_deny on private.finance_receiver_attempts as restrictive for all using(false) with check(false);
create policy finance_receiver_events_deny on private.finance_receiver_events as restrictive for all using(false) with check(false);
revoke all on private.finance_receivers,private.finance_receiver_secrets,private.finance_receiver_attempts,private.finance_receiver_events from public,anon,authenticated,service_role;
create function private.receiver_history_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'receiver_history_immutable' using errcode='42501';end$$;
revoke all on function private.receiver_history_immutable() from public,anon,authenticated,service_role;
create trigger receiver_history_immutable before update or delete on private.finance_receiver_events for each row execute function private.receiver_history_immutable();

-- Service proof writes revalidate the actual operator, not user-editable metadata.
create function private.receiver_actor_allowed(p_actor uuid,p_org uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users a join public.organization_memberships m on m.user_id=a.id
 join public.organizations o on o.id=m.organization_id join public.organization_units u on u.organization_id=o.id
 where a.id=p_actor and a.email is not null and a.email_confirmed_at is not null and a.deleted_at is null and not coalesce(a.is_anonymous,false) and (a.banned_until is null or a.banned_until<=clock_timestamp())
 and m.organization_id=p_org and m.status='active' and m.role in('owner','admin') and o.status in('active','trial') and u.id=p_unit and u.status='active')
 -- Same contract decision as target_unit_module_enabled, without relying on a service JWT's auth.uid().
 and exists(select 1 from public.saas_module_catalog where code='finance')
 and not exists(select 1 from public.saas_unit_contracts c where c.organization_id=p_org and c.unit_id=p_unit and c.status<>'draft'
  and not (c.status='active' and case when c.module_decisions ? 'finance' then c.module_decisions->'finance'='true'::jsonb else exists(select 1 from public.saas_plan_modules pm where pm.plan_id=c.plan_id and pm.module_code='finance' and pm.included) end));
$$;
revoke all on function private.receiver_actor_allowed(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function private.finance_receiver_settings(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.finance_receivers;item uuid;account private.finance_catalog;us uuid[];ms text[];before_value jsonb;result jsonb;
begin
 perform private.require_confirmed_self_service_email();
 if p_action in('central','central_hold','central_resume') then
  if not private.has_aal2() or not private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]) then raise exception 'central_access_denied' using errcode='42501';end if;
  if p_action='central' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select conn.id,conn.organization_id,o.name organization,conn.unit_id,u.name unit,conn.provider,conn.environment,conn.status,conn.holder,conn.external_id,conn.provider_status,conn.version,conn.updated_at,conn.expires_at,conn.holder_confirmed,conn.beneficiary_units,conn.methods from private.finance_receivers conn join public.organizations o on o.id=conn.organization_id join public.organization_units u on u.id=conn.unit_id order by conn.updated_at desc limit 200)x),'[]'));end if;
  if not private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]) then raise exception 'central_manager_required' using errcode='42501';end if;
  perform 1 from public.organizations where id=p_org for update;
  select * into r from private.finance_receivers where id=(p_data->>'id')::uuid and organization_id=p_org and unit_id=p_unit for update;
  if r.id is null or r.version is distinct from (p_data->>'version')::integer then raise exception 'receiver_version_conflict' using errcode='40001';end if;
  if jsonb_typeof(p_data->'reason') is distinct from 'string' or length(btrim(p_data->>'reason')) not between 5 and 300 then raise exception 'reason_required' using errcode='22023';end if;
  if p_action='central_hold' then update private.finance_receivers set status='blocked',holder_confirmed=false,version=version+1,updated_at=now() where id=r.id;
  else
   if r.status<>'blocked' then raise exception 'receiver_not_blocked' using errcode='22023';end if;
   update private.finance_receivers set status='reauthorize',version=version+1,updated_at=now() where id=r.id;
  end if;
  update private.finance_receiver_attempts set completed_at=now(),verifier_sealed='' where organization_id=p_org and unit_id=p_unit and completed_at is null;
  insert into private.finance_receiver_events(receiver_id,actor,action,details) values(r.id,auth.uid(),p_action,jsonb_build_object('reason',p_data->>'reason','previousStatus',r.status));
  return jsonb_build_object('ok',true,'id',r.id);
 end if;
 if p_org is null or p_unit is null or not private.church_ledger_allowed(p_org,p_unit) then raise exception 'receiver_access_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'receiver_access_denied' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(conn) order by conn.provider,conn.environment) from private.finance_receivers conn where conn.organization_id=p_org and conn.unit_id=p_unit),'[]'),
   'events',coalesce((select jsonb_agg(to_jsonb(x)) from(select e.id,e.receiver_id,e.actor,e.action,e.details,e.happened_at from private.finance_receiver_events e join private.finance_receivers conn on conn.id=e.receiver_id where conn.organization_id=p_org and conn.unit_id=p_unit order by e.happened_at desc,e.id limit 100)x),'[]'),
   'canManage',private.receiver_actor_allowed(auth.uid(),p_org,p_unit));
 end if;
 if not private.receiver_actor_allowed(auth.uid(),p_org,p_unit) then raise exception 'receiver_manager_required' using errcode='42501';end if;
 if p_data->>'provider' not in('mercado_pago','asaas','safe2pay') or p_data->>'environment' not in('sandbox','production') or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16384 then raise exception 'invalid_receiver' using errcode='22023';end if;
 select * into r from private.finance_receivers where organization_id=p_org and unit_id=p_unit and provider=p_data->>'provider' and environment=p_data->>'environment' for update;
 if p_action='open' then
  if r.id is null then insert into private.finance_receivers(organization_id,unit_id,provider,environment,status,created_by) values(p_org,p_unit,p_data->>'provider',p_data->>'environment','opening_external',auth.uid()) returning * into r;
   insert into private.finance_receiver_events(receiver_id,actor,action,details) values(r.id,auth.uid(),'opening_external','{}');end if;
  return jsonb_build_object('ok',true,'id',r.id);
 end if;
 if r.id is null or r.version is distinct from (p_data->>'version')::integer then raise exception 'receiver_version_conflict' using errcode='40001';end if;
 before_value:=to_jsonb(r);
 if p_action='revoke' then
  -- A church can discard credentials, but cannot clear a Central hold by revoking/reconnecting.
  update private.finance_receivers set status=case when status='blocked' then 'blocked' else 'revoked' end,holder_confirmed=false,version=version+1,updated_at=now() where id=r.id;
  delete from private.finance_receiver_secrets where receiver_id=r.id;
  update private.finance_receiver_attempts set completed_at=now(),verifier_sealed='' where organization_id=p_org and unit_id=p_unit and environment=r.environment and completed_at is null;
 elsif p_action='configure' then
  if r.status not in('connected','configured') or r.expires_at is null or r.expires_at<=now() or p_data->'holderConfirmed' is distinct from 'true'::jsonb then raise exception 'receiver_not_connected' using errcode='22023';end if;
  us:=array(select jsonb_array_elements_text(p_data->'units')::uuid);ms:=array(select jsonb_array_elements_text(p_data->'methods'));
  if cardinality(us) not between 1 and 100 or (select count(distinct x) from unnest(us)x)<>cardinality(us) or cardinality(ms) not between 1 and 4 or not ms<@array['pix','boleto','card','recurring']::text[] or (select count(distinct x) from unnest(ms)x)<>cardinality(ms) then raise exception 'invalid_receiver_scope' using errcode='22023';end if;
  -- Only a headquarters receiving account can cover other units, all explicitly selected.
  if us<>array[p_unit] and not exists(select 1 from public.organization_units where id=p_unit and unit_type='headquarters') then raise exception 'headquarters_required' using errcode='22023';end if;
  foreach item in array us loop if not private.receiver_actor_allowed(auth.uid(),p_org,item) then raise exception 'beneficiary_not_allowed' using errcode='42501';end if;end loop;
  select * into account from private.finance_catalog where id=(p_data->>'account')::uuid and organization_id=p_org and unit_id=p_unit and kind='account' and active;
  if account.id is null then raise exception 'receiver_account_invalid' using errcode='22023';end if;
  update private.finance_receivers set status='configured',account_id=account.id,beneficiary_units=us,methods=ms,holder_confirmed=true,version=version+1,updated_at=now() where id=r.id;
 else raise exception 'receiver_action_invalid' using errcode='22023';end if;
 select to_jsonb(x) into result from private.finance_receivers x where id=r.id;
 insert into private.finance_receiver_events(receiver_id,actor,action,details) values(r.id,auth.uid(),p_action,jsonb_build_object('before',before_value,'after',result));
 return jsonb_build_object('ok',true,'id',r.id);
end $$;
revoke all on function private.finance_receiver_settings(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_receiver_settings(uuid,uuid,text,jsonb) to authenticated;
create function public.finance_receiver_settings(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.finance_receiver_settings(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_receiver_settings(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.finance_receiver_settings(uuid,uuid,text,jsonb) to authenticated;

create function private.finance_receiver_server(p_actor uuid,p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.finance_receivers;a private.finance_receiver_attempts;v integer;result jsonb;req uuid;
begin
 if p_actor is null or p_org is null or p_unit is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>32768 or not private.receiver_actor_allowed(p_actor,p_org,p_unit) then raise exception 'receiver_server_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform 1 from auth.users where id=p_actor for share;
 if not private.receiver_actor_allowed(p_actor,p_org,p_unit) then raise exception 'receiver_server_denied' using errcode='42501';end if;
 if p_data->>'environment' is null or p_data->>'environment' not in('sandbox','production') then raise exception 'receiver_environment_invalid' using errcode='22023';end if;
 if coalesce(p_data->>'provider','mercado_pago') not in('mercado_pago','asaas') then raise exception 'receiver_provider_not_supported' using errcode='22023';end if;
 select * into r from private.finance_receivers where organization_id=p_org and unit_id=p_unit and provider=coalesce(p_data->>'provider','mercado_pago') and environment=p_data->>'environment' for update;
 if p_action='key_complete' then
  if p_data->>'provider' is distinct from 'asaas' or r.status='blocked' or coalesce(r.version,0) is distinct from (p_data->>'version')::integer then raise exception 'receiver_connection_changed' using errcode='40001';end if;
  if jsonb_typeof(p_data->'externalId') is distinct from 'string' or p_data->>'externalId'!~'^asaas:[a-f0-9]{64}$' or jsonb_typeof(p_data->'holder') is distinct from 'string' or length(btrim(p_data->>'holder')) not between 1 and 160 or jsonb_typeof(p_data->'sealed') is distinct from 'string' or length(p_data->>'sealed') not between 32 and 16384 or nullif(p_data->>'expiresAt','') is null or (p_data->>'expiresAt')::timestamptz<=now() then raise exception 'invalid_provider_proof' using errcode='22023';end if;
  if r.id is null then insert into private.finance_receivers(organization_id,unit_id,provider,environment,status,created_by) values(p_org,p_unit,'asaas',p_data->>'environment','connected',p_actor) returning * into r;end if;
  update private.finance_receivers set status='connected',external_id=p_data->>'externalId',holder=p_data->>'holder',provider_status='identity_checked_24h',expires_at=(p_data->>'expiresAt')::timestamptz,holder_confirmed=false,methods='{}',beneficiary_units='{}',account_id=null,version=version+1,updated_at=now() where id=r.id;
  insert into private.finance_receiver_secrets values(r.id,p_data->>'sealed',now()) on conflict(receiver_id) do update set sealed=excluded.sealed,updated_at=excluded.updated_at;
 elsif p_action='begin' then
  if coalesce(p_data->>'provider','mercado_pago')<>'mercado_pago' then raise exception 'oauth_provider_invalid' using errcode='22023';end if;
  if r.status='blocked' then raise exception 'receiver_blocked' using errcode='42501';end if;
  if (select count(*) from private.finance_receiver_attempts where actor=p_actor and expires_at>now()-interval '10 minutes')>=5 then raise exception 'receiver_attempt_limit' using errcode='22023';end if;
  if jsonb_typeof(p_data->'stateHash') is distinct from 'string' or p_data->>'stateHash'!~'^[a-f0-9]{64}$' or jsonb_typeof(p_data->'verifier') is distinct from 'string' or length(p_data->>'verifier') not between 32 and 4096 then raise exception 'invalid_oauth_state' using errcode='22023';end if;
  req:=(p_data->>'id')::uuid;
  insert into private.finance_receiver_attempts(id,organization_id,unit_id,actor,environment,state_hash,verifier_sealed,base_version,expires_at) values(req,p_org,p_unit,p_actor,p_data->>'environment',p_data->>'stateHash',p_data->>'verifier',coalesce(r.version,0),now()+interval '10 minutes');
  return jsonb_build_object('ok',true,'id',req);
 elsif p_action='claim' then
  if coalesce(p_data->>'provider','mercado_pago')<>'mercado_pago' then raise exception 'oauth_provider_invalid' using errcode='22023';end if;
  select * into a from private.finance_receiver_attempts where state_hash=p_data->>'stateHash' and actor=p_actor and organization_id=p_org and unit_id=p_unit and environment=p_data->>'environment' and expires_at>now() and claimed_at is null and completed_at is null for update;
  if a.id is null then raise exception 'oauth_expired_or_used' using errcode='42501';end if;
  update private.finance_receiver_attempts set claimed_at=now() where id=a.id;
  return jsonb_build_object('id',a.id,'verifier',a.verifier_sealed);
 elsif p_action='complete' then
  if coalesce(p_data->>'provider','mercado_pago')<>'mercado_pago' then raise exception 'oauth_provider_invalid' using errcode='22023';end if;
  select * into a from private.finance_receiver_attempts where id=(p_data->>'attempt')::uuid and actor=p_actor and organization_id=p_org and unit_id=p_unit and environment=p_data->>'environment' and expires_at>now() and claimed_at is not null and completed_at is null for update;
  if a.id is null or a.base_version is distinct from coalesce(r.version,0) or r.status='blocked' then raise exception 'oauth_connection_changed' using errcode='40001';end if;
  if jsonb_typeof(p_data->'externalId') is distinct from 'string' or p_data->>'externalId'!~'^[0-9]{1,30}$' or jsonb_typeof(p_data->'holder') is distinct from 'string' or length(btrim(p_data->>'holder')) not between 1 and 160 or jsonb_typeof(p_data->'sealed') is distinct from 'string' or length(p_data->>'sealed') not between 32 and 16384 or nullif(p_data->>'expiresAt','') is null or (p_data->>'expiresAt')::timestamptz<=now() then raise exception 'invalid_provider_proof' using errcode='22023';end if;
  if r.id is null then insert into private.finance_receivers(organization_id,unit_id,provider,environment,status,created_by) values(p_org,p_unit,'mercado_pago',a.environment,'connected',p_actor) returning * into r;end if;
  update private.finance_receivers set status='connected',external_id=p_data->>'externalId',holder=p_data->>'holder',provider_status='identity_verified',expires_at=(p_data->>'expiresAt')::timestamptz,holder_confirmed=false,methods='{}',beneficiary_units='{}',account_id=null,version=version+1,updated_at=now() where id=r.id;
  insert into private.finance_receiver_secrets values(r.id,p_data->>'sealed',now()) on conflict(receiver_id) do update set sealed=excluded.sealed,updated_at=excluded.updated_at;
  update private.finance_receiver_attempts set completed_at=now(),verifier_sealed='' where id=a.id;
 elsif p_action in('secret','refreshed','reauthorize') then
  if r.id is null or r.status not in('connected','configured') or r.version is distinct from (p_data->>'version')::integer then raise exception 'receiver_connection_changed' using errcode='40001';end if;
  if p_action='secret' then return jsonb_build_object('sealed',(select sealed from private.finance_receiver_secrets where receiver_id=r.id),'externalId',r.external_id,'version',r.version);end if;
  if p_action='refreshed' then
   if p_data->>'externalId' is distinct from r.external_id or nullif(p_data->>'expiresAt','') is null or (p_data->>'expiresAt')::timestamptz<=now() or jsonb_typeof(p_data->'sealed') is distinct from 'string' or length(p_data->>'sealed') not between 32 and 16384 then raise exception 'receiver_identity_changed' using errcode='22023';end if;
   update private.finance_receiver_secrets set sealed=p_data->>'sealed',updated_at=now() where receiver_id=r.id;
   update private.finance_receivers set expires_at=(p_data->>'expiresAt')::timestamptz,version=version+1,updated_at=now() where id=r.id;
  else update private.finance_receivers set status='reauthorize',holder_confirmed=false,version=version+1,updated_at=now() where id=r.id;end if;
 else raise exception 'receiver_server_action_invalid' using errcode='22023';end if;
 insert into private.finance_receiver_events(receiver_id,actor,action,details) values(r.id,p_actor,p_action,jsonb_build_object('provider',coalesce(p_data->>'provider','mercado_pago'),'environment',p_data->>'environment','externalId',p_data->>'externalId'));
 return jsonb_build_object('ok',true,'id',r.id);
end $$;
revoke all on function private.finance_receiver_server(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.finance_receiver_server(uuid,uuid,uuid,text,jsonb) to service_role;
create function public.finance_receiver_server(p_actor uuid,p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_receiver_server(p_actor,p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_receiver_server(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.finance_receiver_server(uuid,uuid,uuid,text,jsonb) to service_role;
