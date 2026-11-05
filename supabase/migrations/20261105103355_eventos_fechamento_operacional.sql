set local lock_timeout='5s';
alter table private.event_ticket_items add column version integer not null default 1;
alter table private.event_messages add column image_url text not null default '',add column redirect_url text not null default '';
create table private.event_staff_orders(order_id uuid primary key references private.event_ticket_orders(id),actor_id uuid not null references auth.users(id),proof text not null,request_data jsonb not null,receipt_token uuid not null default extensions.gen_random_uuid() unique,created_at timestamptz not null default now());
create index event_staff_orders_actor on private.event_staff_orders(actor_id);
create table private.event_receipt_links(order_id uuid primary key references private.event_ticket_orders(id),token uuid not null default extensions.gen_random_uuid() unique,created_at timestamptz not null default now());
create table private.event_receipt_deliveries(id uuid primary key,order_id uuid not null references private.event_ticket_orders(id),actor_id uuid not null references auth.users(id),state text not null default 'queued' check(state in('queued','sending','sent','uncertain','cancelled')),claim_token uuid,provider_id text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index event_receipt_deliveries_order on private.event_receipt_deliveries(order_id,created_at);
create index event_receipt_deliveries_actor on private.event_receipt_deliveries(actor_id);
create index event_receipt_deliveries_work on private.event_receipt_deliveries(state,updated_at);
create table private.event_journeys(event_id uuid not null references private.church_app_events(id),program_id uuid not null references private.learning_programs(id),primary key(event_id,program_id));
create index event_journeys_program on private.event_journeys(program_id);
create table private.event_ratings(event_id uuid not null references private.church_app_events(id),user_id uuid not null references auth.users(id),stars integer not null check(stars between 1 and 5),comment text not null default '' check(length(comment)<=1500),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),primary key(event_id,user_id));
create index event_ratings_user on private.event_ratings(user_id);
alter table private.event_staff_orders enable row level security;
alter table private.event_receipt_links enable row level security;
alter table private.event_receipt_deliveries enable row level security;
alter table private.event_journeys enable row level security;
alter table private.event_ratings enable row level security;
revoke all on private.event_staff_orders,private.event_receipt_links,private.event_receipt_deliveries,private.event_journeys,private.event_ratings from public,anon,authenticated,service_role;

-- The staff command delegates inventory and financial decisions to the same checkout engine.
do $patch$
declare d text;needle text;
begin
 select pg_get_functiondef('private.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text)'::regprocedure) into d;
 d:=replace(d,'attempts integer;','attempts integer;staff boolean:=false;');
 needle:=' select * into s from private.event_ticket_settings where event_id=e.id;';
 if position(needle in d)=0 then raise exception 'staff checkout anchor missing';end if;
 d:=replace(d,needle,$sql$ staff:=p_data->>'_staff'='true' and auth.uid() is not null and private.event_manager(e.organization_id,e.unit_id);
 if p_data ? '_staff' and not coalesce(staff,false) then raise exception 'event_staff_denied' using errcode='42501';end if;
 p_data:=p_data-'_staff';
$sql$||needle);
 d:=replace(d,'if p_actor is null and not s.allow_guests then','if p_actor is null and not s.allow_guests and not coalesce(staff,false) then');
 -- Tickets have their own deadline. Events may accept orders while in progress; sales close at their order deadline.
 d:=replace(d,'or e.starts_at<=clock_timestamp() then raise exception ''event_ticket_closed'' using errcode=''40001'';end if;', 'or (case when e.commerce_mode=''sale'' then e.starts_at else e.ends_at end)<=clock_timestamp() then raise exception ''event_ticket_closed'' using errcode=''40001'';end if;');
 execute d;
 -- Add controlled edit versions to the existing staff listing without exposing tables.
 select pg_get_functiondef('private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,'select i.id,i.name,i.type_name ticket','select i.id,i.version,i.name,i.type_name ticket');
 execute d;
end $patch$;

create function private.event_staff_admin(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;o private.event_ticket_orders;i private.event_ticket_items;t private.event_ticket_types;s private.event_staff_orders;r jsonb;proof text;token uuid;recipient text;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.event_manager(p_org,p_unit) then raise exception 'event_staff_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for no key update;
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'event_staff_denied' using errcode='42501';end if;
 if p_action='read' then
  return jsonb_build_object('event',to_jsonb(e),'questions',coalesce((select questions from private.event_ticket_settings where event_id=e.id),'[]'),'types',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('used',private.event_ticket_used(e.id,x.id))) from private.event_ticket_types x where x.event_id=e.id and x.active and x.audience='public'),'[]'));
 elsif p_action='create' then
  if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['buyerName','buyerEmail','emailConfirmation','items','coupon','intent']<>'{}' then raise exception 'invalid_event_staff' using errcode='22023';end if;
  select * into s from private.event_staff_orders where order_id=p_id;
  if found and (s.actor_id<>auth.uid() or s.request_data<>p_data) then raise exception 'event_staff_changed' using errcode='40001';end if;
  proof:=coalesce(s.proof,encode(extensions.gen_random_bytes(32),'hex'));
  r:=private.event_ticket_checkout(e.id,'create',p_id,null,proof,p_data||'{"_staff":true}'::jsonb,encode(extensions.digest('staff:'||auth.uid()::text||current_date::text,'sha256'),'hex'));
  insert into private.event_staff_orders(order_id,actor_id,proof,request_data) values(p_id,auth.uid(),proof,p_data) on conflict(order_id) do nothing;
  insert into private.event_receipt_links(order_id) values(p_id) on conflict do nothing;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'event.staff.created','event_ticket_order',p_id::text,jsonb_build_object('event',e.id));
  return r||jsonb_build_object('receipt',(select l.token from private.event_receipt_links l where l.order_id=p_id));
 elsif p_action in('item','edit') then
  select * into i from private.event_ticket_items where id=p_id and event_id=e.id for update;
  select * into o from private.event_ticket_orders where id=i.order_id for update;
  if i.id is null then raise exception 'event_staff_denied' using errcode='42501';end if;
  if p_action='item' then return jsonb_build_object('item',to_jsonb(i),'questions',o.questions,'state',o.state);end if;
  if i.version is distinct from p_version or i.checked_in_at is not null or o.state not in('confirmed','reserved','holding') or o.state in('reserved','holding') and o.expires_at<=clock_timestamp() then raise exception 'event_staff_changed' using errcode='40001';end if;
  if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['name','email','cpf','phone','answers','reason']<>'{}' or not(p_data ?& array['name','email','cpf','phone','answers','reason']) or coalesce(length(btrim(p_data->>'name')),0) not between 2 and 160 or coalesce(length(btrim(p_data->>'reason')),0) not between 5 and 1000 or length(p_data->>'email')>254 or length(p_data->>'phone')>22 or coalesce(p_data->>'email','')<>'' and p_data->>'email'!~'^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$' or not private.event_ticket_answers_valid(p_data->'answers',o.questions) then raise exception 'invalid_event_staff' using errcode='22023';end if;
  select * into t from private.event_ticket_types where id=i.type_id;
  if coalesce(p_data->>'cpf','')<>'' and not private.event_cpf_valid(p_data->>'cpf') or t.per_cpf is not null and not private.event_cpf_valid(p_data->>'cpf') then raise exception 'invalid_event_staff' using errcode='22023';end if;
  if t.per_cpf is not null and (select count(*) from private.event_ticket_items x join private.event_ticket_orders z on z.id=x.order_id where x.id<>i.id and x.type_id=i.type_id and x.cpf=regexp_replace(p_data->>'cpf','[^0-9]','','g') and (z.state='confirmed' or z.state in('holding','reserved') and z.expires_at>clock_timestamp()))>=t.per_cpf then raise exception 'event_ticket_person_limit' using errcode='22023';end if;
  update private.event_ticket_items set name=btrim(p_data->>'name'),email=lower(btrim(p_data->>'email')),cpf=regexp_replace(p_data->>'cpf','[^0-9]','','g'),phone=p_data->>'phone',answers=p_data->'answers',version=version+1 where id=i.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'event.participant.updated','event_ticket_item',i.id::text,jsonb_build_object('event',e.id,'reason',p_data->>'reason','fromVersion',i.version));
 elsif p_action in('receipt','email') then
  select * into o from private.event_ticket_orders where id=p_id and event_id=e.id for update;
  if not found or o.state not in('confirmed','reserved','holding','payment_review') then raise exception 'event_staff_denied' using errcode='42501';end if;
  insert into private.event_receipt_links(order_id) values(o.id) on conflict do nothing;
  select l.token into token from private.event_receipt_links l where order_id=o.id;
  if p_action='receipt' then return jsonb_build_object('ok',true,'receipt',token);end if;
  if p_data-array['request']<>'{}' or p_data->>'request' is null then raise exception 'invalid_event_staff' using errcode='22023';end if;
  if exists(select 1 from private.event_receipt_deliveries where id=(p_data->>'request')::uuid and order_id<>o.id) then raise exception 'event_staff_changed' using errcode='40001';end if;
  if not exists(select 1 from private.event_receipt_deliveries where id=(p_data->>'request')::uuid) and (exists(select 1 from private.event_receipt_deliveries where order_id=o.id and created_at>clock_timestamp()-interval '1 minute') or (select count(*) from private.event_receipt_deliveries where order_id=o.id and created_at>clock_timestamp()-interval '1 day')>=5) then raise exception 'event_receipt_rate_limit' using errcode='40001';end if;
  insert into private.event_receipt_deliveries(id,order_id,actor_id) values((p_data->>'request')::uuid,o.id,auth.uid()) on conflict(id) do nothing;
  return jsonb_build_object('ok',true,'queued',true,'receipt',token,'emailState',(select state from private.event_receipt_deliveries where id=(p_data->>'request')::uuid));
 else raise exception 'invalid_event_staff' using errcode='22023';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_staff_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.event_staff_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.event_staff_admin(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_staff_admin(p_org,p_unit,p_event,p_action,p_id,p_version,p_data)$$;
revoke all on function public.event_staff_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.event_staff_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

-- Capability receipts disclose only the minimum needed at the door; no CPF, answers, e-mail or payment redirect.
create function member_app_api.event_receipt(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('title',e.title,'sale',e.commerce_mode='sale','state',case when e.status='cancelled' then 'cancelled' when o.state in('holding','reserved') and o.expires_at<=clock_timestamp() then 'expired' else o.state end,'starts',e.starts_at,'ends',e.ends_at,'pickup',e.pickup_at,'location',e.location,'items',coalesce((select jsonb_agg(jsonb_build_object('name',i.name,'ticket',i.type_name,'checkedIn',i.checked_in_at,'code',case when o.state='confirmed' and e.status='published' then i.code end)) from private.event_ticket_items i where i.order_id=o.id),'[]')) from private.event_receipt_links l join private.event_ticket_orders o on o.id=l.order_id join private.church_app_events e on e.id=o.event_id where l.token=p_token and e.status in('published','cancelled') and private.member_event_enabled(e.organization_id,e.unit_id) and e.ends_at>now()-interval '90 days';$$;
revoke all on function member_app_api.event_receipt(uuid) from public,service_role;
grant execute on function member_app_api.event_receipt(uuid) to anon,authenticated;
create function public.member_event_receipt(p_token uuid) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.event_receipt(p_token)$$;
revoke all on function public.member_event_receipt(uuid) from public,service_role;
grant execute on function public.member_event_receipt(uuid) to anon,authenticated;

create function private.event_receipt_work(p_action text,p_org uuid default null,p_event uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.event_receipt_deliveries;o private.event_ticket_orders;e private.church_app_events;token uuid;m private.event_messages;
begin
 if p_action='claim' then
  update private.event_receipt_deliveries set state='uncertain',updated_at=clock_timestamp() where state='sending' and updated_at<clock_timestamp()-interval '15 minutes';
  for d in select q.* from private.event_receipt_deliveries q join private.event_ticket_orders ord on ord.id=q.order_id where q.state='queued' and (p_org is null or ord.organization_id=p_org) and (p_event is null or ord.event_id=p_event) order by q.created_at limit 1 for update of q skip locked loop
   select * into o from private.event_ticket_orders where id=d.order_id;
   select * into e from private.church_app_events where id=o.event_id;
   m:=jsonb_populate_record(null::private.event_messages,jsonb_build_object('organization_id',e.organization_id,'unit_id',e.unit_id,'event_id',e.id,'created_by',d.actor_id));
   if not private.event_message_authorized(m) or e.status not in('published','cancelled') or o.state not in('confirmed','reserved','holding','payment_review') then update private.event_receipt_deliveries set state='cancelled' where id=d.id;continue;end if;
   select l.token into token from private.event_receipt_links l where l.order_id=o.id;
   update private.event_receipt_deliveries set state='sending',claim_token=extensions.gen_random_uuid(),updated_at=clock_timestamp() where id=d.id returning * into d;
   return jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',d.id,'token',d.claim_token,'recipient',o.buyer_email,'title','Seu comprovante · '||e.title,'receipt',token,'sale',e.commerce_mode='sale')));
  end loop;return jsonb_build_object('items','[]'::jsonb);
 elsif p_action='settle' then
  update private.event_receipt_deliveries set state=case when nullif(p_data->>'provider','') is null then 'uncertain' else 'sent' end,provider_id=nullif(p_data->>'provider',''),updated_at=clock_timestamp() where id=(p_data->>'id')::uuid and claim_token=(p_data->>'token')::uuid and state='sending';
  if not found then raise exception 'event_delivery_changed' using errcode='40001';end if;return jsonb_build_object('ok',true);
 end if;raise exception 'invalid_event_delivery' using errcode='22023';
end $$;
revoke all on function private.event_receipt_work(text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.event_receipt_work(text,uuid,uuid,jsonb) to service_role;
create function public.event_receipt_work(p_action text,p_org uuid default null,p_event uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_receipt_work(p_action,p_org,p_event,p_data)$$;
revoke all on function public.event_receipt_work(text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.event_receipt_work(text,uuid,uuid,jsonb) to service_role;

create function private.event_insights(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;start_at timestamptz;end_at timestamptz;result jsonb;program uuid;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.event_manager(p_org,p_unit) then raise exception 'event_operations_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for no key update;
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'event_operations_denied' using errcode='42501';end if;
 if p_action='journeys_save' then
  if p_data-array['programs']<>'{}' or jsonb_typeof(p_data->'programs') is distinct from 'array' or jsonb_array_length(p_data->'programs')>10 then raise exception 'invalid_event_report' using errcode='22023';end if;
  for program in select value::uuid from jsonb_array_elements_text(p_data->'programs') loop
   if not exists(select 1 from private.learning_programs p where p.id=program and p.organization_id=p_org and p.unit_id=p_unit and p.kind='journey' and p.status='published') then raise exception 'event_journey_denied' using errcode='42501';end if;
  end loop;
  delete from private.event_journeys where event_id=e.id;
  insert into private.event_journeys(event_id,program_id) select distinct e.id,value::uuid from jsonb_array_elements_text(p_data->'programs');
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'event.journeys.updated','church_app_event',e.id::text,jsonb_build_object('count',jsonb_array_length(p_data->'programs')));
  return jsonb_build_object('ok',true);
 elsif p_action='journeys' then return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'linked',exists(select 1 from private.event_journeys j where j.event_id=e.id and j.program_id=p.id))) from private.learning_programs p where p.organization_id=p_org and p.unit_id=p_unit and p.kind='journey' and p.status='published'),'[]'));end if;
 if p_data-array['from','to']<>'{}' or coalesce(p_data->>'from','')<>'' and p_data->>'from'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(p_data->>'to','')<>'' and p_data->>'to'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'invalid_event_report' using errcode='22023';end if;
 start_at:=coalesce(nullif(p_data->>'from','')::date,'1900-01-01'::date)::timestamp at time zone 'America/Sao_Paulo';
 end_at:=(coalesce(nullif(p_data->>'to','')::date,'2200-01-01'::date)+1)::timestamp at time zone 'America/Sao_Paulo';
 if end_at<=start_at then raise exception 'invalid_event_report' using errcode='22023';end if;
 if p_action='finance' then
  if not private.receiver_actor_allowed(auth.uid(),p_org,p_unit) and not exists(select 1 from private.event_ticket_orders o where o.event_id=e.id and private.receiver_actor_allowed(auth.uid(),p_org,o.receiving_unit)) then raise exception 'event_operations_finance_denied' using errcode='42501';end if;
  select jsonb_build_object('items',coalesce(jsonb_agg(x order by x.created_at desc),'[]'),'truncated',count(*)>=1000) into result from(select o.id,o.buyer_name,o.total::text,o.state,o.expires_at,u.name church,o.created_at,r.snapshot,r.review_reason from private.event_ticket_orders o join public.organization_units u on u.id=o.receiving_unit left join private.finance_digital_receipts r on r.order_id=o.finance_order where o.event_id=e.id and o.total>0 and o.created_at>=start_at and o.created_at<end_at and private.receiver_actor_allowed(auth.uid(),p_org,o.receiving_unit) order by o.created_at desc limit 1000)x;
  return result||jsonb_build_object('cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from private.event_refund_cases c where c.event_id=e.id and c.created_at>=start_at and c.created_at<end_at and private.receiver_actor_allowed(auth.uid(),p_org,c.receiving_unit)),'[]'),'summary',(select jsonb_build_object('orders',count(*),'gross',coalesce(sum(case when r.snapshot->>'state' in('approved','partially_refunded','refunded','disputed') then (r.snapshot->>'gross')::bigint else 0 end),0)::text,'refunds',coalesce(sum((r.snapshot->>'refunded')::bigint),0)::text,'fees',coalesce(sum((select sum((f->>'amount')::bigint) from jsonb_array_elements(case when jsonb_typeof(r.snapshot->'fees')='array' then r.snapshot->'fees' else '[]'::jsonb end)f)),0)::text,'unknownFees',count(*) filter(where r.snapshot is not null and r.snapshot->'fees'='null'::jsonb),'receivable',coalesce(sum(o.total) filter(where o.state in('holding','reserved') and o.expires_at>clock_timestamp()),0)::text,'review',count(*) filter(where o.state='payment_review')) from private.event_ticket_orders o left join private.finance_digital_receipts r on r.order_id=o.finance_order where o.event_id=e.id and o.total>0 and o.created_at>=start_at and o.created_at<end_at and private.receiver_actor_allowed(auth.uid(),p_org,o.receiving_unit)));
 elsif p_action='report' then
  return jsonb_build_object('sale',e.commerce_mode='sale','metrics',(select jsonb_build_object('confirmed',count(*) filter(where o.state='confirmed'),'checked',count(*) filter(where o.state='confirmed' and i.checked_in_at is not null),'absent',count(*) filter(where o.state='confirmed' and i.checked_in_at is null),'reserved',count(*) filter(where o.state='reserved' and o.expires_at>now()),'pending',count(*) filter(where o.state='holding' and o.expires_at>now()),'expired',count(*) filter(where o.state in('holding','reserved') and o.expires_at<=now())) from private.event_ticket_items i join private.event_ticket_orders o on o.id=i.order_id where o.event_id=e.id and o.created_at>=start_at and o.created_at<end_at),'interests',(select count(*) from private.event_interests i where i.event_id=e.id and i.active and i.created_at>=start_at and i.created_at<end_at),'converted',(select count(*) from private.event_interests i where i.event_id=e.id and i.active and i.created_at>=start_at and i.created_at<end_at and exists(select 1 from private.event_ticket_orders o where o.event_id=e.id and o.user_id=i.user_id and o.state='confirmed')),'ratings',(select jsonb_build_object('total',count(*),'average',coalesce(round(avg(stars),2),0),'distribution',jsonb_build_array(count(*) filter(where stars=1),count(*) filter(where stars=2),count(*) filter(where stars=3),count(*) filter(where stars=4),count(*) filter(where stars=5))) from private.event_ratings where event_id=e.id),'feedback',coalesce((select jsonb_agg(x) from(select stars,comment,created_at from private.event_ratings where event_id=e.id and comment<>'' order by updated_at desc limit 100)x),'[]'));
 end if;raise exception 'invalid_event_report' using errcode='22023';
end $$;
revoke all on function private.event_insights(uuid,uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.event_insights(uuid,uuid,uuid,text,jsonb) to authenticated;
create function public.event_insights(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_insights(p_org,p_unit,p_event,p_action,p_data)$$;
revoke all on function public.event_insights(uuid,uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.event_insights(uuid,uuid,uuid,text,jsonb) to authenticated;

create function member_app_api.event_experience(p_event uuid,p_stars integer default null,p_comment text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;eligible boolean;
begin
 select * into e from private.church_app_events where id=p_event and status='published';if not found or not private.member_event_enabled(e.organization_id,e.unit_id) then return null;end if;
 eligible:=auth.uid() is not null and e.ends_at<=now() and e.commerce_mode='event' and exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<now())) and (exists(select 1 from private.event_ticket_orders o where o.event_id=e.id and o.user_id=auth.uid() and o.state='confirmed') or exists(select 1 from private.church_app_registrations r where r.event_id=e.id and r.user_id=auth.uid() and r.status='confirmed'));
 if p_stars is not null then
  if not eligible then raise exception 'event_rating_denied' using errcode='42501';end if;
  if p_stars not between 1 and 5 or p_comment is null or length(p_comment)>1500 then raise exception 'invalid_event_rating' using errcode='22023';end if;
  insert into private.event_ratings(event_id,user_id,stars,comment) values(e.id,auth.uid(),p_stars,btrim(p_comment)) on conflict(event_id,user_id) do update set stars=excluded.stars,comment=excluded.comment,updated_at=clock_timestamp();
 end if;
 return jsonb_build_object('messages',coalesce((select jsonb_agg(x) from(select m.title,m.body,m.image_url,m.redirect_url from private.event_messages m where m.event_id=e.id and m.state='scheduled' and m.scheduled_at<=now() and m.scheduled_at>now()-interval '90 days' and auth.uid() is not null and private.event_message_authorized(m) and private.event_message_matches(m,auth.uid()) order by m.scheduled_at desc limit 20)x),'[]'),'eligible',eligible,'rating',(select jsonb_build_object('stars',stars,'comment',comment) from private.event_ratings where event_id=e.id and user_id=auth.uid()),'journeys',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'summary',p.summary)) from private.event_journeys j join private.learning_programs p on p.id=j.program_id where j.event_id=e.id and p.organization_id=e.organization_id and p.unit_id=e.unit_id and p.status='published'),'[]'));
end $$;
revoke all on function member_app_api.event_experience(uuid,integer,text) from public,service_role;
grant execute on function member_app_api.event_experience(uuid,integer,text) to anon,authenticated;
create function public.member_event_experience(p_event uuid,p_stars integer default null,p_comment text default '') returns jsonb language sql security invoker set search_path='' as $$select member_app_api.event_experience(p_event,p_stars,p_comment)$$;
revoke all on function public.member_event_experience(uuid,integer,text) from public,service_role;
grant execute on function public.member_event_experience(uuid,integer,text) to anon,authenticated;

-- Extend existing message validation and delivery; no outbound work in this migration.
do $patch$
declare d text;needle text;
begin
 select pg_get_functiondef('private.event_operations_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,$sql$p_data-array['title','body','audience','email','scheduled']$sql$,$sql$p_data-array['title','body','audience','email','scheduled','image','redirect']$sql$);
 needle:='   select * into m from private.event_messages where id=p_id;';
 if position(needle in d)=0 then raise exception 'message media anchor';end if;
 d:=replace(d,needle,$sql$   if coalesce(p_data->>'image','')<>'' and (length(p_data->>'image')>2000 or not private.ministry_public_url(p_data->>'image')) or coalesce(p_data->>'redirect','')<>'' and (length(p_data->>'redirect')>2000 or not private.ministry_public_url(p_data->>'redirect')) then raise exception 'invalid_event_operations' using errcode='22023';end if;
$sql$||needle);
 needle:='  elsif p_action in(''message_schedule'',''message_cancel'') then';
 d:=replace(d,needle,$sql$   update private.event_messages set image_url=coalesce(p_data->>'image',''),redirect_url=coalesce(p_data->>'redirect','') where id=p_id and event_id=e.id;
$sql$||needle);execute d;
 select pg_get_functiondef('private.event_email_work(text,uuid,uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,$sql$'unsubscribe',d.unsubscribe_token$sql$,$sql$'unsubscribe',d.unsubscribe_token,'image',m.image_url,'redirect',m.redirect_url$sql$);execute d;
end $patch$;
notify pgrst,'reload schema';

-- Keep the provider claim, reservation deadline and verified confirmation on the same cutoff.
do $patch$
declare d text; f text;
begin
 foreach f in array array['private.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text)','private.event_ticket_delivery(uuid,text,jsonb)','private.event_ticket_payment_apply()'] loop
  select pg_get_functiondef(f::regprocedure) into d;
  if f like '%checkout%' then
   d:=replace(d,'expires:=least(e.starts_at,','expires:=least((case when e.commerce_mode=''sale'' then e.starts_at else e.ends_at end),');
  else
   if position('e.starts_at<=clock_timestamp()' in d)=0 then raise exception 'event payment cutoff anchor missing: %',f;end if;
   d:=replace(d,'e.starts_at<=clock_timestamp()','(case when e.commerce_mode=''sale'' then e.starts_at else e.ends_at end)<=clock_timestamp()');
  end if;
  execute d;
 end loop;
end $patch$;

create function private.event_receipt_payment(p_token uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('event',o.event_id,'id',o.id,'proof',s.proof) from private.event_receipt_links l join private.event_staff_orders s on s.order_id=l.order_id join private.event_ticket_orders o on o.id=l.order_id join private.church_app_events e on e.id=o.event_id where l.token=p_token and o.user_id is null and o.total>0 and o.state in('holding','reserved') and o.expires_at>clock_timestamp() and e.status='published' and (case when e.commerce_mode='sale' then e.starts_at else e.ends_at end)>clock_timestamp() and private.member_event_enabled(e.organization_id,e.unit_id);$$;
revoke all on function private.event_receipt_payment(uuid) from public,anon,authenticated;
grant execute on function private.event_receipt_payment(uuid) to service_role;
create function public.event_receipt_payment(p_token uuid) returns jsonb language sql security invoker set search_path='' as $$select private.event_receipt_payment(p_token)$$;
revoke all on function public.event_receipt_payment(uuid) from public,anon,authenticated;
grant execute on function public.event_receipt_payment(uuid) to service_role;
do $patch$
declare d text;
begin
 select pg_get_functiondef('member_app_api.event_receipt(uuid)'::regprocedure) into d;
 d:=replace(d,$sql$'title',e.title$sql$,$sql$'canPay',exists(select 1 from private.event_staff_orders staff where staff.order_id=o.id) and o.total>0 and o.state in('holding','reserved') and o.expires_at>now() and e.status='published','title',e.title$sql$);execute d;
end $patch$;
notify pgrst,'reload schema';

