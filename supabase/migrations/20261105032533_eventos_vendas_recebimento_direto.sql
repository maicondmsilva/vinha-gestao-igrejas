set local lock_timeout='5s';
alter table private.church_app_events add column commerce_mode text not null default 'event' check(commerce_mode in('event','sale')),add column pickup_at timestamptz;
-- Validate the final row at commit so atomic date edits may update the schedule and pickup together.
create function private.commerce_dates_guard() returns trigger language plpgsql security definer set search_path='' as $
begin
 if exists(select 1 from private.church_app_events e where e.id=new.id and e.commerce_mode='sale' and (e.pickup_at is null or e.pickup_at<e.starts_at or e.pickup_at>e.ends_at)) then raise exception 'invalid_commerce_dates' using errcode='23514';end if;
 return null;
end $;
revoke all on function private.commerce_dates_guard() from public,anon,authenticated,service_role;
create constraint trigger commerce_pickup_dates after insert or update on private.church_app_events deferrable initially deferred for each row execute function private.commerce_dates_guard();
create index commerce_events_scope on private.church_app_events(organization_id,unit_id,commerce_mode,starts_at);
alter table private.event_ticket_types add column product_name text not null default '' check(length(product_name)<=100),add column product_size text not null default '' check(length(product_size)<=40),add column product_color text not null default '' check(length(product_color)<=60);
create unique index commerce_variant_unique on private.event_ticket_types(event_id,lower(product_name),lower(product_size),lower(product_color)) where product_name<>'';

create function private.commerce_receivers(p_org uuid,p_unit uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.event_manager(p_org,p_unit) then raise exception 'event_ticket_denied' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.holder,'provider',r.provider,'unit',r.unit_id,'unit_name',u.name,'primary',r.is_primary,'methods',to_jsonb(r.methods),'canConfigure',private.receiver_actor_allowed(auth.uid(),p_org,r.unit_id)) order by r.is_primary desc,u.name,r.provider)
 from private.finance_receivers r join public.organization_units u on u.id=r.unit_id and u.organization_id=r.organization_id
 where r.organization_id=p_org and r.environment='production' and r.provider='mercado_pago' and r.status='configured' and r.payments_enabled and r.webhook_configured and r.holder_confirmed and r.expires_at>clock_timestamp() and cardinality(r.methods)>0 and r.methods<@array['pix','card','boleto']::text[] and p_unit=any(r.beneficiary_units)
 and private.receiver_actor_allowed(r.created_by,p_org,r.unit_id) and private.can_access_unit(p_org,r.unit_id,array['manage','admin']::public.unit_access_level[])
 and exists(select 1 from private.finance_catalog a where a.id=r.account_id and a.organization_id=p_org and a.unit_id=r.unit_id and a.kind='account' and a.active)),'[]');
end $$;
revoke all on function private.commerce_receivers(uuid,uuid) from public,anon,service_role;
grant execute on function private.commerce_receivers(uuid,uuid) to authenticated;
create function public.commerce_receivers(p_org uuid,p_unit uuid) returns jsonb language sql security invoker set search_path='' as $$select private.commerce_receivers(p_org,p_unit)$$;
revoke all on function public.commerce_receivers(uuid,uuid) from public,anon,service_role;
grant execute on function public.commerce_receivers(uuid,uuid) to authenticated;

-- Deterministic defaults belong to this receiver and financial unit; never repoint a previous purpose.
create function private.commerce_receiving_purpose(p_org uuid,p_event_unit uuid,p_receiver uuid,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare r private.finance_receivers;p uuid;cat uuid;fee uuid;refund uuid;item uuid;n text;direction text;k integer;
begin
 perform private.community_identity(p_org,p_event_unit,false);
 perform 1 from public.organizations where id=p_org for no key update;
 if p_mode not in('event','sale') or not private.event_manager(p_org,p_event_unit) then raise exception 'event_ticket_denied' using errcode='42501';end if;
 select * into r from private.finance_receivers where id=p_receiver and organization_id=p_org for share;
 if r.id is null or not private.receiver_actor_allowed(auth.uid(),p_org,r.unit_id) or not exists(select 1 from jsonb_array_elements(private.commerce_receivers(p_org,p_event_unit))v where v->>'id'=r.id::text) then raise exception 'event_receiver_unavailable' using errcode='42501';end if;
 p:=md5('vinha-commerce-purpose:'||p_org||':'||r.unit_id||':'||r.id||':'||p_mode)::uuid;
 if exists(select 1 from private.finance_purposes where id=p) then
  if not exists(select 1 from private.finance_purposes where id=p and organization_id=p_org and unit_id=r.unit_id and account_id=r.account_id and origin='event' and active) or private.member_payment_receiver(p_org,r.unit_id,p) is distinct from r.id then raise exception 'event_default_changed' using errcode='40001';end if;
  return p;
 end if;
 for k in 1..3 loop
  n:=case k when 1 then case p_mode when 'sale' then 'Vinha · Vendas e encomendas' else 'Vinha · Eventos' end when 2 then 'Vinha · Taxas de recebimentos digitais' else 'Vinha · Devoluções de recebimentos digitais' end;
  direction:=case k when 1 then 'income' else 'expense' end;
  item:=md5('vinha-commerce-category:'||p_org||':'||r.unit_id||':'||n)::uuid;
  if not exists(select 1 from private.finance_catalog where id=item) then
   perform private.finance_f1(p_org,array[r.unit_id],'catalog',jsonb_build_object('id',item,'kind','category','name',n,'direction',direction));
  end if;
  if not private.digital_catalog(p_org,r.unit_id,item,'category',direction) then raise exception 'event_default_changed' using errcode='40001';end if;
  if k=1 then cat:=item;elsif k=2 then fee:=item;else refund:=item;end if;
 end loop;
 perform private.finance_digital(p_org,r.unit_id,'purpose',jsonb_build_object('id',p,'version',0,'name',case p_mode when 'sale' then 'Vendas e encomendas' else 'Eventos' end||' · '||left(r.id::text,8),'origin','event','account',r.account_id,'category',cat,'feeCategory',fee,'refundCategory',refund,'creditCategory',cat,'active',true));
 perform private.member_payment_publish(p_org,r.unit_id,p,r.id,true);
 return p;
end $$;
revoke all on function private.commerce_receiving_purpose(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

create function private.commerce_event_save(p_event uuid,d jsonb) returns void language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;s private.event_ticket_settings;pickup timestamptz;receiver uuid;
begin
 select * into e from private.church_app_events where id=p_event for update;
 if e.id is null or not private.event_manager(e.organization_id,e.unit_id) or jsonb_typeof(d) is distinct from 'object' or d-array['mode','pickupLocal','receiver','methods']<>'{}' or not(d ?& array['mode','pickupLocal','receiver','methods']) or jsonb_typeof(d->'mode') is distinct from 'string' or d->>'mode' not in('event','sale') or jsonb_typeof(d->'pickupLocal') is distinct from 'string' or jsonb_typeof(d->'receiver') is distinct from 'string' or jsonb_typeof(d->'methods') is distinct from 'array' then raise exception 'invalid_commerce' using errcode='22023';end if;
 if e.commerce_mode<>d->>'mode' and (exists(select 1 from private.event_ticket_types where event_id=e.id) or exists(select 1 from private.church_app_registrations where event_id=e.id)) then raise exception 'commerce_mode_locked' using errcode='40001';end if;
 if d->>'mode'='sale' then
  pickup:=(d->>'pickupLocal')::timestamp at time zone 'America/Sao_Paulo';
  if pickup is null or pickup<e.starts_at or pickup>e.ends_at or e.series_id is not null then raise exception 'invalid_commerce_dates' using errcode='22023';end if;
 end if;
 update private.church_app_events set commerce_mode=d->>'mode',pickup_at=pickup where id=e.id;
 receiver:=nullif(d->>'receiver','')::uuid;
 select * into s from private.event_ticket_settings where event_id=e.id;
 if receiver is not null or s.event_id is not null then
  perform private.event_ticket_admin(e.organization_id,e.unit_id,e.id,'settings',null,e.version,jsonb_build_object('enabled',coalesce(s.enabled,false),'allow_guests',coalesce(s.allow_guests,false),'show_remaining',coalesce(s.show_remaining,true),'purpose','','receiving_unit',e.unit_id,'reservation_hours',coalesce(s.reservation_hours,24),'questions',coalesce(s.questions,'[]'),'receiver',receiver,'payment_methods',d->'methods'));
 end if;
end $$;
revoke all on function private.commerce_event_save(uuid,jsonb) from public,anon,authenticated,service_role;

do $patch$
declare d text;needle text;
begin
 select pg_get_functiondef('private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 -- No wrapper bypass: keep the same authorization, row locks and version check for every command.
 d:=replace(d,$sql$if p_action='settings' then$sql$,$sql$if p_action='settings' then
  if p_data ? 'receiver' then
   if nullif(p_data->>'receiver','') is null then p_data:=p_data-'receiver';
   else
    uid:=private.commerce_receiving_purpose(p_org,p_unit,(p_data->>'receiver')::uuid,e.commerce_mode);
    p_data:=(p_data-'receiver')||jsonb_build_object('purpose',uid,'receiving_unit',(select unit_id from private.finance_purposes where id=uid));
   end if;
  end if;
$sql$);
 d:=replace(d,'''event'',to_jsonb(e),''settings''','''receivers'',private.commerce_receivers(p_org,p_unit),''event'',to_jsonb(e),''settings''');
 d:=replace(d,$sql$'ready',private.member_payment_receiver(p_org,p.unit_id,p.id) is not null$sql$,$sql$'receiver',private.member_payment_receiver(p_org,p.unit_id,p.id),'ready',private.member_payment_receiver(p_org,p.unit_id,p.id) is not null$sql$);
 needle:=' elsif p_action=''type'' then';if position(needle in d)=0 then raise exception 'ticket type anchor';end if;
 d:=replace(d,needle,needle||$sql$
  if p_data ? 'product' then
   if e.commerce_mode<>'sale' or jsonb_typeof(p_data->'product') is distinct from 'object' or (p_data->'product')-array['name','size','color']<>'{}' or not((p_data->'product') ?& array['name','size','color']) or jsonb_typeof(p_data->'product'->'name') is distinct from 'string' or length(btrim(p_data->'product'->>'name')) not between 2 and 100 or jsonb_typeof(p_data->'product'->'size') is distinct from 'string' or jsonb_typeof(p_data->'product'->'color') is distinct from 'string' or length(p_data->'product'->>'size')>40 or length(p_data->'product'->>'color')>60 then raise exception 'invalid_product' using errcode='22023';end if;
   if nullif(p_data->>'quantity','') is null or (p_data->>'ends')::timestamptz>e.starts_at or p_data->>'name' is distinct from concat_ws(' · ',btrim(p_data->'product'->>'name'),nullif(btrim(p_data->'product'->>'size'),''),nullif(btrim(p_data->'product'->>'color'),'')) then raise exception 'invalid_product' using errcode='22023';end if;
  elsif e.commerce_mode='sale' then raise exception 'invalid_product' using errcode='22023';end if;
$sql$);
 d:=replace(d,$sql$p_data-array['name','mode','price','quantity','starts','ends','active','per_user','per_cpf','audience','audience_units','position']$sql$,$sql$p_data-array['name','mode','price','quantity','starts','ends','active','per_user','per_cpf','audience','audience_units','position','product']$sql$);
 needle:=' elsif p_action=''coupon'' then';
 d:=replace(d,needle,$sql$  if e.commerce_mode='sale' then update private.event_ticket_types set product_name=btrim(p_data->'product'->>'name'),product_size=btrim(p_data->'product'->>'size'),product_color=btrim(p_data->'product'->>'color') where id=p_id and event_id=e.id;end if;
$sql$||needle);
 d:=replace(d,$sql$if e.status<>'published' or clock_timestamp()<e.starts_at-interval '2 hours' or clock_timestamp()>e.ends_at+interval '6 hours' then$sql$,$sql$if e.status<>'published' or (e.commerce_mode='sale' and (clock_timestamp()<e.pickup_at or clock_timestamp()>e.ends_at)) or (e.commerce_mode='event' and (clock_timestamp()<e.starts_at-interval '2 hours' or clock_timestamp()>e.ends_at+interval '6 hours')) then$sql$);
 execute d;

 select pg_get_functiondef('private.programming_admin_base_20261103(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,$sql$section_name not in('todos','proximos','encerrados')$sql$,$sql$section_name not in('todos','proximos','encerrados','vendas')$sql$);
 d:=replace(d,$sql$and (section_name='todos' or$sql$,$sql$and ((section_name='vendas' and evt.commerce_mode='sale') or (section_name<>'vendas' and evt.commerce_mode='event'))
    and (section_name in('todos','vendas') or$sql$);
 execute d;

 select pg_get_functiondef('private.programming_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,$sql$perform private.community_identity(p_org,p_unit,false);$sql$,$sql$perform private.community_identity(p_org,p_unit,false);
 if p_data ? 'commerce' and (p_action not in('create','edit') or not(p_data ? 'information')) then raise exception 'invalid_commerce' using errcode='22023';end if;$sql$);
 d:=replace(d,$sql$(p_data-'information')$sql$,$sql$(p_data-'information'-'commerce')$sql$);
 d:=replace(d,$sql$perform private.save_event_information(p_org,p_unit,i,profile);$sql$,$sql$perform private.save_event_information(p_org,p_unit,i,profile);
    if p_data ? 'commerce' then perform private.commerce_event_save(i,p_data->'commerce');end if;$sql$);
 execute d;

 -- Public data carries the nature and pickup schedule; the checkout proof is unchanged.
 select pg_get_functiondef('member_app_api.event_page(uuid)'::regprocedure) into d;
 d:=replace(d,$sql$'id',e.id,'title',e.title$sql$,$sql$'commerce_mode',e.commerce_mode,'pickup_at',e.pickup_at,'id',e.id,'title',e.title$sql$);execute d;
 select pg_get_functiondef('private.event_information_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,$sql::regprocedure) into d;
 d:=replace(d,$sql$'enabled',true,'event',e.id$sql$,$sql$'commerceMode',e.commerce_mode,'pickupAt',e.pickup_at,'pickupUntil',e.ends_at,'pickupLocation',e.location,'enabled',true,'event',e.id$sql$);execute d;
 select pg_get_functiondef('private.event_ticket_order_view(private.event_ticket_orders)'::regprocedure) into d;
 d:=replace(d,$sql$'ok',true,'id',o.id$sql$,$sql$'commerceMode',(select commerce_mode from private.church_app_events where id=o.event_id),'ok',true,'id',o.id$sql$);execute d;
end $patch$;
notify pgrst,'reload schema';
id',e.id,'title',e.title$sql$,$sql::regprocedure) into d;
 d:=replace(d,$sql$'enabled',true,'event',e.id$sql$,$sql$'commerceMode',e.commerce_mode,'pickupAt',e.pickup_at,'pickupUntil',e.ends_at,'pickupLocation',e.location,'enabled',true,'event',e.id$sql$);execute d;
 select pg_get_functiondef('private.event_ticket_order_view(private.event_ticket_orders)'::regprocedure) into d;
 d:=replace(d,$sql$'ok',true,'id',o.id$sql$,$sql$'commerceMode',(select commerce_mode from private.church_app_events where id=o.event_id),'ok',true,'id',o.id$sql$);execute d;
end $patch$;
notify pgrst,'reload schema';
commerce_mode',e.commerce_mode,'pickup_at',e.pickup_at,'id',e.id,'title',e.title$sql$);execute d;
 select pg_get_functiondef('member_app_api.event_ticket_catalog(uuid)'::regprocedure) into d;
 d:=replace(d,$sql$'enabled',true,'event',e.id$sql$,$sql$'commerceMode',e.commerce_mode,'pickupAt',e.pickup_at,'pickupUntil',e.ends_at,'pickupLocation',e.location,'enabled',true,'event',e.id$sql$);execute d;
 select pg_get_functiondef('private.event_ticket_order_view(private.event_ticket_orders)'::regprocedure) into d;
 d:=replace(d,$sql$'ok',true,'id',o.id$sql$,$sql$'commerceMode',(select commerce_mode from private.church_app_events where id=o.event_id),'ok',true,'id',o.id$sql$);execute d;
end $patch$;
notify pgrst,'reload schema';
