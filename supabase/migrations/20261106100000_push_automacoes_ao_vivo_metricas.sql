begin;
set local lock_timeout='5s';
-- Etapa 2: automações de push (aniversários e início de live), ao vivo automático pelo YouTube e métricas de alcance.

create table private.push_automations(
 organization_id uuid primary key references public.organizations(id),
 birthdays boolean not null default false,
 birthday_title text not null default 'Feliz aniversário!' check(length(btrim(birthday_title)) between 2 and 65),
 birthday_body text not null default 'Hoje a sua igreja celebra a sua vida. Que Deus abençoe o seu novo ano!' check(length(btrim(birthday_body)) between 2 and 240),
 live_push boolean not null default true,
 version integer not null default 1 check(version>0),
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default clock_timestamp()
);
create index push_automations_updated_by on private.push_automations(updated_by);
alter table private.push_automations enable row level security;
revoke all on private.push_automations from public,anon,authenticated,service_role;

create table private.publishing_clicks(
 item_id uuid not null references private.publishing_items(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 organization_id uuid not null references public.organizations(id),
 clicked_at timestamptz not null default clock_timestamp(),
 primary key(item_id,user_id)
);
create index publishing_clicks_user on private.publishing_clicks(user_id);
create index publishing_clicks_org on private.publishing_clicks(organization_id,clicked_at);
alter table private.publishing_clicks enable row level security;
revoke all on private.publishing_clicks from public,anon,authenticated,service_role;

-- Settings: read by any publisher; changed only by owner, admin or pastor.
create function public.push_automation(p_org uuid,p_unit uuid,p_action text,p_version integer default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.push_automations;
begin
 if auth.uid() is null or not private.publisher_unit(p_org,p_unit) then raise exception 'push_denied' using errcode='42501';end if;
 insert into private.push_automations(organization_id) values(p_org) on conflict do nothing;
 if p_action='save' then
  if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'push_denied' using errcode='42501';end if;
  if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['birthdays','birthdayTitle','birthdayBody','livePush']<>'{}'::jsonb
   or jsonb_typeof(p_data->'birthdays')<>'boolean' or jsonb_typeof(p_data->'livePush')<>'boolean'
   or length(btrim(coalesce(p_data->>'birthdayTitle',''))) not between 2 and 65 or length(btrim(coalesce(p_data->>'birthdayBody',''))) not between 2 and 240 then
   raise exception 'invalid_push_automation' using errcode='22023';
  end if;
  select * into a from private.push_automations where organization_id=p_org for update;
  if a.version<>p_version then raise exception 'push_conflict' using errcode='40001';end if;
  update private.push_automations set birthdays=(p_data->>'birthdays')::boolean,live_push=(p_data->>'livePush')::boolean,
   birthday_title=btrim(p_data->>'birthdayTitle'),birthday_body=btrim(p_data->>'birthdayBody'),version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
   where organization_id=p_org;
 elsif p_action<>'get' then raise exception 'invalid_push_automation' using errcode='22023';
 end if;
 select * into a from private.push_automations where organization_id=p_org;
 return jsonb_build_object('ok',true,'birthdays',a.birthdays,'birthdayTitle',a.birthday_title,'birthdayBody',a.birthday_body,'livePush',a.live_push,'version',a.version,
  'canEdit',private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]));
end $$;
revoke all on function public.push_automation(uuid,uuid,text,integer,jsonb) from public,anon;
grant execute on function public.push_automation(uuid,uuid,text,integer,jsonb) to authenticated;

-- Birthdays: one campaign per church per day, picked up by the minute worker.
create function private.push_birthdays() returns integer language plpgsql security definer set search_path='' as $$
declare made integer;today text:=to_char((now() at time zone 'America/Sao_Paulo')::date,'YYYY-MM-DD');
begin
 insert into private.push_campaigns(organization_id,owner_unit,title,body,link,audience,targets,source,source_key,status,send_at,next_run_at)
 select a.organization_id,hq.id,a.birthday_title,a.birthday_body,'{"screen":"inbox"}','{"birthdayToday":true}',units.ids,'birthday','birthday:'||today,'scheduled',clock_timestamp(),clock_timestamp()
 from private.push_automations a
 join public.organizations o on o.id=a.organization_id and o.status in('active','trial')
 cross join lateral(select array_agg(u.id order by u.id) ids from public.organization_units u where u.organization_id=a.organization_id and u.status='active') units
 cross join lateral(select u.id from public.organization_units u where u.organization_id=a.organization_id and u.status='active' order by (u.parent_unit_id is null) desc,u.created_at limit 1) hq
 where a.birthdays and cardinality(units.ids) between 1 and 200
 on conflict(organization_id,source,source_key) do nothing;
 get diagnostics made=row_count;
 return made;
end $$;
revoke all on function private.push_birthdays() from public,anon,authenticated,service_role;
select cron.schedule('vinha-push-birthdays','5 12 * * *','select private.push_birthdays();');

-- Live detection worker (server only): candidate YouTube lives and their state transitions.
create function private.live_engine(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare i private.publishing_items;target text;notify boolean;
begin
 if p_action='due' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'source',x.source,'state',x.live_state)) from(
   select id,source,live_state from private.publishing_items where kind='live' and status='published' and provider='youtube'
    and (live_state='live' or (live_state='scheduled' and starts_at between now()-interval '12 hours' and now()+interval '30 minutes'))
   order by starts_at limit 50)x),'[]'));
 elsif p_action='set' then
  target:=p_data->>'state';
  if target not in('live','ended') or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_live_engine' using errcode='22023';end if;
  select * into i from private.publishing_items where id=(p_data->>'id')::uuid and kind='live' and status='published' for update;
  if not found or i.live_state=target or i.live_state='ended' then return jsonb_build_object('ok',true,'changed',false);end if;
  update private.publishing_items set live_state=target,version=version+1,updated_at=clock_timestamp() where id=i.id;
  if target='live' then
   select coalesce((select live_push from private.push_automations where organization_id=i.organization_id),true) into notify;
   if notify then
    insert into private.push_campaigns(organization_id,owner_unit,title,body,link,audience,targets,source,source_key,status,send_at,next_run_at)
    values(i.organization_id,i.owner_unit,'Ao vivo agora',left(btrim(i.title),240),jsonb_build_object('screen','live','id',i.id),'{}',i.targets,'live','live:'||i.id,'scheduled',clock_timestamp(),clock_timestamp())
    on conflict(organization_id,source,source_key) do nothing;
   end if;
  end if;
  return jsonb_build_object('ok',true,'changed',true);
 end if;
 raise exception 'invalid_live_engine' using errcode='22023';
end $$;
revoke all on function private.live_engine(text,jsonb) from public,anon,authenticated,service_role;
create function public.live_engine(p_action text,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.live_engine(p_action,p_data)$$;
revoke all on function public.live_engine(text,jsonb) from public,anon,authenticated;
grant execute on function public.live_engine(text,jsonb) to service_role;

-- Banner/notice tap from the member app (metric only).
create function public.publishing_click(p_item uuid) returns jsonb language sql security definer set search_path='' as $$
 with ins as(insert into private.publishing_clicks(item_id,user_id,organization_id)
  select i.id,auth.uid(),i.organization_id from private.publishing_items i
  where i.id=p_item and i.status='published' and exists(select 1 from public.organization_memberships m where m.user_id=auth.uid() and m.organization_id=i.organization_id and m.status='active')
  on conflict do nothing returning 1)
 select jsonb_build_object('ok',true);
$$;
revoke all on function public.publishing_click(uuid) from public,anon;
grant execute on function public.publishing_click(uuid) to authenticated;

-- Reach metrics for the communication panel: push, notice reads, banner taps, over the last N days.
create function public.communication_metrics(p_org uuid,p_unit uuid,p_days integer default 30) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare since timestamptz;dest uuid[];
begin
 if auth.uid() is null or not private.publisher_unit(p_org,p_unit) then raise exception 'push_denied' using errcode='42501';end if;
 if p_days not in(7,30,90) then raise exception 'invalid_metrics' using errcode='22023';end if;
 since:=now()-make_interval(days=>p_days);
 select coalesce(array_agg(u.id),'{}') into dest from public.organization_units u where u.organization_id=p_org and private.publisher_unit(p_org,u.id);
 return jsonb_build_object('days',p_days,
  'push',(select jsonb_build_object('campaigns',count(distinct c.id),'recipients',count(m.id),
    'delivered',count(m.id) filter(where m.state in('submitted','delivered')),'opened',count(m.id) filter(where m.opened_at is not null))
   from private.push_campaigns c join private.push_runs r on r.campaign_id=c.id join private.push_messages m on m.run_id=r.id
   where c.organization_id=p_org and c.owner_unit=any(dest) and r.created_at>=since),
  'campaigns',coalesce((select jsonb_agg(x order by x->>'at' desc) from(select jsonb_build_object('id',c.id,'title',c.title,'source',c.source,'at',max(r.created_at),
    'recipients',count(m.id),'delivered',count(m.id) filter(where m.state in('submitted','delivered')),'opened',count(m.id) filter(where m.opened_at is not null)) x
   from private.push_campaigns c join private.push_runs r on r.campaign_id=c.id left join private.push_messages m on m.run_id=r.id
   where c.organization_id=p_org and c.owner_unit=any(dest) and r.created_at>=since group by c.id order by max(r.created_at) desc limit 10)q),'[]'),
  'notices',coalesce((select jsonb_agg(x order by (x->>'reads')::int desc) from(select jsonb_build_object('id',i.id,'title',i.title,'kind',i.kind,
    'reads',(select count(*) from private.member_publications p join private.member_inbox_reads rd on rd.organization_id=p.organization_id and rd.message_key='post:'||p.id
      where p.publishing_id=i.id),
    'clicks',(select count(*) from private.publishing_clicks k where k.item_id=i.id)) x
   from private.publishing_items i where i.organization_id=p_org and i.owner_unit=any(dest) and i.kind in('notice','banner') and i.status='published' and i.updated_at>=since
   order by i.updated_at desc limit 20)q),'[]'));
end $$;
revoke all on function public.communication_metrics(uuid,uuid,integer) from public,anon;
grant execute on function public.communication_metrics(uuid,uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
