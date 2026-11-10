set local lock_timeout='5s';

-- Private device registry: an installation belongs to one authenticated account.
create table private.member_push_apps(
 organization_id uuid primary key references public.organizations(id), project_id uuid not null,
 application_id text not null check(application_id ~ '^[A-Za-z][A-Za-z0-9_.]{2,150}$'),
 enabled boolean not null default false, updated_at timestamptz not null default now()
);
create table private.member_push_devices(
 id uuid primary key,organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id),unit_id uuid not null,
 token text not null unique check(token ~ '^(ExponentPushToken|ExpoPushToken)\[[A-Za-z0-9_-]{10,200}\]$'),
 enabled boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index member_push_devices_org on private.member_push_devices(organization_id,user_id);
create index member_push_devices_user on private.member_push_devices(user_id);
create index member_push_devices_unit on private.member_push_devices(unit_id,organization_id);
create table private.member_push_deliveries(
 id uuid primary key default extensions.gen_random_uuid(),device_id uuid not null references private.member_push_devices(id),
 message_key text not null, state text not null default 'queued' check(state in('queued','sending','submitted','delivered','failed','uncertain','cancelled')),
 ticket text,attempts integer not null default 0,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(device_id,message_key)
);
create index member_push_deliveries_queue on private.member_push_deliveries(state,updated_at);
create table private.member_digital_cards(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 person_id uuid not null,category text not null check(length(btrim(category)) between 2 and 80),
 token uuid not null unique default extensions.gen_random_uuid(),expires_on date not null,
 revoked boolean not null default false,version integer not null default 1,created_at timestamptz not null default now(),
 issued_by uuid not null references auth.users(id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create index member_digital_cards_org on private.member_digital_cards(organization_id,unit_id,created_at desc);
create index member_digital_cards_unit on private.member_digital_cards(unit_id,organization_id);
create index member_digital_cards_person on private.member_digital_cards(person_id,organization_id);
create index member_digital_cards_issuer on private.member_digital_cards(issued_by);
alter table private.member_push_apps enable row level security;
alter table private.member_push_devices enable row level security;
alter table private.member_push_deliveries enable row level security;
alter table private.member_digital_cards enable row level security;
revoke all on private.member_push_apps,private.member_push_devices,private.member_push_deliveries,private.member_digital_cards from public,anon,authenticated,service_role;

create function private.member_services(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare person uuid;app private.member_push_apps;device private.member_push_devices;result jsonb;uid uuid;
begin
 person:=private.community_identity(p_org,p_unit,p_action='cards');
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>4096 then raise exception 'invalid_service' using errcode='22023';end if;
 if p_action='cards' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('ministry',(select name from public.organizations where id=p_org),'primary',(select primary_color from public.organizations where id=p_org),'logo',coalesce((select logo_png from private.church_branding where scope_id=c.unit_id),(select logo_png from private.church_branding where scope_id=p_org)),'id',c.id,'category',c.category,'name',p.full_name,'unit',u.name,'expires',c.expires_on,'valid',not c.revoked and c.expires_on>=current_date and p.status='active' and p.unit_id=c.unit_id,'code',case when not c.revoked and c.expires_on>=current_date and p.status='active' and p.unit_id=c.unit_id then c.token end) order by c.created_at desc)
  from private.member_digital_cards c join public.people p on p.id=c.person_id join public.organization_units u on u.id=c.unit_id where c.organization_id=p_org and c.person_id=person),'[]'));
 elsif p_action='push_status' then
  select * into app from private.member_push_apps where organization_id=p_org;
  return jsonb_build_object('configured',coalesce(app.enabled,false),'project',app.project_id,'application',app.application_id,'devices',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'enabled',d.enabled,'updated',d.updated_at)) from private.member_push_devices d where d.organization_id=p_org and d.user_id=auth.uid()),'[]'));
 elsif p_action='push_follow' then
  update private.member_push_devices set unit_id=p_unit,updated_at=clock_timestamp() where id=(p_data->>'id')::uuid and user_id=auth.uid() and organization_id=p_org and enabled;
 elsif p_action='push_disable' then
  if p_data-array['id']<>'{}' then raise exception 'invalid_service' using errcode='22023';end if;
  update private.member_push_devices set enabled=false,token=null,updated_at=clock_timestamp() where organization_id=p_org and user_id=auth.uid() and id=(p_data->>'id')::uuid;
  update private.member_push_deliveries set state='cancelled',updated_at=clock_timestamp() where device_id=(p_data->>'id')::uuid and state='queued' and exists(select 1 from private.member_push_devices d where d.id=device_id and d.user_id=auth.uid() and d.organization_id=p_org);
 elsif p_action='push_register' then
  if p_data-array['id','token','project','application']<>'{}' or p_unit is null or coalesce(p_data->>'token','')!~'^(ExponentPushToken|ExpoPushToken)\[[A-Za-z0-9_-]{10,200}\]$' then raise exception 'invalid_service' using errcode='22023';end if;
  select * into app from private.member_push_apps where organization_id=p_org and enabled for share;
  if not found or app.project_id::text is distinct from p_data->>'project' or app.application_id is distinct from p_data->>'application' then raise exception 'push_not_configured' using errcode='42501';end if;
  uid:=(p_data->>'id')::uuid;
  select * into device from private.member_push_devices where id=uid or token=p_data->>'token' for update;
  if found and (device.user_id<>auth.uid() or device.organization_id<>p_org or device.id<>uid) then raise exception 'push_device_conflict' using errcode='40001';end if;
  if (select count(*) from private.member_push_devices where organization_id=p_org and user_id=auth.uid())>=10 and device.id is null then raise exception 'push_device_limit' using errcode='22023';end if;
  insert into private.member_push_devices(id,organization_id,user_id,unit_id,token) values(uid,p_org,auth.uid(),p_unit,p_data->>'token')
   on conflict(id) do update set token=excluded.token,unit_id=excluded.unit_id,enabled=true,updated_at=clock_timestamp();
 else raise exception 'invalid_service' using errcode='22023';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.member_services(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.member_services(uuid,uuid,text,jsonb) to authenticated;
create function public.member_services(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_services(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.member_services(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.member_services(uuid,uuid,text,jsonb) to authenticated;

create function private.member_services_admin(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid;c private.member_digital_cards;person public.people;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'services_admin_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>4096 then raise exception 'invalid_service' using errcode='22023';end if;
 if p_action='list' then return jsonb_build_object('events',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',title)) from private.church_app_events where organization_id=p_org and unit_id=p_unit and status='draft'),'[]'),'people',coalesce((select jsonb_agg(to_jsonb(q)) from(select id,full_name as name from public.people where organization_id=p_org and unit_id=p_unit and status='active' order by full_name limit 1000)q),'[]'),'purposes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from private.finance_purposes where organization_id=p_org and unit_id=p_unit and active),'[]'),'receivers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',holder)) from private.finance_receivers where organization_id=p_org and p_unit=any(beneficiary_units) and status='configured'),'[]'),'cards',coalesce((select jsonb_agg(to_jsonb(q)) from(select cardrow.id,cardrow.person_id,p.full_name as name,cardrow.category,cardrow.expires_on,cardrow.revoked,cardrow.version from private.member_digital_cards cardrow join public.people p on p.id=cardrow.person_id where cardrow.organization_id=p_org and cardrow.unit_id=p_unit order by cardrow.created_at desc limit 100)q),'[]'),'push',(select jsonb_build_object('project',project_id,'application',application_id,'enabled',enabled) from private.member_push_apps where organization_id=p_org));
 elsif p_action='issue' then
  if p_data-array['person','category','expires']<>'{}' or coalesce(length(btrim(p_data->>'category')),0) not between 2 and 80 or (p_data->>'expires')::date not between current_date and current_date+1095 then raise exception 'invalid_service' using errcode='22023';end if;
  select * into person from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and unit_id=p_unit and status='active' for share;
  if not found then raise exception 'card_person_unavailable' using errcode='42501';end if;
  insert into private.member_digital_cards(organization_id,unit_id,person_id,category,expires_on,issued_by) values(p_org,p_unit,person.id,btrim(p_data->>'category'),(p_data->>'expires')::date,auth.uid()) returning id into uid;
 elsif p_action='revoke' then
  select * into c from private.member_digital_cards where id=(p_data->>'id')::uuid and organization_id=p_org and unit_id=p_unit for update;
  if not found or c.version is distinct from (p_data->>'version')::integer then raise exception 'card_changed' using errcode='40001';end if;
  update private.member_digital_cards set revoked=true,version=version+1 where id=c.id;uid:=c.id;
 elsif p_action='verify' then
  select * into c from private.member_digital_cards where token=(p_data->>'code')::uuid and organization_id=p_org and unit_id=p_unit;
  return jsonb_build_object('valid',c.id is not null and not c.revoked and c.expires_on>=current_date and exists(select 1 from public.people p where p.id=c.person_id and p.status='active' and p.unit_id=c.unit_id),'category',c.category,'expires',c.expires_on);
 else raise exception 'invalid_service' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.services.'||p_action,'digital_card',uid::text,jsonb_build_object('unit',p_unit));
 return jsonb_build_object('ok',true,'id',uid);
end $$;
revoke all on function private.member_services_admin(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.member_services_admin(uuid,uuid,text,jsonb) to authenticated;
create function public.member_services_admin(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_services_admin(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.member_services_admin(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.member_services_admin(uuid,uuid,text,jsonb) to authenticated;

-- A published purpose explicitly selects its receiving account; the payer cannot redirect it.
create table private.member_payment_catalog(
 purpose_id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 receiver_id uuid not null references private.finance_receivers(id),published boolean not null default false,
 foreign key(purpose_id,organization_id,unit_id) references private.finance_purposes(id,organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index member_payment_catalog_org on private.member_payment_catalog(organization_id,unit_id);
create index member_payment_catalog_unit on private.member_payment_catalog(unit_id,organization_id);
create index member_payment_catalog_receiver on private.member_payment_catalog(receiver_id);
create table private.member_payment_orders(
 order_id uuid primary key references private.finance_digital_orders(id),user_id uuid not null references auth.users(id),
 organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index member_payment_orders_user on private.member_payment_orders(user_id,organization_id);
create index member_payment_orders_org on private.member_payment_orders(organization_id,unit_id);
create index member_payment_orders_unit on private.member_payment_orders(unit_id,organization_id);
alter table private.member_payment_catalog enable row level security;
alter table private.member_payment_orders enable row level security;
revoke all on private.member_payment_catalog,private.member_payment_orders from public,anon,authenticated,service_role;

create function private.member_payment_receiver(p_org uuid,p_unit uuid,p_purpose uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 select r.id into result from private.member_payment_catalog c
 join private.finance_purposes p on p.id=c.purpose_id and p.organization_id=c.organization_id and p.unit_id=c.unit_id and p.active
 join private.finance_receivers r on r.id=c.receiver_id and r.organization_id=c.organization_id and r.account_id=p.account_id
 where c.purpose_id=p_purpose and c.organization_id=p_org and c.unit_id=p_unit and c.published
 and r.environment='production' and r.provider='mercado_pago' and r.status='configured' and r.holder_confirmed and r.payments_enabled and r.webhook_configured and cardinality(r.methods)>0
 and r.expires_at>clock_timestamp() and p_unit=any(r.beneficiary_units) and private.receiver_actor_allowed(r.created_by,p_org,r.unit_id)
;
 return result;
end $$;
revoke all on function private.member_payment_receiver(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function private.member_payments(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare person uuid;p private.finance_purposes;r uuid;o private.finance_digital_orders;a private.finance_checkout_attempts;v_id uuid;amount bigint;mail text;full_name text;
begin
 person:=private.community_identity(p_org,p_unit,true);
 if p_unit is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>4096 then raise exception 'invalid_member_payment' using errcode='22023';end if;
 if p_action='list' then
  return jsonb_build_object('purposes',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'origin',x.origin)) from private.finance_purposes x where x.organization_id=p_org and x.unit_id=p_unit and x.active and x.origin<>'event' and private.member_payment_receiver(p_org,p_unit,x.id) is not null),'[]'),
  'orders',coalesce((select jsonb_agg(to_jsonb(q)) from(select ord.id,ord.unit_id,ord.gross::text as amount,ord.classification->>'name' as purpose,ord.created_at,coalesce(rec.snapshot->>'state','pending') as status,attempt.state as checkout_state,case when attempt.expires_at>now() and attempt.state='ready' and rec.id is null then attempt.checkout_url end as url
  from private.member_payment_orders m join private.finance_digital_orders ord on ord.id=m.order_id left join private.finance_digital_receipts rec on rec.order_id=ord.id left join private.finance_checkout_attempts attempt on attempt.order_id=ord.id where m.organization_id=p_org and m.user_id=auth.uid() order by ord.created_at desc limit 100)q),'[]'));
 elsif p_action not in('create','resume') then raise exception 'invalid_member_payment' using errcode='22023';end if;
 v_id:=(p_data->>'id')::uuid;
 select * into o from private.finance_digital_orders where finance_digital_orders.id=v_id for update;
 if found then
  if o.organization_id<>p_org or o.unit_id<>p_unit or not exists(select 1 from private.member_payment_orders m where m.order_id=v_id and m.user_id=auth.uid()) then raise exception 'member_payment_denied' using errcode='42501';end if;
  if p_action='create' and (o.purpose_id is distinct from (p_data->>'purpose')::uuid or o.gross is distinct from (p_data->>'amount')::bigint) then raise exception 'member_payment_conflict' using errcode='40001';end if;
 else
  if p_action='resume' then raise exception 'member_payment_denied' using errcode='42501';end if;
  if p_action<>'create' or p_data-array['id','purpose','amount']<>'{}' or coalesce(p_data->>'amount','')!~'^[1-9][0-9]{0,7}$' then raise exception 'invalid_member_payment' using errcode='22023';end if;
  amount:=(p_data->>'amount')::bigint;
  if amount not between 100 and 99999999 then raise exception 'invalid_member_payment' using errcode='22023';end if;
  if (select count(*) from private.member_payment_orders m join private.finance_digital_orders d on d.id=m.order_id where m.user_id=auth.uid() and m.organization_id=p_org and d.created_at>now()-interval '1 day')>=10 then raise exception 'member_payment_daily_limit' using errcode='22023';end if;
  select * into p from private.finance_purposes where finance_purposes.id=(p_data->>'purpose')::uuid and organization_id=p_org and unit_id=p_unit and active for share;
  r:=private.member_payment_receiver(p_org,p_unit,p.id);
  if r is null then raise exception 'member_payment_not_configured' using errcode='42501';end if;
  select people.full_name into full_name from public.people where people.id=person;
  insert into private.finance_digital_orders(id,organization_id,unit_id,purpose_id,receiver_id,environment,gross,person_id,party_name,source_reference,classification,created_by)
   values(v_id,p_org,p_unit,p.id,r,'production',amount,person,full_name,'member:'||v_id,to_jsonb(p),auth.uid()) returning * into o;
  insert into private.member_payment_orders values(v_id,auth.uid(),p_org,p_unit);
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.payment.create','finance_digital',v_id::text,jsonb_build_object('unit',p_unit));
 end if;
 if private.member_payment_receiver(p_org,p_unit,o.purpose_id) is distinct from o.receiver_id then raise exception 'member_payment_not_configured' using errcode='42501';end if;
 if exists(select 1 from private.finance_digital_receipts where order_id=v_id) then return jsonb_build_object('ok',true,'paidObserved',true,'order',v_id);end if;
 select email into mail from auth.users where auth.users.id=auth.uid();
 insert into private.finance_checkout_attempts(order_id,actor_id,payer_name,payer_email) values(v_id,auth.uid(),o.party_name,mail) on conflict(order_id) do nothing;
 select * into a from private.finance_checkout_attempts where order_id=v_id;
 return jsonb_build_object('ok',true,'order',v_id,'id',a.id,'receiver',o.receiver_id,'state',a.state,'expired',a.expires_at<=clock_timestamp());
end $$;
revoke all on function private.member_payments(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.member_payments(uuid,uuid,text,jsonb) to authenticated;
create function public.member_payments(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_payments(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.member_payments(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.member_payments(uuid,uuid,text,jsonb) to authenticated;

create function private.member_payment_publish(p_org uuid,p_unit uuid,p_purpose uuid,p_receiver uuid,p_published boolean) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) or not private.target_unit_module_enabled(p_org,p_unit,'finance') then raise exception 'member_payment_denied' using errcode='42501';end if;
 if p_published is null or not exists(select 1 from private.finance_purposes p join private.finance_receivers r on r.account_id=p.account_id and r.organization_id=p.organization_id where p.id=p_purpose and p.organization_id=p_org and p.unit_id=p_unit and r.id=p_receiver and p_unit=any(r.beneficiary_units)) then raise exception 'member_payment_destination' using errcode='22023';end if;
 insert into private.member_payment_catalog values(p_purpose,p_org,p_unit,p_receiver,p_published) on conflict(purpose_id) do update set receiver_id=excluded.receiver_id,published=excluded.published where member_payment_catalog.organization_id=p_org and member_payment_catalog.unit_id=p_unit;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.payment.publish','finance_purpose',p_purpose::text,jsonb_build_object('unit',p_unit,'published',p_published));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.member_payment_publish(uuid,uuid,uuid,uuid,boolean) from public,anon,service_role;
grant execute on function private.member_payment_publish(uuid,uuid,uuid,uuid,boolean) to authenticated;
create function public.member_payment_publish(p_org uuid,p_unit uuid,p_purpose uuid,p_receiver uuid,p_published boolean) returns jsonb language sql security invoker set search_path='' as $$select private.member_payment_publish(p_org,p_unit,p_purpose,p_receiver,p_published)$$;
revoke all on function public.member_payment_publish(uuid,uuid,uuid,uuid,boolean) from public,anon,service_role;
grant execute on function public.member_payment_publish(uuid,uuid,uuid,uuid,boolean) to authenticated;

alter table private.member_push_devices add column session_id uuid,add column polled_at timestamptz;
-- Service worker only: evaluate the existing private inbox for the registered identity.
create function private.member_push_work(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.member_push_devices;q private.member_push_deliveries;oldsub text:=current_setting('request.jwt.claim.sub',true);items jsonb:='[]';valid boolean;entry record;
begin
 if p_action='claim' then
  update private.member_push_deliveries set state='uncertain',updated_at=clock_timestamp() where state='sending' and updated_at<now()-interval '10 minutes';
  <<devices>>
  for d in select v.* from private.member_push_devices v join private.member_push_apps a on a.organization_id=v.organization_id and a.enabled
   where v.enabled and v.updated_at>now()-interval '30 days' order by v.polled_at nulls first,v.id limit 100 for update of v skip locked loop
   valid:=exists(select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id join public.organizations o on o.id=m.organization_id join public.organization_units unit on unit.id=d.unit_id and unit.organization_id=o.id
    where m.user_id=d.user_id and m.organization_id=d.organization_id and m.status='active' and o.status in('active','trial') and unit.status='active' and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<now()) and exists(select 1 from auth.sessions s where s.id=d.session_id and s.user_id=u.id and (s.not_after is null or s.not_after>now())));
   if valid then
    perform set_config('request.jwt.claim.sub',d.user_id::text,true);
    insert into private.member_push_deliveries(device_id,message_key)
     select d.id,n.message_key from private.member_inbox_rows(d.organization_id,d.unit_id)n
     where n.occurred_at>=d.created_at and n.occurred_at>now()-interval '1 day' and not exists(select 1 from private.member_inbox_reads r where r.organization_id=d.organization_id and r.user_id=d.user_id and r.message_key=n.message_key) on conflict do nothing;
    for q in select x.* from private.member_push_deliveries x where x.device_id=d.id and x.state='queued' and (x.attempts=0 or x.updated_at<now()-interval '10 minutes') order by x.created_at limit 5 for update skip locked loop
     if exists(select 1 from private.member_inbox_rows(d.organization_id,d.unit_id)n where n.message_key=q.message_key) then
      update private.member_push_deliveries set state='sending',attempts=attempts+1,updated_at=clock_timestamp() where id=q.id;
      items:=items||jsonb_build_array(jsonb_build_object('id',q.id,'token',d.token,'org',d.organization_id,'project',(select a.project_id from private.member_push_apps a where a.organization_id=d.organization_id)));
     else update private.member_push_deliveries set state='cancelled' where id=q.id;end if;
    end loop;
   else update private.member_push_devices set enabled=false where id=d.id;end if;
   update private.member_push_devices set polled_at=clock_timestamp() where id=d.id;
   exit devices when jsonb_array_length(items)>=20;
  end loop;
  perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);
  return jsonb_build_object('items',items);
 elsif p_action='receipts' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'ticket',x.ticket)) from(select * from private.member_push_deliveries where state='submitted' and updated_at<now()-interval '15 minutes' order by updated_at limit 100)x),'[]'));
 elsif p_action='settle' then
  select * into q from private.member_push_deliveries where id=(p_data->>'id')::uuid for update;
  if not found or q.state not in('sending','submitted') then return jsonb_build_object('ok',true);end if;
  if p_data->>'state' not in('queued','submitted','delivered','failed','uncertain') then raise exception 'invalid_push_state' using errcode='22023';end if;
  update private.member_push_deliveries set state=case when p_data->>'state'='queued' and attempts>=5 then 'failed' else p_data->>'state' end,ticket=coalesce(p_data->>'ticket',ticket),updated_at=clock_timestamp() where id=q.id;
  if p_data->>'error'='DeviceNotRegistered' then update private.member_push_devices set enabled=false where id=q.device_id;end if;
  return jsonb_build_object('ok',true);
 else raise exception 'invalid_push_action' using errcode='22023';end if;
end $$;
revoke all on function private.member_push_work(text,jsonb) from public,anon,authenticated;
grant execute on function private.member_push_work(text,jsonb) to service_role;
create function public.member_push_work(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_push_work(p_action,p_data)$$;
revoke all on function public.member_push_work(text,jsonb) from public,anon,authenticated;
grant execute on function public.member_push_work(text,jsonb) to service_role;

create function private.member_push_session_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if not new.enabled then return new;end if;
 new.session_id:=nullif(auth.jwt()->>'session_id','')::uuid;
 if new.session_id is null then raise exception 'push_session_required' using errcode='42501';end if;
 return new;
end $$;
revoke all on function private.member_push_session_guard() from public,anon,authenticated,service_role;
create trigger member_push_session before insert or update of token on private.member_push_devices for each row execute function private.member_push_session_guard();

alter table private.church_app_events add column commerce_version integer not null default 0;
create table private.member_event_prices(
 event_id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,purpose_id uuid not null,
 amount bigint not null check(amount between 100 and 99999999),
 foreign key(event_id,organization_id,unit_id) references private.church_app_events(id,organization_id,unit_id),
 foreign key(purpose_id,organization_id,unit_id) references private.finance_purposes(id,organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index member_event_prices_org on private.member_event_prices(organization_id,unit_id);
create index member_event_prices_unit on private.member_event_prices(unit_id,organization_id);
create index member_event_prices_purpose on private.member_event_prices(purpose_id,organization_id,unit_id);
create table private.member_event_orders(
 order_id uuid primary key references private.member_payment_orders(order_id),event_id uuid not null references private.church_app_events(id),
 user_id uuid not null references auth.users(id),expires_at timestamptz not null default now()+interval '30 minutes',
 state text not null default 'holding' check(state in('holding','confirmed','payment_review','cancelled')),registration_id uuid references private.church_app_registrations(id),
 unique(event_id,user_id)
);
create index member_event_orders_user on private.member_event_orders(user_id);
create index member_event_orders_registration on private.member_event_orders(registration_id);
alter table private.member_event_prices enable row level security;
alter table private.member_event_orders enable row level security;
revoke all on private.member_event_prices,private.member_event_orders from public,anon,authenticated,service_role;

create function private.member_event_purchase(p_org uuid,p_unit uuid,p_action text,p_id uuid,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare person uuid;e private.church_app_events;price private.member_event_prices;existing private.member_event_orders;result jsonb;amount bigint;
begin
 person:=private.community_identity(p_org,p_unit,p_action='buy');
 if not private.member_event_enabled(p_org,p_unit) then raise exception 'member_event_closed' using errcode='42501';end if;
 if p_action='prices' then return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.event_id,'amount',p.amount::text,'title',evt.title,'starts_at',evt.starts_at)) from private.member_event_prices p join private.church_app_events evt on evt.id=p.event_id where p.organization_id=p_org and p.unit_id=p_unit and evt.status='published'),'[]'),'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.order_id,'event',o.event_id,'state',o.state,'expires',o.expires_at)) from private.member_event_orders o join private.church_app_events evt on evt.id=o.event_id where evt.organization_id=p_org and o.user_id=auth.uid()),'[]'));end if;
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
revoke all on function private.member_event_purchase(uuid,uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function private.member_event_purchase(uuid,uuid,text,uuid,jsonb) to authenticated;
create function public.member_event_purchase(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.member_event_purchase(p_org,p_unit,p_action,p_id,p_data)$$;
revoke all on function public.member_event_purchase(uuid,uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function public.member_event_purchase(uuid,uuid,text,uuid,jsonb) to authenticated;

-- Provider-confirmed money is the only path to a paid ticket. Late payments require review if capacity was lost.
create function private.member_paid_ticket_apply() returns trigger language plpgsql security definer set search_path='' as $$
declare booking private.member_event_orders;e private.church_app_events;o private.finance_digital_orders;reg uuid;person public.people;paid boolean;
begin
 select * into booking from private.member_event_orders where order_id=new.order_id;
 if not found then return new;end if;
 select * into e from private.church_app_events where id=booking.event_id for update;
 select * into booking from private.member_event_orders where order_id=new.order_id for update;
 select * into o from private.finance_digital_orders where id=new.order_id;
 paid:=new.snapshot->>'state'='approved' and (new.snapshot->>'gross')::bigint-coalesce((new.snapshot->>'refunded')::bigint,0)>=o.gross;
 if not coalesce(paid,false) then
  if booking.registration_id is null and new.snapshot->>'state' in('pending','processing') then return new;end if;
  if booking.registration_id is not null then update private.church_app_registrations set status='cancelled',version=version+1,code=extensions.gen_random_uuid(),updated_at=clock_timestamp() where id=booking.registration_id;end if;
  update private.member_event_orders set state=case when new.snapshot->>'state' in('refunded','partially_refunded','disputed') then 'cancelled' else 'payment_review' end where order_id=o.id;
  return new;
 end if;
 if booking.state='confirmed' then return new;end if;
 select * into person from public.people where id=o.person_id and status='active' and auth_user_id=booking.user_id;
 if e.status<>'published' or e.starts_at<=now() or person.id is null or not exists(select 1 from public.organization_memberships where organization_id=o.organization_id and user_id=booking.user_id and status='active') or
 (select count(*) from private.church_app_registrations where event_id=e.id and status='confirmed')+(select count(*) from private.member_event_orders where event_id=e.id and order_id<>o.id and state='holding' and expires_at>now())>=e.capacity then
  update private.member_event_orders set state='payment_review' where order_id=o.id;return new;
 end if;
 update private.church_app_events set commerce_version=commerce_version+1 where id=e.id;
 insert into private.church_app_registrations(organization_id,unit_id,event_id,user_id,person_id,name) values(e.organization_id,e.unit_id,e.id,booking.user_id,person.id,person.full_name)
 on conflict(event_id,user_id) do update set status='confirmed',code=extensions.gen_random_uuid(),version=church_app_registrations.version+1,updated_at=clock_timestamp() returning id into reg;
 update private.member_event_orders set state='confirmed',registration_id=reg where order_id=o.id;
 return new;
end $$;
revoke all on function private.member_paid_ticket_apply() from public,anon,authenticated,service_role;
create trigger member_paid_ticket after insert or update of snapshot on private.finance_digital_receipts for each row execute function private.member_paid_ticket_apply();

create function private.member_paid_ticket_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.member_event_prices where event_id=new.event_id) and new.status='confirmed' and not exists(select 1 from private.member_event_orders b join private.finance_digital_orders o on o.id=b.order_id join private.finance_digital_receipts rec on rec.order_id=o.id
 where b.event_id=new.event_id and b.user_id=new.user_id and rec.snapshot->>'state'='approved' and (rec.snapshot->>'gross')::bigint-coalesce((rec.snapshot->>'refunded')::bigint,0)>=o.gross) then raise exception 'member_event_payment_required' using errcode='42501';end if;
 return new;
end $$;
revoke all on function private.member_paid_ticket_guard() from public,anon,authenticated,service_role;
create trigger member_paid_ticket_guard before insert or update on private.church_app_registrations for each row execute function private.member_paid_ticket_guard();

create or replace function member_app_api.agenda(p_org uuid,p_unit uuid,p_past boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_event_enabled(p_org,p_unit) then return jsonb_build_object('unitId',p_unit,'available',false,'items','[]'::jsonb);end if;
 return jsonb_build_object('unitId',p_unit,'available',true,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from(
  select e.id,e.title,e.description,e.kind,e.starts_at,e.ends_at,e.location,e.address,e.capacity,e.status,e.version,coalesce(price.amount,0)::text as price_cents,
  greatest(0,e.capacity-(select count(*) from private.church_app_registrations r where r.event_id=e.id and r.status='confirmed')-(select count(*) from private.member_event_orders o where o.event_id=e.id and o.state='holding' and o.expires_at>now())) as remaining
  from private.church_app_events e left join private.member_event_prices price on price.event_id=e.id where e.organization_id=p_org and e.unit_id=p_unit and e.status in('published','cancelled')
  and case when p_past then e.ends_at<now() and e.ends_at>now()-interval '1 year' else e.ends_at>=now() end order by e.starts_at limit 100)x),'[]'));
end $$;

alter table private.member_push_devices alter column token drop not null;
create index member_payment_catalog_purpose_scope on private.member_payment_catalog(purpose_id,organization_id,unit_id);
create index member_event_prices_event_scope on private.member_event_prices(event_id,organization_id,unit_id);
