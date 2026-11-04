set local lock_timeout='5s';
create table private.event_interests(event_id uuid not null references private.church_app_events(id),user_id uuid not null references auth.users(id),active boolean not null default true,email_consent boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),primary key(event_id,user_id));
create index event_interests_user on private.event_interests(user_id,event_id);
create table private.event_messages(id uuid primary key,event_id uuid not null references private.church_app_events(id),organization_id uuid not null references public.organizations(id),unit_id uuid not null,title text not null check(length(btrim(title)) between 2 and 80),body text not null check(length(btrim(body)) between 2 and 2500),audience text not null check(audience in('all','confirmed','reserved','pending','checkedin','absent','interested')),email_enabled boolean not null default false,scheduled_at timestamptz not null,state text not null default 'draft' check(state in('draft','scheduled','cancelled')),version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),foreign key(event_id,organization_id,unit_id) references private.church_app_events(id,organization_id,unit_id));
create index event_messages_event on private.event_messages(event_id,created_at desc);
create index event_messages_org on private.event_messages(organization_id,unit_id);
create index event_messages_creator on private.event_messages(created_by);
create table private.event_contact_preferences(order_id uuid primary key references private.event_ticket_orders(id),email_consent boolean not null default false,created_at timestamptz not null default now());
create table private.event_email_suppressions(organization_id uuid not null references public.organizations(id),email_hash text not null,created_at timestamptz not null default now(),primary key(organization_id,email_hash));
create table private.event_email_deliveries(id uuid primary key default extensions.gen_random_uuid(),message_id uuid not null references private.event_messages(id),recipient text not null,recipient_key text not null,user_id uuid references auth.users(id),state text not null default 'queued' check(state in('queued','sending','sent','uncertain','cancelled')),claim_token uuid,unsubscribe_token uuid not null default extensions.gen_random_uuid() unique,provider_id text,updated_at timestamptz not null default now(),unique(message_id,recipient_key));
create index event_email_deliveries_user on private.event_email_deliveries(user_id);
create index event_email_deliveries_state on private.event_email_deliveries(state,updated_at);
create table private.event_refund_cases(id uuid primary key,order_id uuid not null references private.event_ticket_orders(id),event_id uuid not null references private.church_app_events(id),organization_id uuid not null references public.organizations(id),receiving_unit uuid not null references public.organization_units(id),amount bigint not null check(amount>0),baseline_refunded bigint not null default 0 check(baseline_refunded>=0),reason text not null check(length(btrim(reason)) between 5 and 1000),state text not null default 'requested' check(state in('requested','approved','declined','awaiting_provider','completed')),decision_note text not null default '',external_note text not null default '',created_by uuid references auth.users(id),reviewed_by uuid references auth.users(id),version integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index event_refund_cases_open on private.event_refund_cases(order_id) where state in('requested','approved','awaiting_provider');
create index event_refund_cases_event on private.event_refund_cases(event_id,created_at desc);
create index event_refund_cases_org on private.event_refund_cases(organization_id,receiving_unit);
create index event_refund_cases_creator on private.event_refund_cases(created_by);
create index event_refund_cases_reviewer on private.event_refund_cases(reviewed_by);
alter table private.event_interests enable row level security;
alter table private.event_messages enable row level security;
alter table private.event_contact_preferences enable row level security;
alter table private.event_email_suppressions enable row level security;
alter table private.event_email_deliveries enable row level security;
alter table private.event_refund_cases enable row level security;
revoke all on private.event_interests,private.event_messages,private.event_contact_preferences,private.event_email_suppressions,private.event_email_deliveries,private.event_refund_cases from public,anon,authenticated,service_role;

create function private.event_message_matches(m private.event_messages,p_user uuid,p_order uuid default null) returns boolean language sql stable security definer set search_path='' as $$
 select (m.audience in('all','interested') and p_user is not null and exists(select 1 from private.event_interests i where i.event_id=m.event_id and i.user_id=p_user and i.active)) or exists(select 1 from private.event_ticket_orders o where o.event_id=m.event_id and (p_order is not null and o.id=p_order or p_order is null and o.user_id=p_user) and
 case m.audience when 'all' then o.state='confirmed' or o.state in('holding','reserved') and o.expires_at>now() when 'confirmed' then o.state='confirmed' when 'reserved' then o.state='reserved' and o.expires_at>now() when 'pending' then o.state='holding' and o.expires_at>now() when 'checkedin' then o.state='confirmed' and exists(select 1 from private.event_ticket_items t where t.order_id=o.id and t.checked_in_at is not null) when 'absent' then o.state='confirmed' and not exists(select 1 from private.event_ticket_items t where t.order_id=o.id and t.checked_in_at is not null) else false end) or p_order is null and exists(select 1 from private.church_app_registrations reg where reg.event_id=m.event_id and reg.user_id=p_user and reg.status='confirmed' and (m.audience in('all','confirmed') or m.audience='checkedin' and reg.checked_in_at is not null or m.audience='absent' and reg.checked_in_at is null));$$;
revoke all on function private.event_message_matches(private.event_messages,uuid,uuid) from public,anon,authenticated,service_role;

create function private.event_interest(p_event uuid,p_active boolean default null,p_email boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;u uuid:=auth.uid();
begin
 if not exists(select 1 from auth.users where id=u and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<now())) then raise exception 'event_login' using errcode='42501';end if;
 select * into e from private.church_app_events where id=p_event and status='published';if not found or not private.member_event_enabled(e.organization_id,e.unit_id) then raise exception 'event_denied' using errcode='42501';end if;
 if p_active is not null then
  if e.ends_at<=clock_timestamp() then raise exception 'event_closed' using errcode='40001';end if;
  insert into private.event_interests(event_id,user_id,active,email_consent) values(e.id,u,p_active,p_active and p_email) on conflict(event_id,user_id) do update set active=excluded.active,email_consent=excluded.email_consent,updated_at=clock_timestamp();
 end if;
 return jsonb_build_object('ok',true,'active',coalesce((select active from private.event_interests where event_id=e.id and user_id=u),false),'emailConsent',coalesce((select email_consent from private.event_interests where event_id=e.id and user_id=u),false));
end $$;
revoke all on function private.event_interest(uuid,boolean,boolean) from public,anon,service_role;
grant execute on function private.event_interest(uuid,boolean,boolean) to authenticated;
create function public.member_event_interest(p_event uuid,p_active boolean default null,p_email boolean default false) returns jsonb language sql security invoker set search_path='' as $$select private.event_interest(p_event,p_active,p_email)$$;
revoke all on function public.member_event_interest(uuid,boolean,boolean) from public,anon,service_role;
grant execute on function public.member_event_interest(uuid,boolean,boolean) to authenticated;

create function private.event_message_authorized(m private.event_messages) returns boolean language sql stable security definer set search_path='' as $$
 select private.member_event_enabled(m.organization_id,m.unit_id) and exists(select 1 from public.organization_memberships mem join auth.users u on u.id=mem.user_id join public.organization_units unit on unit.id=m.unit_id and unit.organization_id=mem.organization_id where mem.organization_id=m.organization_id and mem.user_id=m.created_by and mem.status='active' and mem.role in('owner','admin','pastor') and unit.status='active' and u.email_confirmed_at is not null and u.deleted_at is null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<now()));$$;
revoke all on function private.event_message_authorized(private.event_messages) from public,anon,authenticated,service_role;

-- New communication joins the existing inbox and push pipeline. No outbound sends in a migration.
alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_event_operations;
revoke all on function private.member_inbox_before_event_operations(uuid,uuid) from public,anon,authenticated,service_role;
create function private.member_inbox_rows(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $$
 select * from(select * from private.member_inbox_before_event_operations(p_org,p_unit)
 union all select 'event-message:'||m.id::text,m.title,m.body,m.scheduled_at,'agenda'::text,m.event_id from private.event_messages m join private.church_app_events e on e.id=m.event_id where m.organization_id=p_org and m.state='scheduled' and m.scheduled_at<=now() and m.scheduled_at>now()-interval '90 days' and e.status in('published','cancelled') and private.event_message_authorized(m) and private.member_event_enabled(e.organization_id,e.unit_id) and private.event_message_matches(m,auth.uid()))x order by occurred_at desc nulls last,message_key limit 100;$$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated,service_role;

create function private.event_operations_admin(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;m private.event_messages;o private.event_ticket_orders;c private.event_refund_cases;r private.finance_digital_receipts;manager boolean;finance boolean;d jsonb;n integer;
begin
 perform private.community_identity(p_org,p_unit,false);
 manager:=private.event_manager(p_org,p_unit);finance:=private.receiver_actor_allowed(auth.uid(),p_org,p_unit);
 if not manager and not finance then raise exception 'event_operations_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for no key update;
 select * into e from private.church_app_events where id=p_event and organization_id=p_org and unit_id=p_unit for update;if not found then raise exception 'event_operations_denied' using errcode='42501';end if;
 if p_action='finance' then
  if not finance and not exists(select 1 from private.event_ticket_orders ord where ord.event_id=e.id and private.receiver_actor_allowed(auth.uid(),p_org,ord.receiving_unit)) then raise exception 'event_operations_finance_denied' using errcode='42501';end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(x order by x.created_at desc) from(select ord.id,ord.buyer_name,ord.total::text,ord.state,ord.expires_at,ord.receiving_unit,u.name church,ord.created_at,rec.snapshot,rec.review_reason,rec.posted_gross::text,rec.posted_fee::text,rec.posted_refund::text from private.event_ticket_orders ord join public.organization_units u on u.id=ord.receiving_unit left join private.finance_digital_receipts rec on rec.order_id=ord.finance_order where ord.event_id=e.id and ord.total>0 and private.receiver_actor_allowed(auth.uid(),p_org,ord.receiving_unit) order by ord.created_at desc limit 1000)x),'[]'),'cases',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from private.event_refund_cases x where x.event_id=e.id and private.receiver_actor_allowed(auth.uid(),p_org,x.receiving_unit)),'[]'),'summary',(select jsonb_build_object('orders',count(*),'gross',coalesce(sum(case when rec.snapshot->>'state' in('approved','partially_refunded','refunded','disputed') then (rec.snapshot->>'gross')::bigint else 0 end),0)::text,'refunds',coalesce(sum((rec.snapshot->>'refunded')::bigint),0)::text,'fees',coalesce(sum((select sum((f->>'amount')::bigint) from jsonb_array_elements(case when jsonb_typeof(rec.snapshot->'fees')='array' then rec.snapshot->'fees' else '[]'::jsonb end)f)),0)::text,'unknownFees',count(*) filter(where rec.snapshot is not null and rec.snapshot->'fees'='null'::jsonb),'receivable',coalesce(sum(case when ord.state in('holding','reserved') and ord.expires_at>clock_timestamp() then ord.total else 0 end),0)::text,'review',count(*) filter(where ord.state='payment_review')) from private.event_ticket_orders ord left join private.finance_digital_receipts rec on rec.order_id=ord.finance_order where ord.event_id=e.id and ord.total>0 and private.receiver_actor_allowed(auth.uid(),p_org,ord.receiving_unit)));
 end if;
 if p_action in('refund_review','refund_recorded') then
  select * into c from private.event_refund_cases where id=p_id and event_id=e.id for update;
  if not found or not private.receiver_actor_allowed(auth.uid(),p_org,c.receiving_unit) then raise exception 'event_operations_finance_denied' using errcode='42501';end if;
  if c.version is distinct from p_version then raise exception 'event_operations_changed' using errcode='40001';end if;
  if p_action='refund_review' then
   if c.state<>'requested' or p_data-array['approve','note']<>'{}' or jsonb_typeof(p_data->'approve') is distinct from 'boolean' or length(btrim(p_data->>'note')) not between 5 and 1000 then raise exception 'invalid_event_operations' using errcode='22023';end if;
   update private.event_refund_cases set state=case when (p_data->>'approve')::boolean then 'approved' else 'declined' end,decision_note=btrim(p_data->>'note'),reviewed_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=c.id;
  else
   if c.state<>'approved' or p_data-array['reference']<>'{}' or coalesce(length(btrim(p_data->>'reference')),0) not between 5 and 300 then raise exception 'invalid_event_operations' using errcode='22023';end if;
   update private.event_refund_cases set state='awaiting_provider',external_note=btrim(p_data->>'reference'),reviewed_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=c.id;
  end if;
 else
  if not manager then raise exception 'event_operations_denied' using errcode='42501';end if;
  if p_action='messages' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('recipients',(select count(*) from public.organization_memberships mem where mem.organization_id=p_org and mem.status='active' and private.event_message_matches(x,mem.user_id)),'emails',(select jsonb_build_object('queued',count(*) filter(where state='queued'),'sent',count(*) filter(where state='sent'),'uncertain',count(*) filter(where state in('sending','uncertain'))) from private.event_email_deliveries q where q.message_id=x.id)) order by x.created_at desc) from private.event_messages x where x.event_id=e.id),'[]'));end if;
  if p_action='interests' then return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('user',i.user_id,'name',coalesce((select full_name from public.people where organization_id=p_org and auth_user_id=i.user_id limit 1),'Pessoa interessada'),'emailConsent',i.email_consent,'created',i.created_at) order by i.created_at desc) from private.event_interests i where i.event_id=e.id and i.active),'[]'));end if;
  if p_action='cancel_order' then
   select * into o from private.event_ticket_orders where id=p_id and event_id=e.id for update;
   if not found or o.finance_order is not null or o.state='confirmed' and o.total>0 or exists(select 1 from private.event_ticket_items where order_id=o.id and checked_in_at is not null) then raise exception 'event_operations_refund_required' using errcode='40001';end if;
   if coalesce(length(btrim(p_data->>'reason')),0) not between 5 and 1000 then raise exception 'invalid_event_operations' using errcode='22023';end if;
   update private.event_ticket_orders set state='cancelled',updated_at=clock_timestamp() where id=o.id;
  elsif p_action='message_save' then
   if p_data-array['title','body','audience','email','scheduled']<>'{}' or not(p_data ?& array['title','body','audience','email','scheduled']) or jsonb_typeof(p_data->'email') is distinct from 'boolean' or coalesce(length(btrim(p_data->>'title')),0) not between 2 and 80 or p_data->>'title' ~ E'[\r\n]' or coalesce(length(btrim(p_data->>'body')),0) not between 2 and 2500 or (p_data->>'scheduled')::timestamptz>clock_timestamp()+interval '1 year' then raise exception 'invalid_event_operations' using errcode='22023';end if;
   select * into m from private.event_messages where id=p_id;
   if found and (m.event_id<>e.id or m.version is distinct from p_version or m.state<>'draft') then raise exception 'event_operations_changed' using errcode='40001';end if;
   insert into private.event_messages(id,event_id,organization_id,unit_id,title,body,audience,email_enabled,scheduled_at,created_by) values(p_id,e.id,p_org,p_unit,btrim(p_data->>'title'),btrim(p_data->>'body'),p_data->>'audience',(p_data->>'email')::boolean,(p_data->>'scheduled')::timestamptz,auth.uid()) on conflict(id) do update set title=excluded.title,body=excluded.body,audience=excluded.audience,email_enabled=excluded.email_enabled,scheduled_at=excluded.scheduled_at,version=event_messages.version+1;
  elsif p_action in('message_schedule','message_cancel') then
   select * into m from private.event_messages where id=p_id and event_id=e.id for update;
   if not found or m.version is distinct from p_version then raise exception 'event_operations_changed' using errcode='40001';end if;
   if p_action='message_schedule' and (m.state<>'draft' or e.status not in('published','cancelled') or m.scheduled_at<clock_timestamp()-interval '5 minutes') then raise exception 'event_operations_changed' using errcode='40001';end if;
   update private.event_messages set state=case when p_action='message_schedule' then 'scheduled' else 'cancelled' end,version=version+1 where id=m.id;
   if p_action='message_cancel' then update private.event_email_deliveries set state='cancelled',updated_at=clock_timestamp() where message_id=m.id and state='queued';end if;
  else raise exception 'invalid_event_operations' using errcode='22023';end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'event.operations.'||p_action,'church_app_event',e.id::text,jsonb_build_object('item',p_id,'details',case when p_action='cancel_order' then jsonb_build_object('reason',p_data->>'reason') else '{}'::jsonb end));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_operations_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.event_operations_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.event_operations_admin(p_org uuid,p_unit uuid,p_event uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_operations_admin(p_org,p_unit,p_event,p_action,p_id,p_version,p_data)$$;
revoke all on function public.event_operations_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.event_operations_admin(uuid,uuid,uuid,text,uuid,integer,jsonb) to authenticated;

create function private.event_order_support(p_event uuid,p_id uuid,p_actor uuid,p_proof text,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.event_ticket_orders;r private.finance_digital_receipts;c private.event_refund_cases;n bigint;
begin
 if p_actor is not null and not exists(select 1 from auth.users where id=p_actor and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<now())) then raise exception 'event_support_denied' using errcode='42501';end if;
 select * into o from private.event_ticket_orders where id=p_id and event_id=p_event;
 if not found or not(coalesce(o.user_id is not null and o.user_id=p_actor,false)) and (coalesce(p_proof,'')!~'^[0-9a-f]{64}$' or o.proof_hash<>encode(extensions.digest(p_proof,'sha256'),'hex') or o.user_id is not null) then raise exception 'event_support_denied' using errcode='42501';end if;
 if p_action='read' then return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'amount',x.amount::text,'reason',x.reason,'state',x.state,'note',x.decision_note,'created',x.created_at)) from private.event_refund_cases x where x.order_id=o.id),'[]'));end if;
 if p_action<>'request' or p_data-array['id','reason','amount']<>'{}' or coalesce(length(btrim(p_data->>'reason')),0) not between 5 and 1000 then raise exception 'invalid_event_support' using errcode='22023';end if;
 perform 1 from public.organizations where id=o.organization_id for no key update;
 perform 1 from private.church_app_events where id=o.event_id for update;
 select * into o from private.event_ticket_orders where id=p_id for update;
 select * into r from private.finance_digital_receipts where order_id=o.finance_order;
 n:=(p_data->>'amount')::bigint;
 if r.id is null or r.snapshot->>'state' not in('approved','partially_refunded','disputed') or n<=0 or n>o.total-coalesce((r.snapshot->>'refunded')::bigint,0) then raise exception 'event_support_no_refundable_payment' using errcode='40001';end if;
 select * into c from private.event_refund_cases where id=(p_data->>'id')::uuid;
 if found then if c.order_id<>o.id or c.amount<>n or c.reason<>btrim(p_data->>'reason') then raise exception 'event_support_changed' using errcode='40001';end if;return jsonb_build_object('ok',true);end if;
 insert into private.event_refund_cases(id,order_id,event_id,organization_id,receiving_unit,amount,baseline_refunded,reason,created_by) values((p_data->>'id')::uuid,o.id,o.event_id,o.organization_id,o.receiving_unit,n,coalesce((r.snapshot->>'refunded')::bigint,0),btrim(p_data->>'reason'),p_actor);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_order_support(uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.event_order_support(uuid,uuid,uuid,text,text,jsonb) to service_role;
create function public.event_order_support(p_event uuid,p_id uuid,p_actor uuid,p_proof text,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_order_support(p_event,p_id,p_actor,p_proof,p_action,p_data)$$;
revoke all on function public.event_order_support(uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.event_order_support(uuid,uuid,uuid,text,text,jsonb) to service_role;
create function private.event_refund_observed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update private.event_refund_cases set state='completed',version=version+1,updated_at=clock_timestamp() where order_id=new.order_id and state in('requested','approved','awaiting_provider') and new.snapshot->>'state' in('partially_refunded','refunded') and (new.snapshot->>'refunded')::bigint>=baseline_refunded+amount;
 return new;
end $$;
revoke all on function private.event_refund_observed() from public,anon,authenticated,service_role;
create trigger event_refund_observed after insert or update of snapshot on private.finance_digital_receipts for each row execute function private.event_refund_observed();
notify pgrst,'reload schema';
create function private.event_email_candidates(m private.event_messages) returns table(email text,user_id uuid) language sql stable security definer set search_path='' as $$
 select distinct lower(u.email),u.id from private.event_interests i join auth.users u on u.id=i.user_id where i.event_id=m.event_id and i.active and i.email_consent and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<now()) and private.event_message_matches(m,u.id)
 union select distinct o.buyer_email,o.user_id from private.event_ticket_orders o join private.event_contact_preferences p on p.order_id=o.id and p.email_consent where o.event_id=m.event_id and private.event_message_matches(m,o.user_id,o.id) and (o.user_id is null or exists(select 1 from auth.users where id=o.user_id and email_confirmed_at is not null and deleted_at is null and (banned_until is null or banned_until<now())));$$;
revoke all on function private.event_email_candidates(private.event_messages) from public,anon,authenticated,service_role;
create function private.event_email_work(p_action text,p_org uuid default null,p_event uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare m private.event_messages;d private.event_email_deliveries;e private.church_app_events;result jsonb:='[]';
begin
 if p_action='claim' then
  update private.event_email_deliveries set state='uncertain',updated_at=clock_timestamp() where state='sending' and updated_at<clock_timestamp()-interval '15 minutes';
  for m in select * from private.event_messages where state='scheduled' and email_enabled and scheduled_at<=clock_timestamp() and scheduled_at>clock_timestamp()-interval '7 days' and (p_org is null or organization_id=p_org) and (p_event is null or event_id=p_event) order by scheduled_at limit 50 loop
   perform 1 from public.organizations where id=m.organization_id for no key update;
   select * into e from private.church_app_events where id=m.event_id;
   if e.status not in('published','cancelled') or not private.event_message_authorized(m) then continue;end if;
   insert into private.event_email_deliveries(message_id,recipient,recipient_key,user_id) select distinct on(lower(c.email)) m.id,lower(c.email),encode(extensions.digest(lower(c.email),'sha256'),'hex'),c.user_id from private.event_email_candidates(m)c where c.email~'^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$' and not exists(select 1 from private.event_email_suppressions s where s.organization_id=m.organization_id and s.email_hash=encode(extensions.digest(lower(c.email),'sha256'),'hex')) on conflict(message_id,recipient_key) do nothing;
  end loop;
  for d in select x.* from private.event_email_deliveries x join private.event_messages msg on msg.id=x.message_id where x.state='queued' and (p_org is null or msg.organization_id=p_org) and (p_event is null or msg.event_id=p_event) order by x.updated_at limit 1 for update of x skip locked loop
   select * into m from private.event_messages where id=d.message_id;
   if m.state<>'scheduled' or m.scheduled_at>clock_timestamp() or not private.event_message_authorized(m) or not exists(select 1 from private.church_app_events where id=m.event_id and status in('published','cancelled')) or not exists(select 1 from private.event_email_candidates(m)c where lower(c.email)=d.recipient) or exists(select 1 from private.event_email_suppressions where organization_id=m.organization_id and email_hash=d.recipient_key) then update private.event_email_deliveries set state='cancelled' where id=d.id;continue;end if;
   update private.event_email_deliveries set state='sending',claim_token=extensions.gen_random_uuid(),updated_at=clock_timestamp() where id=d.id returning * into d;
   result:=result||jsonb_build_array(jsonb_build_object('id',d.id,'token',d.claim_token,'recipient',d.recipient,'title',m.title,'body',m.body,'event',m.event_id,'unsubscribe',d.unsubscribe_token));
  end loop;return jsonb_build_object('items',result);
 elsif p_action='settle' then
  update private.event_email_deliveries set state=case when nullif(p_data->>'provider','') is null then 'uncertain' else 'sent' end,provider_id=nullif(p_data->>'provider',''),updated_at=clock_timestamp() where id=(p_data->>'id')::uuid and claim_token=(p_data->>'token')::uuid and state='sending';if not found then raise exception 'event_delivery_changed' using errcode='40001';end if;return jsonb_build_object('ok',true);
 end if;raise exception 'invalid_event_delivery' using errcode='22023';
end $$;
revoke all on function private.event_email_work(text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.event_email_work(text,uuid,uuid,jsonb) to service_role;
create function public.event_email_work(p_action text,p_org uuid default null,p_event uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.event_email_work(p_action,p_org,p_event,p_data)$$;
revoke all on function public.event_email_work(text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.event_email_work(text,uuid,uuid,jsonb) to service_role;
create function private.event_email_unsubscribe(p_token uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.event_email_deliveries;org uuid;
begin
 select * into d from private.event_email_deliveries where unsubscribe_token=p_token;if not found then return jsonb_build_object('ok',true);end if;
 select organization_id into org from private.event_messages where id=d.message_id;
 insert into private.event_email_suppressions(organization_id,email_hash) values(org,d.recipient_key) on conflict do nothing;
 update private.event_email_deliveries x set state='cancelled',updated_at=clock_timestamp() where x.recipient_key=d.recipient_key and x.state='queued' and exists(select 1 from private.event_messages m where m.id=x.message_id and m.organization_id=org);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.event_email_unsubscribe(uuid) from public,anon,authenticated;
grant execute on function private.event_email_unsubscribe(uuid) to service_role;
create function public.event_email_unsubscribe(p_token uuid) returns jsonb language sql security invoker set search_path='' as $$select private.event_email_unsubscribe(p_token)$$;
revoke all on function public.event_email_unsubscribe(uuid) from public,anon,authenticated;
grant execute on function public.event_email_unsubscribe(uuid) to service_role;
-- Persist only explicit consent; old orders do not gain opt-in retroactively.
do $patch$ declare d text;needle text;begin
 select pg_get_functiondef('private.event_ticket_checkout(uuid,text,uuid,uuid,text,jsonb,text)'::regprocedure) into d;
 needle:='p_data-array[''buyerName'',''buyerEmail'',''emailConfirmation'',''items'',''coupon'',''intent'',''expectedTotal'',''revision'']';
 if position(needle in d)=0 then raise exception 'checkout_signature_changed';end if;
 d:=replace(d,needle,'p_data-array[''buyerName'',''buyerEmail'',''emailConfirmation'',''items'',''coupon'',''intent'',''expectedTotal'',''revision'',''emailConsent'']');
 needle:='  if o.state in(''confirmed'',''reserved'') then return private.event_ticket_order_view(o);end if;';
 if position(needle in d)=0 then raise exception 'checkout_insert_changed';end if;
 d:=replace(d,needle,'  if p_data ? ''emailConsent'' and jsonb_typeof(p_data->''emailConsent'') is distinct from ''boolean'' then raise exception ''invalid_event_ticket'' using errcode=''22023'';end if;insert into private.event_contact_preferences(order_id,email_consent) values(o.id,coalesce((p_data->>''emailConsent'')::boolean,false));'||chr(10)||needle);
 execute d;
end $patch$;
