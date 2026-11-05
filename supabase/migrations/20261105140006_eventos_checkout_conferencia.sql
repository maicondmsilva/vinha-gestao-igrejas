set local lock_timeout='5s';
create function private.event_checkout_review(p_org uuid,p_unit uuid,p_event uuid,p_order uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.event_ticket_orders;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.event_manager(p_org,p_unit) then raise exception 'event_review_denied' using errcode='42501';end if;
 select * into o from private.event_ticket_orders where id=p_order and event_id=p_event and organization_id=p_org and unit_id=p_unit;
 if not found or not private.receiver_actor_allowed(auth.uid(),p_org,o.receiving_unit) then raise exception 'event_review_denied' using errcode='42501';end if;
 return jsonb_build_object('id',o.id,'order',o.finance_order,'receiver',o.receiver_id,'gross',o.total::text,'state',o.checkout_state,'active',o.state='holding' and o.expires_at>clock_timestamp(),'expiresAt',o.expires_at);
end $$;
revoke all on function private.event_checkout_review(uuid,uuid,uuid,uuid) from public,anon,service_role;
grant execute on function private.event_checkout_review(uuid,uuid,uuid,uuid) to authenticated;
create function public.event_checkout_review(p_org uuid,p_unit uuid,p_event uuid,p_order uuid) returns jsonb language sql security invoker set search_path='' as $$select private.event_checkout_review(p_org,p_unit,p_event,p_order)$$;
revoke all on function public.event_checkout_review(uuid,uuid,uuid,uuid) from public,anon,service_role;
grant execute on function public.event_checkout_review(uuid,uuid,uuid,uuid) to authenticated;
-- Completion only records a preference verified by the server; it never creates a second preference.
do $patch$
declare d text;
begin
 select pg_get_functiondef('private.event_ticket_delivery(uuid,text,jsonb)'::regprocedure) into d;
 if position('if o.checkout_state<>''dispatching'' or' in d)=0 then raise exception 'checkout completion anchor missing';end if;
 d:=replace(d,'if o.checkout_state<>''dispatching'' or','if o.checkout_state not in(''dispatching'',''uncertain'') or o.checkout_state=''uncertain'' and (o.state<>''holding'' or o.expires_at<=clock_timestamp() or e.status<>''published'' or private.member_payment_receiver(o.organization_id,f.unit_id,f.purpose_id) is distinct from r.id) or');execute d;
end $patch$;
notify pgrst,'reload schema';
-- Pickup may begin while orders are still open. Only the final pickup deadline bounds it.
create or replace function private.commerce_dates_guard() returns trigger language plpgsql security definer set search_path='' as $guard$
begin
 if exists(select 1 from private.church_app_events e where e.id=new.id and e.commerce_mode='sale' and (e.pickup_at is null or e.pickup_at>e.ends_at)) then raise exception 'invalid_commerce_pickup_end' using errcode='23514';end if;
 return null;
end $guard$;
do $patch$
declare d text;
begin
 select pg_get_functiondef('private.commerce_event_save(uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,'pickup<e.starts_at or ','');d:=replace(d,'''invalid_commerce_dates''','''invalid_commerce_pickup_end''');execute d;
end $patch$;
-- Human-facing IDs are sequential within each ministry. UUIDs remain internal foreign keys.
lock table private.church_app_events in share row exclusive mode;
alter table private.church_app_events add column display_id bigint;
with numbered as(select id,row_number() over(partition by organization_id order by created_at,id) n from private.church_app_events) update private.church_app_events e set display_id=n.n from numbered n where n.id=e.id;
set constraints all immediate;
alter table private.church_app_events alter column display_id set not null;
alter table private.church_app_events add constraint event_display_id_positive check(display_id>0),add constraint event_display_id_scope unique(organization_id,display_id);
create table private.event_display_counters(organization_id uuid primary key references public.organizations(id),last_value bigint not null check(last_value>0));
insert into private.event_display_counters select organization_id,max(display_id) from private.church_app_events group by organization_id;
alter table private.event_display_counters enable row level security;
revoke all on private.event_display_counters from public,anon,authenticated,service_role;
create function private.event_display_number() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then if new.display_id is distinct from old.display_id or new.organization_id is distinct from old.organization_id then raise exception 'event_number_immutable' using errcode='22023';end if;return new;end if;
 insert into private.event_display_counters values(new.organization_id,1) on conflict(organization_id) do update set last_value=event_display_counters.last_value+1 returning last_value into new.display_id;
 return new;
end $$;
revoke all on function private.event_display_number() from public,anon,authenticated,service_role;
create trigger event_display_number before insert or update of display_id,organization_id on private.church_app_events for each row execute function private.event_display_number();
do $patch$
declare d text;needle text;
begin
 select pg_get_functiondef('private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,'''used'',private.event_ticket_used(e.id,x.id)', '''has_orders'',exists(select 1 from private.event_ticket_items i where i.type_id=x.id),''used'',private.event_ticket_used(e.id,x.id)');
 needle:=' elsif p_action=''type'' then';
 if position(needle in d)=0 then raise exception 'ticket management anchor missing';end if;
 d:=replace(d,needle,$sql$ elsif p_action in('type_delete','type_active') then
  select * into t from private.event_ticket_types where id=p_id and event_id=e.id for update;
  if not found then raise exception 'event_ticket_denied' using errcode='42501';end if;
  if p_action='type_delete' then
   if exists(select 1 from private.event_ticket_items where type_id=t.id) then raise exception 'event_ticket_has_orders' using errcode='40001';end if;
   if exists(select 1 from private.event_ticket_coupons where t.id=any(ticket_types)) then raise exception 'event_ticket_coupon_linked' using errcode='40001';end if;
   delete from private.event_ticket_types where id=t.id;
  else
   if p_data-array['active']<>'{}' or jsonb_typeof(p_data->'active') is distinct from 'boolean' then raise exception 'invalid_event_ticket' using errcode='22023';end if;
   update private.event_ticket_types set active=(p_data->>'active')::boolean,version=version+1 where id=t.id;
  end if;
$sql$||needle);execute d;
end $patch$;
notify pgrst,'reload schema';
-- Organizer choices come from approved member records linked to confirmed user accounts.
do $patch$
declare d text;needle text;
begin
 select pg_get_functiondef('private.event_information_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,'left join public.people person on person.auth_user_id=m.user_id and person.organization_id=m.organization_id','join public.people person on person.auth_user_id=m.user_id and person.organization_id=m.organization_id and person.status=''active''');execute d;
 select pg_get_functiondef('private.member_profile_review(uuid,text,uuid,text[],text)'::regprocedure) into d;
 needle:='p.full_name as person_name';
 if position(needle in d)=0 then raise exception 'member comparison anchor missing';end if;
 d:=replace(d,needle,$sql$p.full_name as person_name,jsonb_build_object('email',exists(select 1 from auth.users account where account.id=req.user_id and lower(account.email)=lower(p.email)),'cpf',nullif(req.payload->>'cpf','') is not null and regexp_replace(coalesce(p.cpf,''),'[^0-9]','','g')=req.payload->>'cpf','linked',p.auth_user_id=req.user_id) identity_match$sql$);execute d;
end $patch$;
notify pgrst,'reload schema';
-- Acquired item definitions are immutable; availability can still be changed independently.
do $patch$
declare d text;
begin
 select pg_get_functiondef('private.event_ticket_admin(uuid,uuid,uuid,text,uuid,integer,jsonb)'::regprocedure) into d;
 d:=replace(d,' elsif p_action=''type'' then',$sql$ elsif p_action='type' then
  if exists(select 1 from private.event_ticket_items where type_id=p_id) then raise exception 'event_ticket_has_orders' using errcode='40001';end if;
$sql$);execute d;
 select pg_get_functiondef('member_app_api.event_page(uuid)'::regprocedure) into d;
 d:=replace(d,'''id'',e.id,''title'',e.title','''display_id'',e.display_id,''id'',e.id,''title'',e.title');execute d;
end $patch$;
notify pgrst,'reload schema';
-- A confirmed provider rejection or failed read happened before any preference was created.
-- Only the service can release that attempt; ambiguous network results remain uncertain.
do $patch$
declare d text;
begin
 select pg_get_functiondef('private.event_ticket_delivery(uuid,text,jsonb)'::regprocedure) into d;
 d:=replace(d,' elsif p_action=''uncertain'' then',$sql$ elsif p_action='not_sent' then
  if p_data<>'{}'::jsonb then raise exception 'invalid_event_ticket' using errcode='22023';end if;
  update private.event_ticket_orders set checkout_state='reserved',updated_at=clock_timestamp() where id=o.id and checkout_state='dispatching';
$sql$||' elsif p_action=''uncertain'' then');execute d;
end $patch$;
notify pgrst,'reload schema';
-- Matching remains a proposal for review; normalized email/CPF never grant administrative access.
do $patch$
declare d text;
begin
 select pg_get_functiondef('private.member_self_service(uuid,text,uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,'lower(email)=account_email','lower(btrim(email))=account_email');
 d:=replace(d,'cpf=p_data->>''cpf''','regexp_replace(coalesce(cpf,''''),''[^0-9]'','''',''g'')=p_data->>''cpf''');execute d;
end $patch$;
notify pgrst,'reload schema';
