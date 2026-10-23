begin;
set local lock_timeout='5s';
alter table private.finance_receivers add column payments_enabled boolean not null default false,
 add column webhook_configured boolean not null default false;

create function private.finance_receiver_key_check(p_actor uuid,p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.finance_receivers;v integer;
begin
 if not private.receiver_actor_allowed(p_actor,p_org,p_unit) then raise exception 'receiver_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform 1 from auth.users where id=p_actor for share;
 if not private.receiver_actor_allowed(p_actor,p_org,p_unit) then raise exception 'receiver_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 or p_data->>'environment' is null or p_data->>'environment' not in('sandbox','production') or p_data->>'provider' is distinct from 'mercado_pago' or jsonb_typeof(p_data->'version') is distinct from 'number' then raise exception 'invalid_key_validation' using errcode='22023';end if;
 v:=(p_data->>'version')::integer;
 select * into r from private.finance_receivers where organization_id=p_org and unit_id=p_unit and provider='mercado_pago' and environment=p_data->>'environment' for update;
 if r.status='blocked' or r.status='revoked' and p_action<>'complete' then raise exception 'receiver_blocked' using errcode='42501';end if;
 if coalesce(r.version,0) is distinct from v then raise exception 'receiver_changed' using errcode='40001';end if;
 if p_action='inspect' then
  if r.id is null then raise exception 'receiver_missing' using errcode='22023';end if;
  return jsonb_build_object('sealed',(select sealed from private.finance_receiver_secrets where receiver_id=r.id),'version',r.version,'status',r.status,'externalId',r.external_id);
 elsif p_action in('complete','renew') then
  if jsonb_typeof(p_data->'externalId') is distinct from 'string' or p_data->>'externalId'!~'^[0-9]{1,30}$' or jsonb_typeof(p_data->'holder') is distinct from 'string' or length(btrim(p_data->>'holder')) not between 1 and 160 or jsonb_typeof(p_data->'sealed') is distinct from 'string' or length(p_data->>'sealed') not between 32 and 16384 or jsonb_typeof(p_data->'webhookConfigured') is distinct from 'boolean' or (p_data->>'expiresAt')::timestamptz is null or (p_data->>'expiresAt')::timestamptz<=now() or (p_data->>'expiresAt')::timestamptz>now()+interval '31 days' then raise exception 'invalid_key_proof' using errcode='22023';end if;
  if p_action='renew' then
   if r.id is null or r.status not in('connected','configured') or r.external_id is distinct from p_data->>'externalId' or r.webhook_configured is distinct from (p_data->>'webhookConfigured')::boolean then raise exception 'receiver_identity_changed' using errcode='40001';end if;
   update private.finance_receivers set holder=p_data->>'holder',expires_at=(p_data->>'expiresAt')::timestamptz,version=version+1,updated_at=now() where id=r.id;
  else
  if r.id is null then insert into private.finance_receivers(organization_id,unit_id,provider,environment,status,created_by) values(p_org,p_unit,'mercado_pago',p_data->>'environment','connected',p_actor) returning * into r;end if;
  update private.finance_receivers set status='connected',external_id=p_data->>'externalId',holder=p_data->>'holder',provider_status='manual_identity_checked_30d',expires_at=(p_data->>'expiresAt')::timestamptz,holder_confirmed=false,methods='{}',beneficiary_units='{}',account_id=null,payments_enabled=false,webhook_configured=(p_data->>'webhookConfigured')::boolean,version=version+1,updated_at=now() where id=r.id;
  end if;
  insert into private.finance_receiver_secrets values(r.id,p_data->>'sealed',now()) on conflict(receiver_id) do update set sealed=excluded.sealed,updated_at=excluded.updated_at;
 elsif p_action='activate' then
  if r.id is null or r.status<>'configured' or not r.holder_confirmed or not r.webhook_configured or r.account_id is null or r.expires_at is null or r.expires_at<=now() or p_data->'confirmed' is distinct from 'true'::jsonb or cardinality(r.methods)=0 or not r.methods<@array['pix','boleto','card']::text[] then raise exception 'receiver_not_ready' using errcode='22023';end if;
  if not exists(select 1 from private.finance_catalog where id=r.account_id and active and organization_id=p_org and unit_id=p_unit and kind='account') then raise exception 'account_unavailable' using errcode='22023';end if;
  if not private.receiver_actor_allowed(r.created_by,p_org,p_unit) then raise exception 'creator_unavailable' using errcode='42501';end if;
  update private.finance_receivers set payments_enabled=true,version=version+1,updated_at=now() where id=r.id;
 else raise exception 'invalid_key_action' using errcode='22023';end if;
 insert into private.finance_receiver_events(receiver_id,actor,action,details) values(r.id,p_actor,'key_'||p_action,jsonb_build_object('provider','mercado_pago','environment',r.environment));
 return jsonb_build_object('ok',true,'id',r.id);
end $$;
revoke all on function private.finance_receiver_key_check(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.finance_receiver_key_check(uuid,uuid,uuid,text,jsonb) to service_role;
create function public.finance_receiver_key_check(p_actor uuid,p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_receiver_key_check(p_actor,p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_receiver_key_check(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.finance_receiver_key_check(uuid,uuid,uuid,text,jsonb) to service_role;

create function private.reset_receiver_activation() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status<>'configured' or not new.holder_confirmed or new.account_id is distinct from old.account_id or new.external_id is distinct from old.external_id or new.methods is distinct from old.methods or new.beneficiary_units is distinct from old.beneficiary_units then new.payments_enabled:=false;end if;
 return new;
end $$;
revoke all on function private.reset_receiver_activation() from public,anon,authenticated,service_role;
create trigger reset_receiver_activation before update on private.finance_receivers for each row execute function private.reset_receiver_activation();

do $patch$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.finance_digital_connection(uuid)'::regprocedure);
 needle:='''beneficiaries'',c.beneficiary_units,''sealed''';
 if strpos(definition,needle)=0 then raise exception 'unexpected_digital_connection';end if;
 definition:=replace(definition,needle,'''beneficiaries'',c.beneficiary_units,''methods'',c.methods,''paymentsEnabled'',c.payments_enabled,''webhookConfigured'',c.webhook_configured,''sealed''');
 execute definition;
end $patch$;
commit;
