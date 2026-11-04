-- One explicit default per church/environment. Existing payment destinations remain immutable.
set local lock_timeout='5s';
alter table private.finance_receivers add column is_primary boolean not null default false;
create unique index finance_receiver_one_primary on private.finance_receivers(organization_id,unit_id,environment) where is_primary;
alter table private.event_ticket_settings add column payment_methods text[];
alter table private.event_ticket_settings add constraint event_methods_allowed check(payment_methods is null or (cardinality(payment_methods) between 1 and 3 and payment_methods <@ array['pix','card','boleto']::text[]));
alter table private.event_ticket_orders add column payment_methods text[];

create function private.receiver_primary_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status<>'configured' or not new.payments_enabled or not new.holder_confirmed or not new.webhook_configured or new.expires_at is null or new.expires_at<=clock_timestamp() then new.is_primary:=false;end if;
 return new;
end $$;
revoke all on function private.receiver_primary_guard() from public,anon,authenticated,service_role;
create trigger zz_receiver_primary_guard before update on private.finance_receivers for each row execute function private.receiver_primary_guard();

-- Change only the relevant branches; retain the audited authorization/locking path.
do $migration$
declare d text;old text;
begin
 select pg_get_functiondef('private.finance_receiver_settings(uuid,uuid,text,jsonb)'::regprocedure) into d;
 old:='elsif p_action=''configure'' then';
 if position(old in d)=0 then raise exception 'receiver migration anchor missing';end if;
 d:=replace(d,old,$branch$elsif p_action='primary' then
  if p_data-array['provider','environment','version','primary']<>'{}' or jsonb_typeof(p_data->'primary') is distinct from 'boolean' then raise exception 'invalid_receiver' using errcode='22023';end if;
  if (p_data->>'primary')::boolean then
   if r.status<>'configured' or not r.payments_enabled or not r.holder_confirmed or not r.webhook_configured or r.expires_at<=clock_timestamp() or r.expires_at is null or cardinality(r.methods)=0 or not private.receiver_actor_allowed(r.created_by,p_org,r.unit_id) or not exists(select 1 from private.finance_catalog where id=r.account_id and organization_id=p_org and unit_id=p_unit and kind='account' and active) then raise exception 'receiver_not_ready' using errcode='22023';end if;
   with previous as (update private.finance_receivers set is_primary=false,version=version+1,updated_at=now() where organization_id=p_org and unit_id=p_unit and environment=r.environment and is_primary and id<>r.id returning id)
   insert into private.finance_receiver_events(receiver_id,actor,action,details) select id,auth.uid(),'primary_replaced',jsonb_build_object('replacement',r.id) from previous;
  end if;
  update private.finance_receivers set is_primary=(p_data->>'primary')::boolean,version=version+1,updated_at=now() where id=r.id;
 elsif p_action='configure' then$branch$);
 execute d;

 select pg_get_functiondef('private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 old:='''ready'',private.member_payment_receiver(p_org,p.unit_id,p.id) is not null';
 if position(old in d)=0 then raise exception 'event read anchor missing';end if;
 d:=replace(d,old,old||$branch$,'methods',coalesce((select to_jsonb(r.methods) from private.finance_receivers r where r.id=private.member_payment_receiver(p_org,p.unit_id,p.id)),'[]'::jsonb),'primary',coalesce((select r.is_primary from private.finance_receivers r where r.id=private.member_payment_receiver(p_org,p.unit_id,p.id)),false),'receiver_name',(select r.holder from private.finance_receivers r where r.id=private.member_payment_receiver(p_org,p.unit_id,p.id))$branch$);
 d:=replace(d,$anchor$p_data-array['enabled','allow_guests','show_remaining','purpose','receiving_unit','reservation_hours','questions']$anchor$,$anchor$p_data-array['enabled','allow_guests','show_remaining','purpose','receiving_unit','reservation_hours','questions','payment_methods']$anchor$);
 old:='  uid:=(p_data->>''receiving_unit'')::uuid;';
 if position(old in d)=0 then raise exception 'event settings anchor missing';end if;
 d:=replace(d,old,old||$branch$
  if p_data ? 'payment_methods' and (jsonb_typeof(p_data->'payment_methods') is distinct from 'array' or jsonb_array_length(p_data->'payment_methods') not between 1 and 3 or exists(select 1 from jsonb_array_elements(p_data->'payment_methods')v where jsonb_typeof(v)<>'string' or v#>>'{}' not in('pix','card','boleto')) or (select count(distinct v) from jsonb_array_elements(p_data->'payment_methods')v)<>jsonb_array_length(p_data->'payment_methods')) then raise exception 'invalid_event_methods' using errcode='22023';end if;
  if p_data ? 'payment_methods' and (nullif(p_data->>'purpose','') is null or not exists(select 1 from private.finance_receivers r where r.id=private.member_payment_receiver(p_org,uid,(p_data->>'purpose')::uuid) and array(select jsonb_array_elements_text(p_data->'payment_methods')) <@ r.methods)) then raise exception 'event_methods_unavailable' using errcode='22023';end if;
$branch$);
 old:=' elsif p_action=''type'' then';
 if position(old in d)=0 then raise exception 'event save anchor missing';end if;
 d:=replace(d,old,$branch$  update private.event_ticket_settings set payment_methods=case when p_data ? 'payment_methods' then array(select jsonb_array_elements_text(p_data->'payment_methods')) else null end where event_id=e.id;
 elsif p_action='type' then$branch$);
 execute d;

 select pg_get_functiondef('private.event_ticket_delivery(uuid,text,jsonb)'::regprocedure) into d;
 old:='''gross'',o.total::text';
 if position(old in d)=0 then raise exception 'event delivery anchor missing';end if;
 d:=replace(d,old,'''methods'',to_jsonb(o.payment_methods),'||old);execute d;
end $migration$;

-- Capture the allowed methods once. Later edits cannot broaden a saved order.
create function private.event_order_methods_snapshot() returns trigger language plpgsql security definer set search_path='' as $$
declare selected text[];available text[];
begin
 if new.total>0 then
  select payment_methods into selected from private.event_ticket_settings where event_id=new.event_id;
  select methods into available from private.finance_receivers where id=new.receiver_id and organization_id=new.organization_id;
  if available is null or cardinality(available)=0 or selected is not null and not selected <@ available then raise exception 'event_methods_unavailable' using errcode='42501';end if;
  new.payment_methods:=coalesce(selected,available);
 end if;
 return new;
end $$;
revoke all on function private.event_order_methods_snapshot() from public,anon,authenticated,service_role;
create trigger event_order_methods_snapshot before insert on private.event_ticket_orders for each row execute function private.event_order_methods_snapshot();
