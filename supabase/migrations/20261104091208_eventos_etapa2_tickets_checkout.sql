set local lock_timeout='5s';
create table private.event_ticket_settings(
 event_id uuid primary key references private.church_app_events(id),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 enabled boolean not null default false,allow_guests boolean not null default false,show_remaining boolean not null default true,
 purpose_id uuid references private.finance_purposes(id),receiving_unit uuid not null,reservation_hours integer not null default 24 check(reservation_hours between 1 and 168),
 questions jsonb not null default '[]',created_by uuid not null references auth.users(id),
 foreign key(event_id,organization_id,unit_id) references private.church_app_events(id,organization_id,unit_id),
 foreign key(receiving_unit,organization_id) references public.organization_units(id,organization_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id));
create table private.event_ticket_types(
 id uuid primary key,event_id uuid not null references private.event_ticket_settings(event_id),name text not null check(length(btrim(name)) between 2 and 160),
 mode text not null check(mode in('free','paid','reservation')),price bigint not null check(price between 0 and 99999999),quantity integer check(quantity between 1 and 50000),
 starts_at timestamptz not null,ends_at timestamptz not null,active boolean not null default true,
 per_user integer check(per_user between 1 and 100),per_cpf integer check(per_cpf between 1 and 100),audience text not null default 'public' check(audience in('public','members','units')),audience_units uuid[] not null default '{}',
 position integer not null default 0,version integer not null default 1,check(ends_at>starts_at),check((mode='free' and price=0) or (mode<>'free' and price>=100)),unique(id,event_id));
create index event_ticket_types_event on private.event_ticket_types(event_id,position,id);
create table private.event_ticket_coupons(
 id uuid primary key,event_id uuid not null references private.event_ticket_settings(event_id),code text not null check(code~'^[A-Z0-9_-]{2,40}$'),
 kind text not null check(kind in('fixed','percent')),value bigint not null check(value>0),ends_at timestamptz not null,
 usage_limit integer check(usage_limit between 1 and 100000),once_per_buyer boolean not null default true,ticket_types uuid[] not null default '{}',active boolean not null default true,version integer not null default 1,
 check(kind<>'percent' or value<=100),unique(event_id,code));
create index event_ticket_coupons_event on private.event_ticket_coupons(event_id);
create table private.event_ticket_orders(
 id uuid primary key,event_id uuid not null references private.event_ticket_settings(event_id),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 user_id uuid references auth.users(id),proof_hash text not null,fingerprint text not null,buyer_name text not null,buyer_email text not null,buyer_key text not null,
 state text not null check(state in('holding','reserved','confirmed','cancelled','payment_review')),expires_at timestamptz not null,
 subtotal bigint not null check(subtotal>=0),discount bigint not null default 0 check(discount>=0),total bigint not null check(total>=0),coupon_id uuid references private.event_ticket_coupons(id),questions jsonb not null,
 purpose_id uuid references private.finance_purposes(id),receiving_unit uuid references public.organization_units(id),financial_actor uuid references auth.users(id),receiver_id uuid references private.finance_receivers(id),classification jsonb,
 finance_order uuid unique references private.finance_digital_orders(id),checkout_state text not null default 'reserved' check(checkout_state in('reserved','dispatching','ready','uncertain')),
 checkout_url text,preference_id text,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 foreign key(event_id,organization_id,unit_id) references private.church_app_events(id,organization_id,unit_id),check(total=subtotal-discount),check((checkout_state='ready')=(checkout_url is not null and preference_id is not null)));
create index event_ticket_orders_event on private.event_ticket_orders(event_id,state,expires_at);
create index event_ticket_orders_user on private.event_ticket_orders(user_id,organization_id,created_at desc);
create index event_ticket_orders_buyer on private.event_ticket_orders(event_id,buyer_key,created_at desc);
create index event_ticket_orders_coupon on private.event_ticket_orders(coupon_id,state,expires_at);
create index event_ticket_orders_org on private.event_ticket_orders(organization_id,unit_id);
create table private.event_ticket_items(
 id uuid primary key default extensions.gen_random_uuid(),order_id uuid not null references private.event_ticket_orders(id),event_id uuid not null references private.church_app_events(id),type_id uuid not null,
 type_name text not null,price bigint not null check(price>=0),name text not null,email text not null default '',cpf text not null default '',phone text not null default '',answers jsonb not null default '{}',
 code uuid not null unique default extensions.gen_random_uuid(),checked_in_at timestamptz,checked_in_by uuid references auth.users(id),foreign key(type_id,event_id) references private.event_ticket_types(id,event_id));
create index event_ticket_items_order on private.event_ticket_items(order_id);
create index event_ticket_items_event on private.event_ticket_items(event_id,type_id);
create index event_ticket_items_cpf on private.event_ticket_items(type_id,cpf);
create index event_ticket_items_checker on private.event_ticket_items(checked_in_by);
alter table private.event_ticket_settings enable row level security;
alter table private.event_ticket_types enable row level security;
alter table private.event_ticket_coupons enable row level security;
alter table private.event_ticket_orders enable row level security;
alter table private.event_ticket_items enable row level security;
revoke all on private.event_ticket_settings,private.event_ticket_types,private.event_ticket_coupons,private.event_ticket_orders,private.event_ticket_items from public,anon,authenticated,service_role;

create function private.event_ticket_used(p_event uuid,p_type uuid default null,p_exclude uuid default null) returns integer language sql stable security definer set search_path='' as $$
 select count(*)::integer from private.event_ticket_items i join private.event_ticket_orders o on o.id=i.order_id where i.event_id=p_event and (p_type is null or i.type_id=p_type) and (p_exclude is null or o.id<>p_exclude) and (o.state='confirmed' or o.state in('holding','reserved') and o.expires_at>clock_timestamp());$$;
revoke all on function private.event_ticket_used(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function private.event_ticket_questions_valid(d jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare q jsonb;
begin
 if jsonb_typeof(d) is distinct from 'array' or jsonb_array_length(d)>30 then return false;end if;
 for q in select value from jsonb_array_elements(d) loop
  if jsonb_typeof(q) is distinct from 'object' or q-array['id','label','kind','required','options']<>'{}' or not(q ?& array['id','label','kind','required','options']) or jsonb_typeof(q->'label') is distinct from 'string' or length(btrim(q->>'label')) not between 2 and 160 or jsonb_typeof(q->'required') is distinct from 'boolean' or coalesce(q->>'kind','') not in('text','email','date','cpf','phone','number','select','boolean') or jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options')>30 then return false;end if;
  if nullif(q->>'id','')::uuid is null then return false;end if;
  if q->>'kind'='select' and jsonb_array_length(q->'options')=0 then return false;end if;
  if exists(select 1 from jsonb_array_elements(q->'options')v where jsonb_typeof(v) is distinct from 'string' or length(v#>>'{}') not between 1 and 100) then return false;end if;
 end loop;
 return (select count(distinct v->>'id')=jsonb_array_length(d) from jsonb_array_elements(d)v);
exception when others then return false;end $$;
revoke all on function private.event_ticket_questions_valid(jsonb) from public,anon,authenticated,service_role;

create function private.event_ticket_admin(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;s private.event_ticket_settings;t private.event_ticket_types;c private.event_ticket_coupons;uid uuid;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.event_manager(p_org,p_unit) then raise exception 'event_ticket_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for no key update;
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'event_ticket_denied' using errcode='42501';end if;
 select * into s from private.event_ticket_settings where event_id=e.id;
 if p_action='read' then return jsonb_build_object('event',to_jsonb(e),'settings',to_jsonb(s),'types',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('used',private.event_ticket_used(e.id,x.id)) order by x.position,x.id) from private.event_ticket_types x where x.event_id=e.id),'[]'),'coupons',coalesce((select jsonb_agg(to_jsonb(x)) from private.event_ticket_coupons x where x.event_id=e.id),'[]'),'purposes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'unit',p.unit_id,'unit_name',u.name,'ready',private.member_payment_receiver(p_org,p.unit_id,p.id) is not null)) from private.finance_purposes p join public.organization_units u on u.id=p.unit_id and u.organization_id=p.organization_id where p.organization_id=p_org and p.active and p.origin='event' and private.can_access_unit(p_org,p.unit_id,array['manage','admin']::public.unit_access_level[])),'[]'));end if;
 if p_action='registrations' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(x) from (select i.id,i.name,i.type_name ticket,i.code,i.checked_in_at,o.id order_id,o.buyer_name,o.buyer_email,case when o.state in('reserved','holding') and o.expires_at<clock_timestamp() then 'expired' else o.state end state,o.total::text total,o.created_at from private.event_ticket_items i join private.event_ticket_orders o on o.id=i.order_id where i.event_id=e.id order by o.created_at desc,i.id limit 1000)x),'[]'));
 end if;
 if p_action='checkin' then
  if e.status<>'published' or clock_timestamp()<e.starts_at-interval '2 hours' or clock_timestamp()>e.ends_at+interval '6 hours' then raise exception 'event_ticket_closed' using errcode='40001';end if;
  select i.id into uid from private.event_ticket_items i join private.event_ticket_orders o on o.id=i.order_id where i.event_id=e.id and i.code=(p_data->>'code')::uuid and o.state='confirmed' for update of i;
  if not found then raise exception 'event_ticket_denied' using errcode='42501';end if;
  if exists(select 1 from private.event_ticket_items where id=uid and checked_in_at is not null) then return jsonb_build_object('ok',true,'already',true);end if;
  update private.event_ticket_items set checked_in_at=clock_timestamp(),checked_in_by=auth.uid() where id=uid;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'event.ticket.checkin','event_ticket_item',uid::text);
  return jsonb_build_object('ok',true,'already',false);
 end if;
 if e.version is distinct from p_version or e.status='cancelled' then raise exception 'event_ticket_changed' using errcode='40001';end if;
 if p_action='settings' then
  if p_data-array['enabled','allow_guests','show_remaining','purpose','receiving_unit','reservation_hours','questions']<>'{}' or not(p_data ?& array['enabled','allow_guests','show_remaining','purpose','receiving_unit','reservation_hours','questions']) or jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'allow_guests') is distinct from 'boolean' or jsonb_typeof(p_data->'show_remaining') is distinct from 'boolean' or not private.event_ticket_questions_valid(p_data->'questions') or (p_data->>'reservation_hours')::integer not between 1 and 168 then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  uid:=(p_data->>'receiving_unit')::uuid;
  if not private.can_access_unit(p_org,uid,array['manage','admin']::public.unit_access_level[]) or not exists(select 1 from public.organization_units where id=uid and organization_id=p_org and status='active') or nullif(p_data->>'purpose','') is not null and not exists(select 1 from private.finance_purposes where id=(p_data->>'purpose')::uuid and organization_id=p_org and unit_id=uid and origin='event' and active) then raise exception 'event_ticket_denied' using errcode='42501';end if;
  if (p_data->>'enabled')::boolean and not coalesce(s.enabled,false) and (exists(select 1 from private.church_app_registrations where event_id=e.id and status='confirmed') or exists(select 1 from private.member_event_orders where event_id=e.id)) then raise exception 'event_ticket_legacy_active' using errcode='40001';end if;
  insert into private.event_ticket_settings(event_id,organization_id,unit_id,enabled,allow_guests,show_remaining,purpose_id,receiving_unit,reservation_hours,questions,created_by) values(e.id,p_org,p_unit,(p_data->>'enabled')::boolean,(p_data->>'allow_guests')::boolean,(p_data->>'show_remaining')::boolean,nullif(p_data->>'purpose','')::uuid,uid,(p_data->>'reservation_hours')::integer,p_data->'questions',auth.uid()) on conflict(event_id) do update set enabled=excluded.enabled,allow_guests=excluded.allow_guests,show_remaining=excluded.show_remaining,purpose_id=excluded.purpose_id,receiving_unit=excluded.receiving_unit,reservation_hours=excluded.reservation_hours,questions=excluded.questions,created_by=excluded.created_by;
 elsif p_action='type' then
  if s.event_id is null or p_id is null or p_data-array['name','mode','price','quantity','starts','ends','active','per_user','per_cpf','audience','audience_units','position']<>'{}' or not(p_data ?& array['name','mode','price','quantity','starts','ends','active','per_user','per_cpf','audience','audience_units','position']) or jsonb_typeof(p_data->'active') is distinct from 'boolean' or jsonb_typeof(p_data->'audience_units') is distinct from 'array' then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  if (p_data->>'ends')::timestamptz>e.ends_at or (p_data->>'starts')::timestamptz>e.ends_at then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  if p_data->>'audience'='units' and jsonb_array_length(p_data->'audience_units')=0 or exists(select 1 from jsonb_array_elements_text(p_data->'audience_units')v where not private.event_manager(p_org,v::uuid)) then raise exception 'event_ticket_denied' using errcode='42501';end if;
  select * into t from private.event_ticket_types where id=p_id;
  if found and t.event_id<>e.id then raise exception 'event_ticket_denied' using errcode='42501';end if;
  if nullif(p_data->>'quantity','')::integer<private.event_ticket_used(e.id,p_id) then raise exception 'event_ticket_quantity' using errcode='40001';end if;
  insert into private.event_ticket_types(id,event_id,name,mode,price,quantity,starts_at,ends_at,active,per_user,per_cpf,audience,audience_units,position) values(p_id,e.id,btrim(p_data->>'name'),p_data->>'mode',(p_data->>'price')::bigint,nullif(p_data->>'quantity','')::integer,(p_data->>'starts')::timestamptz,(p_data->>'ends')::timestamptz,(p_data->>'active')::boolean,nullif(p_data->>'per_user','')::integer,nullif(p_data->>'per_cpf','')::integer,p_data->>'audience',array(select value::uuid from jsonb_array_elements_text(p_data->'audience_units')),(p_data->>'position')::integer) on conflict(id) do update set name=excluded.name,mode=excluded.mode,price=excluded.price,quantity=excluded.quantity,starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=excluded.active,per_user=excluded.per_user,per_cpf=excluded.per_cpf,audience=excluded.audience,audience_units=excluded.audience_units,position=excluded.position,version=event_ticket_types.version+1;
 elsif p_action='coupon' then
  if s.event_id is null or p_id is null or p_data-array['code','kind','value','ends','limit','once','types','active']<>'{}' or not(p_data ?& array['code','kind','value','ends','limit','once','types','active']) or jsonb_typeof(p_data->'once') is distinct from 'boolean' or jsonb_typeof(p_data->'active') is distinct from 'boolean' or jsonb_typeof(p_data->'types') is distinct from 'array' then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  select * into c from private.event_ticket_coupons where id=p_id;if found and c.event_id<>e.id then raise exception 'event_ticket_denied' using errcode='42501';end if;
  if exists(select 1 from jsonb_array_elements_text(p_data->'types')v where not exists(select 1 from private.event_ticket_types where id=v::uuid and event_id=e.id)) then raise exception 'event_ticket_denied' using errcode='42501';end if;
  insert into private.event_ticket_coupons(id,event_id,code,kind,value,ends_at,usage_limit,once_per_buyer,ticket_types,active) values(p_id,e.id,upper(btrim(p_data->>'code')),p_data->>'kind',(p_data->>'value')::bigint,(p_data->>'ends')::timestamptz,nullif(p_data->>'limit','')::integer,(p_data->>'once')::boolean,array(select value::uuid from jsonb_array_elements_text(p_data->'types')),(p_data->>'active')::boolean) on conflict(id) do update set code=excluded.code,kind=excluded.kind,value=excluded.value,ends_at=excluded.ends_at,usage_limit=excluded.usage_limit,once_per_buyer=excluded.once_per_buyer,ticket_types=excluded.ticket_types,active=excluded.active,version=event_ticket_coupons.version+1;
 else raise exception 'invalid_event_ticket' using errcode='22023';end if;
 update private.church_app_events set version=version+1,commerce_version=commerce_version+1,updated_at=clock_timestamp() where id=e.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'event.ticket.'||p_action,'church_app_event',e.id::text);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.event_ticket_admin(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_ticket_admin(p_org,p_unit,p_event,p_action,p_id,p_version,p_data)$$;
revoke all on function public.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

create function private.event_ticket_audience(p_actor uuid,p_org uuid,t private.event_ticket_types) returns boolean language sql stable security definer set search_path='' as $$
 select t.audience='public' or exists(select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id where m.user_id=p_actor and m.organization_id=p_org and m.status='active' and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<now()) and (t.audience='members' or m.default_unit_id=any(t.audience_units)));$$;
revoke all on function private.event_ticket_audience(uuid,uuid,private.event_ticket_types) from public,anon,authenticated,service_role;
create function private.event_cpf_valid(value text) returns boolean language plpgsql immutable set search_path='' as $$
declare d text:=regexp_replace(value,'[^0-9]','','g');n integer;v integer;s integer;
begin
 if length(d)<>11 or d=repeat(substr(d,1,1),11) then return false;end if;
 for n in 10..11 loop s:=0;for v in 1..n-1 loop s:=s+substr(d,v,1)::integer*(n+1-v);end loop;s:=(s*10)%11;if s=10 then s:=0;end if;if s<>substr(d,n,1)::integer then return false;end if;end loop;return true;
exception when others then return false;end $$;
revoke all on function private.event_cpf_valid(text) from public,anon,authenticated,service_role;
create function private.event_ticket_answers_valid(d jsonb,questions jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare q jsonb;v text;
begin
 if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>24000 or exists(select 1 from jsonb_each(d) a where not exists(select 1 from jsonb_array_elements(questions)question_row where question_row->>'id'=a.key) or jsonb_typeof(a.value) is distinct from 'string') then return false;end if;
 for q in select value from jsonb_array_elements(questions) loop
  v:=btrim(coalesce(d->>(q->>'id'),''));if length(v)>1000 or (q->>'required')::boolean and v='' then return false;end if;
  if v<>'' then
   if q->>'kind'='email' and v!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or q->>'kind'='number' and v!~'^[0-9]{1,12}$' or q->>'kind'='boolean' and v not in('Sim','Não') or q->>'kind'='select' and not(q->'options' ? v) or q->>'kind'='cpf' and not private.event_cpf_valid(v) or q->>'kind'='phone' and length(regexp_replace(v,'[^0-9]','','g')) not between 10 and 13 then return false;end if;
   if q->>'kind'='date' then if v!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or v::date is null then return false;end if;end if;
  end if;
 end loop;return true;
exception when others then return false;end $$;
revoke all on function private.event_ticket_answers_valid(jsonb,jsonb) from public,anon,authenticated,service_role;
create function member_app_api.event_ticket_catalog(p_event uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.church_app_events;s private.event_ticket_settings;
begin
 select * into e from private.church_app_events where id=p_event and status='published';if not found or not private.member_event_enabled(e.organization_id,e.unit_id) then return null;end if;
 select * into s from private.event_ticket_settings where event_id=e.id and enabled;if not found then return jsonb_build_object('enabled',false);end if;
 return jsonb_build_object('enabled',true,'event',e.id,'allowGuests',s.allow_guests,'authenticated',auth.uid() is not null,'showRemaining',s.show_remaining,'questions',s.questions,'canPay',s.purpose_id is not null and private.member_payment_receiver(e.organization_id,s.receiving_unit,s.purpose_id) is not null,
 'remaining',case when s.show_remaining then greatest(0,e.capacity-private.event_ticket_used(e.id)) end,'types',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'mode',t.mode,'price',t.price::text,'starts',t.starts_at,'ends',t.ends_at,'perUser',t.per_user,'perCpf',t.per_cpf,'remaining',case when s.show_remaining then least(greatest(0,e.capacity-private.event_ticket_used(e.id)),coalesce(t.quantity,50000)-private.event_ticket_used(e.id,t.id)) end) order by t.position,t.id) from private.event_ticket_types t where t.event_id=e.id and t.active and private.event_ticket_audience(auth.uid(),e.organization_id,t)),'[]'));
end $$;
revoke all on function member_app_api.event_ticket_catalog(uuid) from public,service_role;
grant execute on function member_app_api.event_ticket_catalog(uuid) to anon,authenticated;
create function public.member_event_ticket_catalog(p_event uuid) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.event_ticket_catalog(p_event)$$;
revoke all on function public.member_event_ticket_catalog(uuid) from public,service_role;
grant execute on function public.member_event_ticket_catalog(uuid) to anon,authenticated;

create table private.event_checkout_limits(key text not null,bucket_at timestamptz not null,attempts integer not null,primary key(key,bucket_at));
alter table private.event_checkout_limits enable row level security;
revoke all on private.event_checkout_limits from public,anon,authenticated,service_role;
create function private.event_ticket_order_view(o private.event_ticket_orders) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('ok',true,'id',o.id,'event',o.event_id,'state',case when o.state in('holding','reserved') and o.expires_at<=clock_timestamp() then 'expired' else o.state end,'expires',o.expires_at,'subtotal',o.subtotal::text,'discount',o.discount::text,'total',o.total::text,'buyerName',o.buyer_name,'buyerEmail',o.buyer_email,'questions',o.questions,'checkoutState',o.checkout_state,'checkoutUrl',case when o.state='holding' and o.expires_at>clock_timestamp() and o.checkout_state='ready' then o.checkout_url end,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'type',i.type_id,'ticket',i.type_name,'price',i.price::text,'name',i.name,'email',i.email,'cpf',i.cpf,'phone',i.phone,'answers',i.answers,'checkedIn',i.checked_in_at,'code',case when o.state='confirmed' and exists(select 1 from private.church_app_events where id=o.event_id and status='published') then i.code end) order by i.id) from private.event_ticket_items i where i.order_id=o.id),'[]'));$$;
revoke all on function private.event_ticket_order_view(private.event_ticket_orders) from public,anon,authenticated,service_role;
create function private.event_ticket_checkout(p_event uuid,p_action text,p_id uuid,p_actor uuid,p_proof text,p_data jsonb default '{}',p_network text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;s private.event_ticket_settings;o private.event_ticket_orders;t private.event_ticket_types;c private.event_ticket_coupons;line jsonb;subtotal bigint:=0;eligible bigint:=0;discount bigint:=0;qty integer;used integer;mail text;buyer text;fingerprint text;expires timestamptz;purpose private.finance_purposes;receiver uuid;confirmed boolean;finance private.finance_digital_orders;attempts integer;
begin
 if p_actor is not null and not exists(select 1 from auth.users where id=p_actor and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<now())) then raise exception 'event_ticket_login' using errcode='42501';end if;
 if p_action='mine' then
  if p_actor is null then raise exception 'event_ticket_login' using errcode='42501';end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(private.event_ticket_order_view(q)||jsonb_build_object('title',e0.title,'starts',e0.starts_at,'ends',e0.ends_at,'location',e0.location,'eventStatus',e0.status)) from (select * from private.event_ticket_orders where user_id=p_actor order by created_at desc limit 100)q join private.church_app_events e0 on e0.id=q.event_id),'[]'));
 end if;
 if p_proof is null or p_proof!~'^[0-9a-f]{64}$' or p_id is null then raise exception 'event_ticket_proof' using errcode='42501';end if;
 perform 1 from public.organizations where id=(select organization_id from private.church_app_events where id=p_event) for no key update;
 select * into e from private.church_app_events where id=p_event for update;if not found or not private.member_event_enabled(e.organization_id,e.unit_id) then raise exception 'event_ticket_closed' using errcode='42501';end if;
 select * into s from private.event_ticket_settings where event_id=e.id;
 select * into o from private.event_ticket_orders where id=p_id for update;
 if found then
  if o.event_id<>p_event or (o.proof_hash<>encode(extensions.digest(p_proof,'sha256'),'hex') and not(o.user_id is not null and o.user_id=p_actor)) or (o.user_id is not null and o.user_id is distinct from p_actor) then raise exception 'event_ticket_proof' using errcode='42501';end if;
  if p_action='create' and o.fingerprint<>encode(extensions.digest(p_data::text,'sha256'),'hex') then raise exception 'event_ticket_changed' using errcode='40001';end if;
  if p_action in('status','create') then return private.event_ticket_order_view(o);end if;
  if p_action='cancel' then
   if o.state='confirmed' and o.total>0 or o.finance_order is not null then raise exception 'event_ticket_payment_review' using errcode='40001';end if;
   if e.starts_at<=clock_timestamp() or exists(select 1 from private.event_ticket_items where order_id=o.id and checked_in_at is not null) then raise exception 'event_ticket_closed' using errcode='40001';end if;
   update private.event_ticket_orders set state='cancelled',updated_at=clock_timestamp() where id=o.id returning * into o;return private.event_ticket_order_view(o);
  end if;
  if p_action<>'pay' then raise exception 'invalid_event_ticket' using errcode='22023';end if;
 else
  if p_action not in('create','quote') then raise exception 'event_ticket_proof' using errcode='42501';end if;
  if not coalesce(s.enabled,false) or e.status<>'published' or e.starts_at<=clock_timestamp() then raise exception 'event_ticket_closed' using errcode='40001';end if;
  if p_actor is null and not s.allow_guests then raise exception 'event_ticket_login' using errcode='42501';end if;
  if p_data-array['buyerName','buyerEmail','emailConfirmation','items','coupon','intent','expectedTotal','revision']<>'{}' or not(p_data ?& array['buyerName','buyerEmail','emailConfirmation','items','coupon','intent']) or coalesce(length(btrim(p_data->>'buyerName')),0) not between 2 and 160 or coalesce(length(p_data->>'buyerEmail'),0) not between 3 and 254 or p_data->>'buyerEmail'!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or lower(btrim(p_data->>'buyerEmail'))<>lower(btrim(p_data->>'emailConfirmation')) or coalesce(p_data->>'intent','') not in('reserve','pay') or jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items') not between 1 and 20 then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  mail:=lower(btrim(p_data->>'buyerEmail'));if p_actor is not null then select lower(email) into mail from auth.users where id=p_actor;if mail<>lower(btrim(p_data->>'buyerEmail')) then raise exception 'event_ticket_email' using errcode='22023';end if;end if;
  buyer:=encode(extensions.digest(mail,'sha256'),'hex');
  if (select count(*) from private.event_ticket_orders where event_id=e.id and buyer_key=buyer and created_at>clock_timestamp()-interval '1 day')>=10 then raise exception 'event_ticket_rate_limit' using errcode='22023';end if;
  if p_network!~'^[0-9a-f]{64}$' then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  insert into private.event_checkout_limits values(p_network,date_trunc('hour',clock_timestamp()),1) on conflict(key,bucket_at) do update set attempts=event_checkout_limits.attempts+1 returning event_checkout_limits.attempts into attempts;
  if attempts>200 then raise exception 'event_ticket_rate_limit' using errcode='22023';end if;
  qty:=jsonb_array_length(p_data->'items');if private.event_ticket_used(e.id)+qty>e.capacity then raise exception 'event_ticket_full' using errcode='40001';end if;
  for t in select * from private.event_ticket_types where event_id=e.id and id in(select (v->>'type')::uuid from jsonb_array_elements(p_data->'items')v) order by id for update loop
   used:=(select count(*) from jsonb_array_elements(p_data->'items')v where (v->>'type')::uuid=t.id);
   if not t.active or t.starts_at>clock_timestamp() or t.ends_at<=clock_timestamp() or not private.event_ticket_audience(p_actor,e.organization_id,t) or t.mode='paid' and p_data->>'intent'='reserve' then raise exception 'event_ticket_closed' using errcode='40001';end if;
   if t.quantity is not null and private.event_ticket_used(e.id,t.id)+used>t.quantity then raise exception 'event_ticket_full' using errcode='40001';end if;
   if t.per_user is not null and used+(select count(*) from private.event_ticket_items i join private.event_ticket_orders ord on ord.id=i.order_id where i.type_id=t.id and (ord.buyer_key=buyer or p_actor is not null and ord.user_id=p_actor) and (ord.state='confirmed' or ord.state in('holding','reserved') and ord.expires_at>clock_timestamp()))>t.per_user then raise exception 'event_ticket_person_limit' using errcode='22023';end if;
  end loop;
  for line in select value from jsonb_array_elements(p_data->'items') loop
   select * into t from private.event_ticket_types where id=(line->>'type')::uuid and event_id=e.id;
   if not found or line-array['type','name','email','cpf','phone','answers']<>'{}' or not(line ?& array['type','name','email','cpf','phone','answers']) or coalesce(length(btrim(line->>'name')),0) not between 2 and 160 or length(line->>'email')>254 or length(line->>'phone')>22 or line->>'email'<>'' and line->>'email'!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or not private.event_ticket_answers_valid(line->'answers',s.questions) then raise exception 'invalid_event_ticket' using errcode='22023';end if;
   if coalesce(line->>'cpf','')<>'' and not private.event_cpf_valid(line->>'cpf') or t.per_cpf is not null and not private.event_cpf_valid(line->>'cpf') then raise exception 'event_ticket_cpf' using errcode='22023';end if;
   if t.per_cpf is not null and (select count(*) from jsonb_array_elements(p_data->'items')v where v->>'type'=t.id::text and regexp_replace(v->>'cpf','[^0-9]','','g')=regexp_replace(line->>'cpf','[^0-9]','','g'))+(select count(*) from private.event_ticket_items i join private.event_ticket_orders ord on ord.id=i.order_id where i.type_id=t.id and i.cpf=regexp_replace(line->>'cpf','[^0-9]','','g') and (ord.state='confirmed' or ord.state in('holding','reserved') and ord.expires_at>clock_timestamp()))>t.per_cpf then raise exception 'event_ticket_person_limit' using errcode='22023';end if;
   subtotal:=subtotal+t.price;
  end loop;
  if coalesce(p_data->>'coupon','')<>'' then
   select * into c from private.event_ticket_coupons where event_id=e.id and code=upper(btrim(p_data->>'coupon')) and active and ends_at>clock_timestamp() for update;
   if not found or c.usage_limit is not null and (select count(*) from private.event_ticket_orders ord where ord.coupon_id=c.id and (ord.state='confirmed' or ord.state in('holding','reserved') and ord.expires_at>clock_timestamp()))>=c.usage_limit or c.once_per_buyer and exists(select 1 from private.event_ticket_orders ord where ord.coupon_id=c.id and (ord.buyer_key=buyer or p_actor is not null and ord.user_id=p_actor) and (ord.state='confirmed' or ord.state in('holding','reserved') and ord.expires_at>clock_timestamp())) then raise exception 'event_ticket_coupon' using errcode='22023';end if;
   select coalesce(sum(t0.price),0) into eligible from jsonb_array_elements(p_data->'items')v join private.event_ticket_types t0 on t0.id=(v->>'type')::uuid and t0.event_id=e.id where cardinality(c.ticket_types)=0 or t0.id=any(c.ticket_types);
   if eligible=0 then raise exception 'event_ticket_coupon' using errcode='22023';end if;
   discount:=least(eligible,case when c.kind='percent' then eligible*c.value/100 else c.value end);
  end if;
  if subtotal-discount>999999999 then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  if subtotal-discount between 1 and 99 then raise exception 'event_ticket_minimum' using errcode='22023';end if;
  if p_action='create' and (p_data ? 'expectedTotal') and ((p_data->>'expectedTotal')::bigint<>subtotal-discount or (p_data->>'revision')::integer<>e.version) then raise exception 'event_ticket_quote_changed' using errcode='40001';end if;
  confirmed:=subtotal=discount;
  if not confirmed then
   select * into purpose from private.finance_purposes where id=s.purpose_id and organization_id=e.organization_id and unit_id=s.receiving_unit and origin='event' and active for share;
   receiver:=private.member_payment_receiver(e.organization_id,s.receiving_unit,purpose.id);
   if receiver is null or not private.receiver_actor_allowed(s.created_by,e.organization_id,s.receiving_unit) then raise exception 'event_ticket_payment_unavailable' using errcode='42501';end if;
  end if;
  if p_action='quote' then return jsonb_build_object('ok',true,'subtotal',subtotal::text,'discount',discount::text,'total',(subtotal-discount)::text,'revision',e.version);end if;
  expires:=least(e.starts_at,clock_timestamp()+case when p_data->>'intent'='reserve' then make_interval(hours=>s.reservation_hours) else interval '30 minutes' end,(select min(ends_at) from private.event_ticket_types where id in(select (v->>'type')::uuid from jsonb_array_elements(p_data->'items')v)));
  insert into private.event_ticket_orders(id,event_id,organization_id,unit_id,user_id,proof_hash,fingerprint,buyer_name,buyer_email,buyer_key,state,expires_at,subtotal,discount,total,coupon_id,questions,purpose_id,receiving_unit,financial_actor,receiver_id,classification)
   values(p_id,e.id,e.organization_id,e.unit_id,p_actor,encode(extensions.digest(p_proof,'sha256'),'hex'),encode(extensions.digest(p_data::text,'sha256'),'hex'),btrim(p_data->>'buyerName'),mail,buyer,case when confirmed then 'confirmed' when p_data->>'intent'='reserve' then 'reserved' else 'holding' end,expires,subtotal,discount,subtotal-discount,c.id,s.questions,purpose.id,s.receiving_unit,s.created_by,receiver,to_jsonb(purpose)) returning * into o;
  for line in select value from jsonb_array_elements(p_data->'items') loop
   select * into t from private.event_ticket_types where id=(line->>'type')::uuid;
   insert into private.event_ticket_items(order_id,event_id,type_id,type_name,price,name,email,cpf,phone,answers) values(o.id,e.id,t.id,t.name,t.price,btrim(line->>'name'),lower(btrim(line->>'email')),regexp_replace(line->>'cpf','[^0-9]','','g'),line->>'phone',line->'answers');
  end loop;
  if o.state in('confirmed','reserved') then return private.event_ticket_order_view(o);end if;
 end if;
 -- One durable provider attempt per order; no second POST after an ambiguous result.
 if o.state<>'holding' and o.state<>'reserved' or o.expires_at<=clock_timestamp() or e.status<>'published' or e.starts_at<=clock_timestamp() then raise exception 'event_ticket_closed' using errcode='40001';end if;
 if o.finance_order is null then
  select * into purpose from private.finance_purposes where id=o.purpose_id and organization_id=e.organization_id and unit_id=o.receiving_unit and origin='event' and active for share;
  receiver:=private.member_payment_receiver(e.organization_id,o.receiving_unit,purpose.id);
  if receiver is null or receiver is distinct from o.receiver_id or not private.receiver_actor_allowed(o.financial_actor,e.organization_id,o.receiving_unit) then raise exception 'event_ticket_payment_unavailable' using errcode='42501';end if;
  insert into private.finance_digital_orders(id,organization_id,unit_id,purpose_id,receiver_id,environment,gross,party_name,source_reference,classification,created_by) values(o.id,e.organization_id,o.receiving_unit,purpose.id,receiver,'production',o.total,o.buyer_name,'event-ticket:'||o.id::text,o.classification,o.financial_actor);
  update private.event_ticket_orders set finance_order=o.id,state='holding',expires_at=least(o.expires_at,clock_timestamp()+interval '30 minutes'),updated_at=clock_timestamp() where id=o.id returning * into o;
 end if;
 return private.event_ticket_order_view(o)||jsonb_build_object('paymentRequired',true);
end $$;
revoke all on function private.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function private.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text) to service_role;
create function public.event_ticket_checkout(p_event uuid,p_action text,p_id uuid default null,p_actor uuid default null,p_proof text default '',p_data jsonb default '{}',p_network text default '') returns jsonb language sql security invoker set search_path='' as $$select private.event_ticket_checkout(p_event,p_action,p_id,p_actor,p_proof,p_data,p_network)$$;
revoke all on function public.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text) to service_role;

create function private.event_ticket_delivery(p_id uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.event_ticket_orders;f private.finance_digital_orders;r private.finance_receivers;e private.church_app_events;claimed boolean:=false;
begin
 select * into o from private.event_ticket_orders where id=p_id;if not found or o.finance_order is null then raise exception 'event_ticket_payment_unavailable' using errcode='42501';end if;
 perform 1 from public.organizations where id=o.organization_id for no key update;
 select * into e from private.church_app_events where id=o.event_id for update;
 select * into o from private.event_ticket_orders where id=p_id for update;
 select * into f from private.finance_digital_orders where id=o.finance_order;
 select * into r from private.finance_receivers where id=f.receiver_id for share;
 if p_action='claim' then
  if o.state<>'holding' or o.expires_at<=clock_timestamp() or e.status<>'published' or e.starts_at<=clock_timestamp() or exists(select 1 from private.finance_digital_receipts where order_id=f.id) or not private.receiver_actor_allowed(o.financial_actor,o.organization_id,f.unit_id) or not private.receiver_actor_allowed(r.created_by,o.organization_id,r.unit_id) or private.member_payment_receiver(o.organization_id,f.unit_id,f.purpose_id) is distinct from r.id then raise exception 'event_ticket_payment_unavailable' using errcode='42501';end if;
  if o.checkout_state='reserved' then update private.event_ticket_orders set checkout_state='dispatching',updated_at=clock_timestamp() where id=o.id;claimed:=true;end if;
  return jsonb_build_object('id',o.id,'order',f.id,'receiver',r.id,'org',o.organization_id,'unit',f.unit_id,'gross',o.total::text,'title',e.title,'name',o.buyer_name,'email',o.buyer_email,'expiresAt',o.expires_at,'state',case when claimed then 'dispatching' when o.checkout_state='dispatching' then 'in_progress' else o.checkout_state end,'checkoutUrl',case when o.checkout_state='ready' then o.checkout_url end);
 elsif p_action='complete' then
  if o.checkout_state<>'dispatching' or p_data-array['preference','url']<>'{}' or coalesce(p_data->>'preference','')!~'^[A-Za-z0-9_-]{1,200}$' or coalesce(p_data->>'url','')!~'^https://(www[.])?mercadopago[.]com[.]br/checkout/v1/redirect[?]pref_id=[A-Za-z0-9_-]+$' or split_part(p_data->>'url','pref_id=',2)<>p_data->>'preference' then raise exception 'event_ticket_payment_proof' using errcode='22023';end if;
  update private.event_ticket_orders set checkout_state='ready',preference_id=p_data->>'preference',checkout_url=p_data->>'url',updated_at=clock_timestamp() where id=o.id;
 elsif p_action='uncertain' then
  update private.event_ticket_orders set checkout_state='uncertain',updated_at=clock_timestamp() where id=o.id and checkout_state='dispatching';
 else raise exception 'invalid_event_ticket' using errcode='22023';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_ticket_delivery(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.event_ticket_delivery(uuid,text,jsonb) to service_role;
create function public.event_ticket_delivery(p_id uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_ticket_delivery(p_id,p_action,p_data)$$;
revoke all on function public.event_ticket_delivery(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.event_ticket_delivery(uuid,text,jsonb) to service_role;

create function private.event_ticket_payment_apply() returns trigger language plpgsql security definer set search_path='' as $$
declare o private.event_ticket_orders;e private.church_app_events;i record;paid boolean;c private.event_ticket_coupons;
begin
 select * into o from private.event_ticket_orders where finance_order=new.order_id;if not found then return new;end if;
 select * into e from private.church_app_events where id=o.event_id for update;
 select * into o from private.event_ticket_orders where id=o.id for update;
 paid:=new.snapshot->>'state'='approved' and (new.snapshot->>'gross')::bigint=o.total and coalesce((new.snapshot->>'refunded')::bigint,0)=0;
 if not coalesce(paid,false) then
  if new.snapshot->>'state' in('pending','processing') and o.state<>'confirmed' then return new;end if;
  update private.event_ticket_orders set state=case when new.snapshot->>'state' in('refunded','rejected','cancelled','expired') then 'cancelled' else 'payment_review' end,updated_at=clock_timestamp() where id=o.id;return new;
 end if;
 if o.state='confirmed' then return new;end if;
 if o.state='cancelled' or e.status<>'published' or e.starts_at<=clock_timestamp() or private.event_ticket_used(e.id,null,o.id)+(select count(*) from private.event_ticket_items where order_id=o.id)>e.capacity then
  update private.event_ticket_orders set state='payment_review',updated_at=clock_timestamp() where id=o.id;return new;
 end if;
 for i in select it.type_id,count(*) n from private.event_ticket_items it where it.order_id=o.id group by it.type_id loop
  if exists(select 1 from private.event_ticket_types t where t.id=i.type_id and (not private.event_ticket_audience(o.user_id,o.organization_id,t) or t.quantity is not null and private.event_ticket_used(e.id,t.id,o.id)+i.n>t.quantity)) then update private.event_ticket_orders set state='payment_review',updated_at=clock_timestamp() where id=o.id;return new;end if;
 end loop;
 -- Revalidate expired holds against the limits used by checkout, without moving financial facts.
 if exists(select 1 from private.event_ticket_items self join private.event_ticket_types t on t.id=self.type_id where self.order_id=o.id and (t.per_user is not null and (select count(*) from private.event_ticket_items x join private.event_ticket_orders z on z.id=x.order_id where x.type_id=t.id and (z.buyer_key=o.buyer_key or o.user_id is not null and z.user_id=o.user_id) and (z.id=o.id or z.state='confirmed' or z.state in('holding','reserved') and z.expires_at>clock_timestamp()))>t.per_user or t.per_cpf is not null and (select count(*) from private.event_ticket_items x join private.event_ticket_orders z on z.id=x.order_id where x.type_id=t.id and x.cpf=self.cpf and (z.id=o.id or z.state='confirmed' or z.state in('holding','reserved') and z.expires_at>clock_timestamp()))>t.per_cpf)) then update private.event_ticket_orders set state='payment_review' where id=o.id;return new;end if;
 if o.coupon_id is not null then
  select * into c from private.event_ticket_coupons where id=o.coupon_id;
  if c.usage_limit is not null and (select count(*) from private.event_ticket_orders z where z.coupon_id=c.id and (z.id=o.id or z.state='confirmed' or z.state in('holding','reserved') and z.expires_at>clock_timestamp()))>c.usage_limit or c.once_per_buyer and exists(select 1 from private.event_ticket_orders z where z.id<>o.id and z.coupon_id=c.id and (z.buyer_key=o.buyer_key or o.user_id is not null and z.user_id=o.user_id) and (z.state='confirmed' or z.state in('holding','reserved') and z.expires_at>clock_timestamp())) then update private.event_ticket_orders set state='payment_review' where id=o.id;return new;end if;
 end if;
 update private.event_ticket_orders set state='confirmed',updated_at=clock_timestamp() where id=o.id;
 return new;
end $$;
revoke all on function private.event_ticket_payment_apply() from public,anon,authenticated,service_role;
create trigger event_ticket_payment_verified after insert or update of snapshot on private.finance_digital_receipts for each row execute function private.event_ticket_payment_apply();

create function private.event_ticket_legacy_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.event_ticket_settings where event_id=new.event_id and enabled) then raise exception 'event_ticket_checkout_required' using errcode='40001';end if;return new;
end $$;
revoke all on function private.event_ticket_legacy_guard() from public,anon,authenticated,service_role;
create trigger event_ticket_legacy_registration before insert on private.church_app_registrations for each row execute function private.event_ticket_legacy_guard();
create trigger event_ticket_legacy_paid before insert on private.member_event_orders for each row execute function private.event_ticket_legacy_guard();

create function private.event_ticket_capacity_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.capacity<private.event_ticket_used(new.id) then raise exception 'event_ticket_quantity' using errcode='40001';end if;return new;
end $$;
revoke all on function private.event_ticket_capacity_guard() from public,anon,authenticated,service_role;
create trigger event_ticket_capacity before update of capacity on private.church_app_events for each row execute function private.event_ticket_capacity_guard();

create or replace function member_app_api.agenda(p_org uuid,p_unit uuid,p_past boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_event_enabled(p_org,p_unit) then return jsonb_build_object('unitId',p_unit,'available',false,'items','[]'::jsonb);end if;
 return jsonb_build_object('unitId',p_unit,'available',true,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from(
  select e.id,e.title,e.description,e.kind,e.starts_at,e.ends_at,e.location,e.address,e.capacity,e.status,e.version,(e.unit_id<>p_unit) as shared,exists(select 1 from private.event_ticket_settings ts where ts.event_id=e.id and ts.enabled) as has_tickets,'/eventos/e-'||e.id::text as public_path,coalesce(price.amount,0)::text as price_cents,
  greatest(0,e.capacity-private.event_ticket_used(e.id)-(select count(*) from private.church_app_registrations r where r.event_id=e.id and r.status='confirmed')-(select count(*) from private.member_event_orders o where o.event_id=e.id and o.state='holding' and o.expires_at>now())) as remaining
  from private.church_app_events e left join private.member_event_prices price on price.event_id=e.id where e.organization_id=p_org and (e.unit_id=p_unit and not exists(select 1 from private.event_information info where info.event_id=e.id) or exists(select 1 from private.event_information info where info.event_id=e.id and p_unit=any(info.targets)) and private.member_event_enabled(p_org,e.unit_id)) and e.status in('published','cancelled')
  and case when p_past then e.ends_at<now() and e.ends_at>now()-interval '1 year' else e.ends_at>=now() end order by e.starts_at limit 100)x),'[]'));
end $$;
create function member_app_api.event_ticket_orders(p_org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<now())) then raise exception 'event_ticket_login' using errcode='42501';end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(private.event_ticket_order_view(q)||jsonb_build_object('title',e.title,'starts',e.starts_at,'eventStatus',e.status)) from (select * from private.event_ticket_orders where user_id=auth.uid() and organization_id=p_org order by created_at desc limit 100)q join private.church_app_events e on e.id=q.event_id),'[]'));
end $$;
revoke all on function member_app_api.event_ticket_orders(uuid) from public,anon,service_role;
grant execute on function member_app_api.event_ticket_orders(uuid) to authenticated;
create function public.member_event_ticket_orders(p_org uuid) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.event_ticket_orders(p_org)$$;
revoke all on function public.member_event_ticket_orders(uuid) from public,anon,service_role;
grant execute on function public.member_event_ticket_orders(uuid) to authenticated;

create or replace function private.member_event_purchase(p_org uuid,p_unit uuid,p_action text,p_id uuid,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare person uuid;e private.church_app_events;price private.member_event_prices;existing private.member_event_orders;result jsonb;amount bigint;
begin
 person:=private.community_identity(p_org,p_unit,p_action='buy');
 if not private.member_event_enabled(p_org,p_unit) then raise exception 'member_event_closed' using errcode='42501';end if;
 if p_action='prices' then return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.event_id,'amount',p.amount::text,'title',evt.title,'starts_at',evt.starts_at)) from private.member_event_prices p join private.church_app_events evt on evt.id=p.event_id where p.organization_id=p_org and p.unit_id=p_unit and evt.status='published' and not exists(select 1 from private.event_ticket_settings s where s.event_id=evt.id and s.enabled)),'[]'),'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.order_id,'event',o.event_id,'state',o.state,'expires',o.expires_at)) from private.member_event_orders o join private.church_app_events evt on evt.id=o.event_id where evt.organization_id=p_org and o.user_id=auth.uid()),'[]'));end if;
 select * into e from private.church_app_events where id=p_id and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'member_event_closed' using errcode='42501';end if;
 if p_action='price' then
  if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'member_event_closed' using errcode='42501';end if;
  if e.status<>'draft' or exists(select 1 from private.church_app_registrations where event_id=e.id) or exists(select 1 from private.member_event_orders where event_id=e.id) then raise exception 'member_event_changed' using errcode='40001';end if;
  amount:=(p_data->>'amount')::bigint;
  if amount=0 then delete from private.member_event_prices where event_id=e.id;
  else
   if private.member_payment_receiver(p_org,p_unit,(p_data->>'purpose')::uuid) is null or not exists(select 1 from private.finance_purposes where id=(p_data->>'purpose')::uuid and origin='event') then raise exception 'member_payment_not_configured' using errcode='42501';end if;
   insert into private.member_event_prices values(e.id,p_org,p_unit,(p_data->>'purpose')::uuid,amount) on conflict(event_id) do update set purpose_id=excluded.purpose_id,amount=excluded.amount;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.event.price','church_app_event',e.id::text,jsonb_build_object('unit',p_unit,'amount',amount));
  update private.church_app_events set version=version+1,updated_at=clock_timestamp() where id=e.id;
  return jsonb_build_object('ok',true);
 elsif p_action<>'buy' then raise exception 'invalid_service' using errcode='22023';end if;
 select * into existing from private.member_event_orders where event_id=e.id and user_id=auth.uid();
 if found then return jsonb_build_object('ok',true,'order',existing.order_id,'state',existing.state);end if;
 if e.status<>'published' or e.starts_at<=now() then raise exception 'member_event_closed' using errcode='40001';end if;
 select * into price from private.member_event_prices where event_id=e.id;
 if not found then raise exception 'member_event_free' using errcode='22023';end if;
 if exists(select 1 from private.church_app_registrations where event_id=e.id and user_id=auth.uid() and status='confirmed') then raise exception 'member_event_changed' using errcode='40001';end if;
 if (select count(*) from private.church_app_registrations where event_id=e.id and status='confirmed')+(select count(*) from private.member_event_orders where event_id=e.id and state='holding' and expires_at>now())>=e.capacity then raise exception 'member_event_full' using errcode='40001';end if;
 result:=private.member_payments(p_org,p_unit,'create',jsonb_build_object('id',(p_data->>'id')::uuid,'purpose',price.purpose_id,'amount',price.amount::text));
 update private.church_app_events set commerce_version=commerce_version+1 where id=e.id;
 insert into private.member_event_orders(order_id,event_id,user_id) values((result->>'order')::uuid,e.id,auth.uid());
 return result;
end $$;

create or replace function private.programming_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;e private.church_app_events;i uuid;profile jsonb;before_ids uuid[];old_events jsonb;old_profile jsonb;anchor timestamptz;delta interval;
begin
 perform private.community_identity(p_org,p_unit,false);
 if p_action not in('list','detail','categories') then perform 1 from public.organizations where id=p_org for no key update;end if;
 if p_action in('create','edit') and p_data ? 'information' then
  if p_action='create' then perform pg_advisory_xact_lock(hashtextextended(p_org::text||p_unit::text||auth.uid()::text||p_id::text,0));if exists(select 1 from private.programming_requests r where r.organization_id=p_org and r.unit_id=p_unit and r.actor_id=auth.uid() and r.request_id=p_id and r.information_payload is not null and r.information_payload is distinct from p_data) then raise exception 'member_event_changed' using errcode='40001';end if;select array_agg((value#>>'{}')::uuid) into before_ids from jsonb_array_elements(coalesce((select r.result->'ids' from private.programming_requests r where r.organization_id=p_org and r.unit_id=p_unit and r.actor_id=auth.uid() and r.request_id=p_id),'[]'));end if;
  if p_action='edit' then select jsonb_object_agg(id::text,jsonb_build_object('starts',starts_at,'information',(select info from private.event_information where event_id=e0.id))) into old_events from private.church_app_events e0 where organization_id=p_org and unit_id=p_unit;end if;
  anchor:=(p_data->>'startsLocal')::timestamp at time zone 'America/Sao_Paulo';
  result:=private.programming_admin_base_20261103(p_org,p_unit,p_action,p_id,p_version,(p_data-'information')||case when p_data->>'cover'~'^/api/event-images/[0-9a-f-]{36}$' then jsonb_build_object('cover','') else '{}'::jsonb end);
  for i in select value::uuid from jsonb_array_elements_text(result->'ids') loop
   if before_ids is not null then null;
   else
    select * into e from private.church_app_events where id=i;
    profile:=p_data->'information';
    if p_action='edit' then
     old_profile:=old_events->i::text->'information';
     if old_profile is not null and old_profile<>'null'::jsonb then
      profile:=profile||jsonb_build_object('schedule',old_profile->'schedule','guests',old_profile->'guests','contacts',old_profile->'contacts','gallery',old_profile->'gallery','team',old_profile->'team');
     end if;
     delta:=e.starts_at-(old_events->i::text->>'starts')::timestamptz;
    else delta:=e.starts_at-anchor;end if;
    profile:=jsonb_set(profile,'{schedule}',coalesce((select jsonb_agg(x||jsonb_build_object('starts',(x->>'starts')::timestamptz+delta,'ends',(x->>'ends')::timestamptz+delta)) from jsonb_array_elements(profile->'schedule')x),'[]'));
    if p_data->>'cover'~'^/api/event-images/[0-9a-f-]{36}$' then update private.church_app_events set cover_url=p_data->>'cover' where id=i;end if;
    perform private.save_event_information(p_org,p_unit,i,profile);
   end if;
  end loop;if p_action='create' then update private.programming_requests set information_payload=p_data where organization_id=p_org and unit_id=p_unit and actor_id=auth.uid() and request_id=p_id;end if;return result;
 end if;
 result:=private.programming_admin_base_20261103(p_org,p_unit,p_action,p_id,p_version,p_data);
 if p_action='list' and result ? 'items' then result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(x||jsonb_build_object('has_tickets',exists(select 1 from private.event_ticket_settings where event_id=(x->>'id')::uuid and enabled),'registrations',coalesce((x->>'registrations')::integer,0)+private.event_ticket_used((x->>'id')::uuid))) from jsonb_array_elements(result->'items')x),'[]'));end if;
 if p_action='detail' then return result||jsonb_build_object('event',(result->'event')||jsonb_build_object('has_tickets',exists(select 1 from private.event_ticket_settings where event_id=p_id and enabled),'ticket_occupied',private.event_ticket_used(p_id)),'information',(select info from private.event_information where event_id=p_id),'publicPath','/eventos/e-'||p_id::text);end if;
 if p_action='publish' then
  for i in select value::uuid from jsonb_array_elements_text(result->'ids') loop
   select * into e from private.church_app_events where id=i;select info into profile from private.event_information where event_id=i;
   if profile is not null then
    if profile->'venue'->>'format' in('presential','hybrid') and (length(btrim(profile->'venue'->>'street'))=0 or length(btrim(profile->'venue'->>'number'))=0 or length(btrim(profile->'venue'->>'city'))=0 or length(btrim(profile->'venue'->>'state'))=0) or profile->'venue'->>'format' in('online','hybrid') and coalesce(profile->'venue'->>'onlineUrl','')='' then raise exception 'invalid_event_information' using errcode='22023';end if;
    perform private.save_event_information(p_org,p_unit,i,profile);
   end if;
  end loop;
 end if;
 return result;
end $$;

create or replace function private.event_information_admin(p_org uuid,p_unit uuid,p_action text,p_event uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;p private.event_information;manager boolean;result jsonb;
begin
 perform private.community_identity(p_org,p_unit,false);if p_action='save' then perform 1 from public.organizations where id=p_org for no key update;end if;manager:=private.event_manager(p_org,p_unit);
 if p_action='choices' then
  if not manager then raise exception 'member_agenda_denied' using errcode='42501';end if;
  return jsonb_build_object('units',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'address',u.address,'phone',u.phone,'email',u.email,'canPublish',private.event_manager(p_org,u.id)) order by u.name) from public.organization_units u where u.organization_id=p_org and u.status='active' and private.can_access_unit(p_org,u.id,array['read','manage','admin']::public.unit_access_level[])),'[]'),
   'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'targets',g.targets,'version',g.version)) from private.publishing_groups g where g.organization_id=p_org and active and not exists(select 1 from unnest(g.targets)t where not private.event_manager(p_org,t))),'[]'),
   'users',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',coalesce(person.full_name,'Usuário confirmado'))) from public.organization_memberships m join auth.users u on u.id=m.user_id left join public.people person on person.auth_user_id=m.user_id and person.organization_id=m.organization_id where m.organization_id=p_org and m.status='active' and u.email_confirmed_at is not null and (m.default_unit_id=p_unit or m.role in('owner','admin','pastor') or exists(select 1 from public.membership_unit_access a where a.membership_id=m.id and a.unit_id=p_unit))),'[]'));
 end if;
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;
 select * into p from private.event_information where event_id=p_event;
 if e.id is null or not manager and not (coalesce(p.info->'team','[]') ? auth.uid()::text) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_action='preview' then
  if not manager then raise exception 'member_agenda_denied' using errcode='42501';end if;
  return jsonb_build_object('preview',true,'event',jsonb_build_object('id',e.id,'title',e.title,'description',e.description,'starts_at',e.starts_at,'ends_at',e.ends_at,'location',e.location,'address',e.address,'cover_url',e.cover_url,'unit',e.unit_id),'information',p.info-'team'-'scope'-'targets'-'group'-'groupVersion','church',(select jsonb_build_object('name',o.name,'slug',o.slug,'primary_color',o.primary_color,'accent_color',o.accent_color,'unit_name',u.name,'logo',coalesce((select logo_png from private.church_branding where scope_id=u.id),(select logo_png from private.church_branding where scope_id=o.id))) from public.organizations o join public.organization_units u on u.organization_id=o.id where o.id=p_org and u.id=p_unit));
 end if;
 if p_action='read' then return jsonb_build_object('event',to_jsonb(e),'information',p.info,'publicPath','/eventos/e-'||p_event::text,'canPublish',manager);end if;
 if p_action<>'save' or p_version is distinct from e.version or e.status='cancelled' then raise exception 'member_event_changed' using errcode='40001';end if;
 if not manager and (p_data-'schedule'-'guests'-'contacts'-'gallery') is distinct from (p.info-'schedule'-'guests'-'contacts'-'gallery') then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if manager then perform private.save_event_information(p_org,p_unit,p_event,p_data);
 else if not private.event_information_valid(p_data,e) then raise exception 'invalid_event_information' using errcode='22023';end if;if exists(select 1 from (select value#>>'{}' uri from jsonb_path_query(p_data,'$.gallery[*].url') q(value) union all select value#>>'{}' from jsonb_path_query(p_data,'$.guests[*].photo') q(value)) refs where uri like '/api/event-images/%' and not exists(select 1 from private.event_images a where a.id=substring(uri from 19)::uuid and a.organization_id=p_org and a.unit_id=p_unit and ready)) then raise exception 'invalid_event_image' using errcode='22023';end if;update private.event_information set info=p_data,updated_at=clock_timestamp() where event_id=p_event;end if;
 update private.church_app_events set version=version+1,updated_at=clock_timestamp() where id=p_event;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'event.information.save','church_app_event',p_event::text);
 return jsonb_build_object('ok',true);
end $$;

create or replace function member_app_api.event_page(p_event uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.church_app_events;d jsonb;
begin
 select * into e from private.church_app_events where id=p_event and status='published';
 if e.id is null or not private.member_event_enabled(e.organization_id,e.unit_id) then return null;end if;
 select info-'team'-'group'-'groupVersion'-'targets'-'scope' into d from private.event_information where event_id=e.id;
 return jsonb_build_object('event',jsonb_build_object('has_tickets',exists(select 1 from private.event_ticket_settings where event_id=e.id and enabled),'id',e.id,'title',e.title,'description',e.description,'starts_at',e.starts_at,'ends_at',e.ends_at,'location',e.location,'address',e.address,'cover_url',e.cover_url,'unit',e.unit_id),'information',d,
 'church',(select jsonb_build_object('name',o.name,'slug',o.slug,'primary_color',o.primary_color,'accent_color',o.accent_color,'unit_name',u.name,'logo',coalesce((select logo_png from private.church_branding where scope_id=u.id),(select logo_png from private.church_branding where scope_id=o.id))) from public.organizations o join public.organization_units u on u.organization_id=o.id where o.id=e.organization_id and u.id=e.unit_id));
end $$;

create index event_ticket_settings_creator on private.event_ticket_settings(created_by);
create index event_ticket_settings_purpose on private.event_ticket_settings(purpose_id);
create index event_ticket_settings_receiving on private.event_ticket_settings(receiving_unit,organization_id);
create index event_ticket_orders_financial_actor on private.event_ticket_orders(financial_actor);
create index event_ticket_orders_receiver on private.event_ticket_orders(receiver_id);
create index event_ticket_orders_purpose on private.event_ticket_orders(purpose_id);
create index event_ticket_orders_receiving on private.event_ticket_orders(receiving_unit);
notify pgrst,'reload schema';
