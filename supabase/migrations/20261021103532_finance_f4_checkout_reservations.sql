-- Durable delivery: no automatic second external POST after a timeout or process crash.
set local lock_timeout='5s';
create table private.finance_checkout_attempts(
 id uuid primary key default extensions.gen_random_uuid(),
 order_id uuid not null unique references private.finance_digital_orders(id),
 actor_id uuid not null references auth.users(id),
 payer_name text not null check(length(btrim(payer_name)) between 2 and 160),
 payer_email text not null check(length(payer_email) between 3 and 254),
 state text not null default 'reserved' check(state in('reserved','dispatching','ready','uncertain')),
 preference_id text,checkout_url text,created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '1 hour',
 check((state='ready')=(preference_id is not null and checkout_url is not null))
);
create index finance_checkout_attempts_actor on private.finance_checkout_attempts(actor_id);
alter table private.finance_checkout_attempts enable row level security;
create policy finance_checkout_attempts_deny on private.finance_checkout_attempts as restrictive for all using(false) with check(false);
revoke all on private.finance_checkout_attempts from public,anon,authenticated,service_role;

create function private.finance_checkout_reserve(p_org uuid,p_unit uuid,p_order uuid,p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.finance_digital_orders;r private.finance_receivers;a private.finance_checkout_attempts;mail text;
begin
 -- Uses the same unit/module locks and confirmation checks as the financial panel.
 perform private.finance_digital(p_org,p_unit,'list','{}');
 if not private.receiver_actor_allowed(auth.uid(),p_org,p_unit) then raise exception 'checkout_manager_required' using errcode='42501';end if;
 if length(btrim(p_name)) not between 2 and 160 then raise exception 'invalid_payer' using errcode='22023';end if;
 select email into mail from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if mail is null or length(mail)>254 then raise exception 'confirmed_email_required' using errcode='42501';end if;
 select * into o from private.finance_digital_orders where id=p_order and organization_id=p_org and unit_id=p_unit;
 if not found then raise exception 'order_denied' using errcode='42501';end if;
 select * into r from private.finance_receivers where id=o.receiver_id for share;
 if r.provider<>'mercado_pago' or r.environment<>o.environment or r.status<>'configured' or not r.holder_confirmed or r.expires_at is null or r.expires_at<=clock_timestamp() or not p_unit=any(r.beneficiary_units) or not private.receiver_actor_allowed(r.created_by,p_org,r.unit_id) or r.account_id is distinct from (o.classification->>'account_id')::uuid then raise exception 'receiver_unavailable' using errcode='42501';end if;
 if exists(select 1 from private.finance_digital_receipts where order_id=o.id) then raise exception 'payment_already_observed' using errcode='40001';end if;
 select * into a from private.finance_checkout_attempts where order_id=o.id for update;
 if not found then
  insert into private.finance_checkout_attempts(order_id,actor_id,payer_name,payer_email) values(o.id,auth.uid(),btrim(p_name),mail) returning * into a;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'digital.checkout_reserved','finance_checkout',a.id::text,jsonb_build_object('unit',p_unit,'order',o.id));
 elsif a.actor_id<>auth.uid() or a.payer_email<>mail or a.payer_name<>btrim(p_name) then raise exception 'checkout_identity_conflict' using errcode='40001';end if;
 return jsonb_build_object('id',a.id,'receiver',r.id,'state',a.state,'environment',o.environment,'expired',a.expires_at<=clock_timestamp());
end $$;
revoke all on function private.finance_checkout_reserve(uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function private.finance_checkout_reserve(uuid,uuid,uuid,text) to authenticated;
create function public.finance_checkout_reserve(p_org uuid,p_unit uuid,p_order uuid,p_name text) returns jsonb language sql security invoker set search_path='' as $$select private.finance_checkout_reserve(p_org,p_unit,p_order,p_name)$$;
revoke all on function public.finance_checkout_reserve(uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function public.finance_checkout_reserve(uuid,uuid,uuid,text) to authenticated;

create function private.finance_checkout_delivery(p_org uuid,p_unit uuid,p_id uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.finance_checkout_attempts;o private.finance_digital_orders;r private.finance_receivers;claimed boolean:=false;
begin
 select ord.* into o from private.finance_digital_orders ord join private.finance_checkout_attempts ca on ca.order_id=ord.id where ca.id=p_id and ord.organization_id=p_org and ord.unit_id=p_unit;
 if not found then raise exception 'checkout_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for no key update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 select * into r from private.finance_receivers where id=o.receiver_id for share;
 select * into a from private.finance_checkout_attempts where id=p_id for update;
 if p_action='claim' then
  if r.environment<>o.environment or not private.receiver_actor_allowed(a.actor_id,p_org,p_unit) or not private.receiver_actor_allowed(r.created_by,p_org,r.unit_id) or not exists(select 1 from auth.users where id=a.actor_id and email=a.payer_email and email_confirmed_at is not null) or r.status<>'configured' or not r.holder_confirmed or r.expires_at is null or r.expires_at<=clock_timestamp() or not p_unit=any(r.beneficiary_units) or r.account_id is distinct from (o.classification->>'account_id')::uuid or exists(select 1 from private.finance_digital_receipts where order_id=o.id) then raise exception 'checkout_denied' using errcode='42501';end if;
  if a.expires_at<=clock_timestamp() then raise exception 'checkout_expired' using errcode='40001';end if;
  if a.state='reserved' then update private.finance_checkout_attempts set state='dispatching' where id=a.id;claimed:=true;end if;
  return jsonb_build_object('id',a.id,'order',o.id,'receiver',r.id,'gross',o.gross::text,'title',o.classification->>'name','name',a.payer_name,'email',a.payer_email,'expiresAt',a.expires_at,'state',case when claimed then 'dispatching' when a.state='dispatching' then 'in_progress' else a.state end,'checkoutUrl',case when a.state='ready' then a.checkout_url else null end);
 elsif p_action='complete' then
  if a.state<>'dispatching' or jsonb_typeof(p_data) is distinct from 'object' or (p_data - array['preference','url'])<>'{}'::jsonb or coalesce(p_data->>'preference','')!~'^[A-Za-z0-9_-]{1,200}$' or coalesce(p_data->>'url','')!~'^https://(www\.)?mercadopago\.com\.br/checkout/v1/redirect\?pref_id=[A-Za-z0-9_-]+$' or split_part(p_data->>'url','pref_id=',2)<>p_data->>'preference' then raise exception 'checkout_proof_invalid' using errcode='22023';end if;
  update private.finance_checkout_attempts set state='ready',preference_id=p_data->>'preference',checkout_url=p_data->>'url' where id=a.id;
 elsif p_action='uncertain' then
  if a.state='dispatching' then update private.finance_checkout_attempts set state='uncertain' where id=a.id;end if;
 else raise exception 'invalid_checkout_action' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,a.actor_id,'digital.checkout_'||p_action,'finance_checkout',a.id::text,jsonb_build_object('unit',p_unit,'order',o.id));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.finance_checkout_delivery(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.finance_checkout_delivery(uuid,uuid,uuid,text,jsonb) to service_role;
create function public.finance_checkout_delivery(p_org uuid,p_unit uuid,p_id uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.finance_checkout_delivery(p_org,p_unit,p_id,p_action,p_data)$$;
revoke all on function public.finance_checkout_delivery(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.finance_checkout_delivery(uuid,uuid,uuid,text,jsonb) to service_role;
