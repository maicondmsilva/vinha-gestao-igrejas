set local lock_timeout='5s';
create table private.programming_categories(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 80),color text not null check(color ~ '^#[0-9a-fA-F]{6}$'),
 active boolean not null default true,version integer not null default 1,
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),unique(id,organization_id,unit_id)
);
create unique index programming_categories_name on private.programming_categories(organization_id,unit_id,lower(btrim(name)));
create index programming_categories_unit on private.programming_categories(unit_id,organization_id);
alter table private.programming_categories enable row level security;
revoke all on private.programming_categories from public,anon,authenticated,service_role;
alter table private.church_app_events add column category_id uuid,add column cover_url text not null default '' check(length(cover_url)<=2000),add column series_id uuid;
alter table private.church_app_events add constraint programming_category_scope foreign key(category_id,organization_id,unit_id) references private.programming_categories(id,organization_id,unit_id);
create index programming_event_category on private.church_app_events(category_id,organization_id,unit_id);
create index programming_event_series on private.church_app_events(organization_id,unit_id,series_id,starts_at);
create table private.programming_requests(
 organization_id uuid not null references public.organizations(id),unit_id uuid not null,actor_id uuid not null references auth.users(id),request_id uuid not null,
 payload jsonb not null,result jsonb not null,primary key(organization_id,unit_id,actor_id,request_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index programming_requests_actor on private.programming_requests(actor_id);
create index programming_requests_unit on private.programming_requests(unit_id,organization_id);
alter table private.programming_requests enable row level security;
revoke all on private.programming_requests from public,anon,authenticated,service_role;

-- Price revisions invalidate stale event publication in every existing client.
create or replace function private.member_event_purchase(p_org uuid,p_unit uuid,p_action text,p_id uuid,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
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
create function private.programming_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.church_app_events;r private.church_app_events;c private.programming_categories;result jsonb;ids jsonb:='[]';cats jsonb;revs jsonb;
 base jsonb;data jsonb;cat uuid;series uuid;n integer;i integer;step interval;delta interval;duration interval;start_time timestamp;
 query_text text;state text;kind_filter text;section_name text;page_no integer;page_size integer;sort_order text;range_start timestamptz;range_end timestamptz;
begin
 -- Reuse canonical identity/contract/unit checks and serialize with registrations and revocations.
 perform private.community_identity(p_org,p_unit,false);
 perform private.member_agenda_admin(p_org,p_unit,'list');
 if p_action is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(k) order by lower(k.name),k.id),'[]') into cats from private.programming_categories k where k.organization_id=p_org and k.unit_id=p_unit;
 if p_action='categories' then return jsonb_build_object('categories',cats);end if;
 if p_action in('list','calendar','attendees') then
  if p_data-array['search','status','kind','category','section','page','size','sort','from','to']<>'{}'::jsonb then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  query_text:=btrim(coalesce(p_data->>'search',''));state:=coalesce(p_data->>'status','');kind_filter:=coalesce(p_data->>'kind','');section_name:=coalesce(p_data->>'section','todos');sort_order:=coalesce(p_data->>'sort','asc');
  page_no:=coalesce((p_data->>'page')::integer,1);page_size:=coalesce((p_data->>'size')::integer,20);cat:=nullif(p_data->>'category','')::uuid;
  if length(query_text)>120 or state not in('','draft','published','cancelled') or kind_filter not in('','event','service') or section_name not in('todos','proximos','encerrados') or page_no not between 1 and 100000 or page_size not between 1 and 100 or sort_order not in('asc','desc') then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  if p_action='attendees' then
   if not exists(select 1 from private.church_app_events where id=p_id and organization_id=p_org and unit_id=p_unit) then raise exception 'member_agenda_denied' using errcode='42501';end if;
   return (with matches as(select reg.id,reg.name,reg.status,reg.checked_in_at,reg.created_at from private.church_app_registrations reg where reg.event_id=p_id and position(lower(query_text) in lower(reg.name))>0),paged as(select * from matches order by name,id limit page_size offset (page_no-1)*page_size)
    select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p)) from paged p),'[]'),'total',(select count(*) from matches),'page',page_no,'size',page_size));
  end if;
  if p_action='calendar' then
   if p_data->>'from' !~ '^\d{4}-\d{2}-\d{2}$' or p_data->>'to' !~ '^\d{4}-\d{2}-\d{2}$' or not(p_data ?& array['from','to']) then raise exception 'invalid_member_agenda' using errcode='22023';end if;
   range_start:=(p_data->>'from')::date::timestamp at time zone 'America/Sao_Paulo';range_end:=(p_data->>'to')::date::timestamp at time zone 'America/Sao_Paulo';
   if range_end<=range_start or range_end-range_start>interval '43 days' then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  end if;
  return (with matches as(
   select evt.*,k.name category_name,k.color category_color,coalesce(pr.amount,0)::text price_cents,pr.purpose_id,
    (select count(*) from private.church_app_registrations reg where reg.event_id=evt.id and reg.status='confirmed') registrations
   from private.church_app_events evt left join private.programming_categories k on k.id=evt.category_id left join private.member_event_prices pr on pr.event_id=evt.id
   where evt.organization_id=p_org and evt.unit_id=p_unit and position(lower(query_text) in lower(evt.title))>0
    and (state='' or evt.status=state) and (kind_filter='' or evt.kind=kind_filter) and (cat is null or evt.category_id=cat)
    and (section_name='todos' or section_name='proximos' and evt.ends_at>=now() and evt.status<>'cancelled' or section_name='encerrados' and evt.ends_at<now())
    and (p_action<>'calendar' or evt.starts_at<range_end and evt.ends_at>range_start)
  ),paged as(select * from matches order by case when sort_order='asc' then starts_at end asc,case when sort_order='desc' then starts_at end desc,id limit page_size offset (page_no-1)*page_size)
   select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by case when sort_order='asc' then p.starts_at end asc,case when sort_order='desc' then p.starts_at end desc,p.id) from paged p),'[]'),'total',(select count(*) from matches),'page',page_no,'size',page_size,'categories',cats,
    'days',case when p_action='calendar' then (select coalesce(jsonb_object_agg(d.day::date::text,(select count(*) from matches m where m.starts_at<((d.day+interval '1 day')::timestamp at time zone 'America/Sao_Paulo') and m.ends_at>(d.day::timestamp at time zone 'America/Sao_Paulo'))),'{}') from generate_series((p_data->>'from')::date::timestamp,(p_data->>'to')::date::timestamp-interval '1 day',interval '1 day') d(day)) else '{}'::jsonb end));
 end if;
 if p_action='category' then
  if p_id is null or p_data-array['name','color','active']<>'{}'::jsonb or not(p_data ?& array['name','color','active']) or jsonb_typeof(p_data->'name')<>'string' or length(btrim(p_data->>'name')) not between 2 and 80 or p_data->>'color' !~ '^#[0-9a-fA-F]{6}$' or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  select * into c from private.programming_categories where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if found then
   if c.version is distinct from p_version then raise exception 'member_event_changed' using errcode='40001';end if;
   update private.programming_categories set name=btrim(p_data->>'name'),color=p_data->>'color',active=(p_data->>'active')::boolean,version=version+1 where id=c.id;
  else
   if p_version is distinct from 0 then raise exception 'member_event_changed' using errcode='40001';end if;
   insert into private.programming_categories(id,organization_id,unit_id,name,color,active) values(p_id,p_org,p_unit,btrim(p_data->>'name'),p_data->>'color',(p_data->>'active')::boolean);
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'programming.category.save','programming_category',p_id);
  return jsonb_build_object('ok',true);
 end if;
 if p_action='create' then
  if p_id is null then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  select req.result into result from private.programming_requests req where req.organization_id=p_org and req.unit_id=p_unit and req.actor_id=auth.uid() and req.request_id=p_id and req.payload=p_data;
  if found then return result;end if;
  if exists(select 1 from private.programming_requests where organization_id=p_org and unit_id=p_unit and actor_id=auth.uid() and request_id=p_id) then raise exception 'member_event_changed' using errcode='40001';end if;
 else
  select * into e from private.church_app_events where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'member_agenda_denied' using errcode='42501';end if;
  if p_action='detail' then
   select coalesce(jsonb_object_agg(x.id::text,x.version),'{}') into revs from private.church_app_events x where x.organization_id=p_org and x.unit_id=p_unit and (x.id=e.id or e.series_id is not null and x.series_id=e.series_id and x.starts_at>=e.starts_at and x.starts_at>now() and x.status<>'cancelled');
   return jsonb_build_object('event',to_jsonb(e)||(select jsonb_build_object('price_cents',coalesce(pr.amount,0)::text,'purpose_id',pr.purpose_id) from (select 1) a left join private.member_event_prices pr on pr.event_id=e.id),'versions',revs);
  end if;
  if p_action='checkin' then return private.member_agenda_admin(p_org,p_unit,'checkin',p_id,null,p_data);end if;
  if p_version is distinct from e.version then raise exception 'member_event_changed' using errcode='40001';end if;
 end if;
 if p_action='price' then
  if p_data-array['amount','purpose']<>'{}'::jsonb or not(p_data ?& array['amount','purpose']) or p_data->>'amount' !~ '^[0-9]{1,8}$' or (p_data->>'amount')::bigint not between 0 and 99999999 or (p_data->>'amount')::bigint between 1 and 99 then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  result:=private.member_event_purchase(p_org,p_unit,'price',e.id,p_data);
  return result;
 end if;
 if p_action not in('create','edit','publish','cancel') then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 if p_action in('create','edit') then
  if p_data-array['title','description','kind','startsLocal','endsLocal','location','address','capacity','category','cover','repeat','count','future','versions']<>'{}'::jsonb or not(p_data ?& array['title','description','kind','startsLocal','endsLocal','location','address','capacity','category','cover']) or jsonb_typeof(p_data->'cover')<>'string' or length(p_data->>'cover')>2000 or (p_data->>'cover'<>'' and (p_data->>'cover' !~ '^https://[^/@[:space:]]+\.[^/@[:space:]]+' or p_data->>'cover' ~ '[[:cntrl:]]')) then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  cat:=nullif(p_data->>'category','')::uuid;
  if cat is not null and not exists(select 1 from private.programming_categories where id=cat and organization_id=p_org and unit_id=p_unit and (active or p_action='edit' and e.category_id=cat)) then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  base:=p_data-array['category','cover','repeat','count','future','versions'];
 end if;
 if p_action='create' then
  n:=(p_data->>'count')::integer;
  if p_data->>'repeat' not in('none','daily','weekly','monthly') or n not between 1 and 52 or n is null or p_data->>'repeat'='none' and n<>1 or not(p_data ?& array['repeat','count']) or p_data ?| array['future','versions'] then raise exception 'invalid_member_agenda' using errcode='22023';end if;
  series:=case when n>1 then extensions.gen_random_uuid() else null end;
  step:=case p_data->>'repeat' when 'daily' then interval '1 day' when 'weekly' then interval '7 days' when 'monthly' then interval '1 month' else interval '0' end;
  for i in 0..n-1 loop
   data:=base||jsonb_build_object('startsLocal',to_char((base->>'startsLocal')::timestamp+step*i,'YYYY-MM-DD"T"HH24:MI'),'endsLocal',to_char((base->>'endsLocal')::timestamp+step*i,'YYYY-MM-DD"T"HH24:MI'));
   result:=private.member_agenda_admin(p_org,p_unit,'create',null,null,data);
   update private.church_app_events set category_id=cat,cover_url=p_data->>'cover',series_id=series where id=(result->>'id')::uuid;
   ids:=ids||jsonb_build_array(result->>'id');
  end loop;
  result:=jsonb_build_object('ok',true,'ids',ids,'id',ids->>0,'count',n);
  insert into private.programming_requests values(p_org,p_unit,auth.uid(),p_id,p_data,result);
  return result;
 end if;
 if jsonb_typeof(p_data->'future') is distinct from 'boolean' or jsonb_typeof(p_data->'versions') is distinct from 'object' or p_action in('publish','cancel') and p_data-array['future','versions']<>'{}'::jsonb then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 if (p_data->>'future')::boolean and (e.series_id is null or e.starts_at<=now()) then raise exception 'member_event_closed' using errcode='40001';end if;
 -- Compare the complete affected set so a concurrent edit cannot silently affect the remainder of a series.
 select coalesce(jsonb_object_agg(x.id::text,x.version),'{}') into revs from private.church_app_events x where x.organization_id=p_org and x.unit_id=p_unit and (x.id=e.id or (p_data->>'future')::boolean and x.series_id=e.series_id and x.starts_at>=e.starts_at and x.starts_at>now() and x.status<>'cancelled');
 if (p_data->>'future')::boolean and revs is distinct from p_data->'versions' then raise exception 'member_event_changed' using errcode='40001';end if;
 if p_action='edit' then delta:=((base->>'startsLocal')::timestamp at time zone 'America/Sao_Paulo')-e.starts_at;duration:=(base->>'endsLocal')::timestamp-(base->>'startsLocal')::timestamp;end if;
 for r in select * from private.church_app_events where id::text in(select jsonb_object_keys(revs)) order by starts_at,id for update loop
  if p_action='edit' then
   if (base->>'capacity')::integer<(select count(*) from private.church_app_registrations where event_id=r.id and status='confirmed')+(select count(*) from private.member_event_orders held where held.event_id=r.id and held.state='holding' and held.expires_at>now()) then raise exception 'invalid_member_agenda' using errcode='22023';end if;
   data:=base||jsonb_build_object('startsLocal',to_char((r.starts_at+delta) at time zone 'America/Sao_Paulo','YYYY-MM-DD"T"HH24:MI'),'endsLocal',to_char((r.starts_at+delta+duration) at time zone 'America/Sao_Paulo','YYYY-MM-DD"T"HH24:MI'));
   result:=private.member_agenda_admin(p_org,p_unit,'edit',r.id,r.version,data);
   update private.church_app_events set category_id=cat,cover_url=p_data->>'cover' where id=r.id;
  else result:=private.member_agenda_admin(p_org,p_unit,p_action,r.id,r.version,'{}');end if;
  ids:=ids||jsonb_build_array(r.id);
 end loop;
 return jsonb_build_object('ok',true,'ids',ids,'count',jsonb_array_length(ids));
end $$;
revoke all on function private.programming_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.programming_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
create function public.programming_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.programming_admin(p_org,p_unit,p_action,p_id,p_version,p_data)$$;
revoke all on function public.programming_admin(uuid,uuid,text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.programming_admin(uuid,uuid,text,uuid,integer,jsonb) to authenticated;
