-- Scale notices use the existing authenticated inbox and read receipts.
alter table private.scale_invites
  add column ended_at timestamptz,
  add column reminder_at timestamptz;

create function private.scale_invite_notice_dates() returns trigger
language plpgsql set search_path='' as $$
declare hours integer;
begin
  if tg_op = 'INSERT' then
    select t.reminder_hours into hours from private.scale_teams t where t.id=new.team_id;
    if hours > 0 then
      new.reminder_at := greatest(new.invited_at + interval '1 hour', new.deadline - make_interval(hours=>hours));
      if new.reminder_at >= new.deadline then new.reminder_at := null; end if;
    end if;
  elsif old.active and not new.active then
    new.ended_at := now();
  end if;
  return new;
end;
$$;
revoke all on function private.scale_invite_notice_dates() from public,anon,authenticated,service_role;
create trigger scale_invite_notice_dates
before insert or update of active on private.scale_invites
for each row execute function private.scale_invite_notice_dates();

alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_scales;
create function private.member_inbox_rows(p_org uuid,p_unit uuid)
returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid)
language sql stable security definer set search_path='' as $$
  with identity as materialized (
    select p.id, p.unit_id from public.people p
    join public.organization_memberships m on m.organization_id=p.organization_id and m.user_id=p.auth_user_id
    join public.organizations o on o.id=p.organization_id
    join public.organization_units u on u.id=p.unit_id and u.organization_id=p.organization_id
    join auth.users au on au.id=m.user_id
    where p.organization_id=p_org and p.auth_user_id=auth.uid()
      and p.status='active' and m.status='active' and o.status in ('active','trial') and u.status='active'
      and au.email_confirmed_at is not null and au.deleted_at is null and not coalesce(au.is_anonymous,false)
      and (au.banned_until is null or au.banned_until<now())


  ), scale_messages as (
    select 'scale:'||i.id||':'||n.kind as message_key, n.title,
      coalesce(i.snapshot->>'title',s.title)||'. Consulte Minhas escalas.' as body,
      n.occurred_at, 'scales'::text as target, i.id as target_id
    from identity p
    join private.scale_invites i on i.person_id=p.id and i.unit_id=p.unit_id and i.organization_id=p_org
    join private.scale_services s on s.id=i.service_id
    cross join lateral (values
      ('invitation','Convite para servir'::text,i.invited_at,i.active and s.status in ('published','closed')),
      ('reminder','Lembrete de resposta',i.reminder_at,i.active and i.response='pending' and s.status='published' and now()<i.deadline),
      ('change',case i.ended_reason when 'cancelled' then 'Escala cancelada' when 'revision' then 'Escala em revisão' else 'Atribuição atualizada' end,
       i.ended_at,not i.active)
    ) n(kind,title,occurred_at,visible)
    where (select count(*) from identity)=1 and n.visible
      and private.target_unit_module_enabled(p_org,p.unit_id,'scales')
      and private.target_unit_module_enabled(p_org,p.unit_id,'people')
      and n.occurred_at<=now() and n.occurred_at>now()-interval '90 days'
  )
  select * from (
    select * from private.member_inbox_before_scales(p_org,p_unit)
    union all
    select * from scale_messages
  ) messages
  order by occurred_at desc nulls last,message_key
  limit 100;
$$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated,service_role;

create function private.scale_insights(p_org uuid,p_unit uuid,p_action text,p_data jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  zone text;
  service_filter uuid;
  date_from date := (p_data->>'from')::date;
  date_to date := (p_data->>'to')::date;
  team_filter uuid := nullif(p_data->>'team','')::uuid;
  role_filter uuid := nullif(p_data->>'role','')::uuid;
  current_page integer := coalesce((p_data->>'page')::integer,1);
  search_text text := btrim(coalesce(p_data->>'search',''));
  result jsonb;
begin
  perform private.require_confirmed_self_service_email();
  if not private.scale_allowed(p_org,p_unit,team_filter,'read') then
    raise exception 'scale_access_denied' using errcode='42501';
  end if;
  if p_action is null or p_action not in ('report','export','pending','filters','connections') or current_page not between 1 and 10000
     or length(search_text)>100 then
    raise exception 'scale_insights_input' using errcode='22023';
  end if;
  zone := private.unit_timezone(p_unit);
  if p_action='connections' then
    service_filter := (p_data->>'service')::uuid;
    if service_filter is null or not private.scale_service_allowed(p_org,p_unit,service_filter,'read') then
      raise exception 'scale_access_denied' using errcode='42501';
    end if;
    select jsonb_build_object(
      'timezone',s.timezone,
      'event',case when e.id is not null then jsonb_build_object(
        'title',e.title,'status',e.status,
        'path',case when e.status='published' and private.member_event_enabled(p_org,p_unit) then '/eventos/e-'||e.id::text end,
        'differentTime',e.starts_at<>s.starts_at or e.ends_at<>s.ends_at
      ) end,
      'kids',coalesce((
        select jsonb_agg(to_jsonb(k) order by k.starts_at,k.id)
        from (
          select ks.id,ks.name,ks.starts_at,ks.ends_at,ks.status
          from private.kids_sessions ks
          where ks.organization_id=p_org and ks.unit_id=p_unit and ks.status<>'cancelled'
            and ks.starts_at<s.ends_at and ks.ends_at>s.arrival_at
            and private.kids_op_allowed(p_org,p_unit,ks.id,'read',null)
          order by ks.starts_at,ks.id limit 10
        ) k
      ),'[]'::jsonb)
    ) into result
    from private.scale_services s
    left join private.church_app_events e on e.id=s.event_id and e.organization_id=p_org and e.unit_id=p_unit
    where s.id=service_filter;
    return result;
  end if;
  if p_action='filters' then
    return jsonb_build_object('timezone',zone,'choices',coalesce((
      select jsonb_agg(jsonb_build_object('team',t.id,'teamName',t.name,'role',r.id,'roleName',r.name) order by t.name,r.name)
      from private.scale_teams t join private.scale_roles r on r.team_id=t.id
      where t.organization_id=p_org and t.unit_id=p_unit and private.scale_allowed(p_org,p_unit,t.id,'read')
    ),'[]'::jsonb));
  end if;
  if p_action in ('report','export') and (date_from is null or date_to is null or date_to-date_from not between 0 and 365) then
    raise exception 'scale_insights_period' using errcode='22023';
  end if;
  if role_filter is not null and not exists (
    select 1 from private.scale_roles r where r.id=role_filter and r.organization_id=p_org and r.unit_id=p_unit
      and (team_filter is null or r.team_id=team_filter) and private.scale_allowed(p_org,p_unit,r.team_id,'read')
  ) then raise exception 'scale_access_denied' using errcode='42501'; end if;

  if p_action='pending' then
    with services as materialized (
      select s.id,s.title,s.starts_at from private.scale_services s
      where s.organization_id=p_org and s.unit_id=p_unit and s.status='published' and s.ends_at>now()
        and private.scale_service_allowed(p_org,p_unit,s.id,'read')
    ), pending as materialized (
      select s.id as service_id,s.title,s.starts_at,t.name as team,r.name as role,p.full_name as name,
        case when x.id is not null then 'replacement' when q.member_id is null then 'vacancy'
             when i.response='declined' then 'declined' else 'reply' end as kind,
        case when x.id is not null or q.member_id is null or i.response='declined' then s.starts_at else i.deadline end as due,
        q.role_id,q.ordinal
      from services s join private.scale_positions q on q.service_id=s.id
      join private.scale_teams t on t.id=q.team_id join private.scale_roles r on r.id=q.role_id
      left join private.scale_invites i on i.service_id=q.service_id and i.role_id=q.role_id and i.ordinal=q.ordinal and i.active
      left join public.people p on p.id=i.person_id
      left join private.scale_replacements x on x.invite_id=i.id and x.state='pending'
      where (team_filter is null or q.team_id=team_filter) and (role_filter is null or q.role_id=role_filter)
        and (q.member_id is null or i.response in ('pending','declined') or x.id is not null)
        and (search_text='' or strpos(lower(concat_ws(' ',s.title,t.name,r.name,p.full_name)),lower(search_text))>0)
    )
    select jsonb_build_object('timezone',zone,'total',(select count(*) from pending),
      'items',coalesce((select jsonb_agg(to_jsonb(page_rows) order by due,service_id,role_id,ordinal)
        from (select * from pending order by due,service_id,role_id,ordinal limit 30 offset (current_page-1)*30) page_rows),'[]'::jsonb))
      into result;
    return result;
  end if;

  with services as materialized (
    select s.id,s.ends_at
    from private.scale_services s
    where s.organization_id=p_org and s.unit_id=p_unit and s.status in ('published','closed')
      and s.starts_at >= date_from::timestamp at time zone zone
      and s.starts_at < (date_to+1)::timestamp at time zone zone
      and private.scale_service_allowed(p_org,p_unit,s.id,'read')
  ), slots as materialized (
    select s.id as service_id,s.ends_at,q.team_id,q.role_id,q.member_id,i.id as invite_id,
      i.person_id,i.response,i.presence,i.replied_at,i.invited_at
    from services s join private.scale_positions q on q.service_id=s.id
    left join private.scale_invites i on i.service_id=q.service_id and i.role_id=q.role_id and i.ordinal=q.ordinal and i.active
    where (team_filter is null or q.team_id=team_filter) and (role_filter is null or q.role_id=role_filter)
  ), attendance as (
    select service_id,person_id,bool_or(presence='present') as present,bool_or(presence='absent') as absent
    from slots
    where person_id is not null and ends_at<=now() and (response<>'declined' or presence<>'unset')
    group by service_id,person_id
  ), changes as (
    select count(*) as total,count(*) filter(where x.state='approved') as approved,
      count(*) filter(where x.state='pending') as pending
    from services s join private.scale_invites i on i.service_id=s.id
    join private.scale_replacements x on x.invite_id=i.id
    where (team_filter is null or i.team_id=team_filter) and (role_filter is null or i.role_id=role_filter)
  ), distribution as materialized (
    select p.id,p.full_name as name,count(distinct s.service_id) as services,
      count(*) as assignments,count(*) filter(where s.response='accepted') as confirmed
    from slots s join public.people p on p.id=s.person_id
    where s.response<>'declined' or s.presence<>'unset'
    group by p.id,p.full_name
  ), team_roles as (
    select t.name as team,r.name as role,count(*) as required,count(s.member_id) as filled,
      count(s.invite_id) as invites,count(*) filter(where s.response='accepted') as confirmed,
      count(*) filter(where s.response='declined') as declined,count(*) filter(where s.response='pending') as pending
    from slots s join private.scale_teams t on t.id=s.team_id join private.scale_roles r on r.id=s.role_id
    group by t.id,t.name,r.id,r.name
  )
  select jsonb_build_object(
    'timezone',zone,
    'unitName',(select name from public.organization_units where id=p_unit and organization_id=p_org),
    'services',(select count(distinct service_id) from slots),
    'slots',(select count(*) from slots),
    'filled',(select count(member_id) from slots),
    'invites',(select count(invite_id) from slots),
    'confirmed',(select count(*) from slots where response='accepted'),
    'declined',(select count(*) from slots where response='declined'),
    'pending',(select count(*) from slots where response='pending'),
    'averageReplyMinutes',(select round(avg(extract(epoch from (replied_at-invited_at)))/60) from slots where replied_at>=invited_at),
    'attendanceBase',(select count(*) from attendance),
    'present',(select count(*) from attendance where present),
    'absent',(select count(*) from attendance where absent and not present),
    'changes',(select to_jsonb(changes) from changes),
    'distributionTotal',(select count(*) from distribution),
    'distribution',coalesce((select jsonb_agg(d order by d.services desc,d.name,d.id) from
      (select * from distribution order by services desc,name,id limit (case when p_action='export' then 2000 else 30 end) offset (case when p_action='export' then 0 else (current_page-1)*30 end))d),'[]'::jsonb),
    'teamRoles',coalesce((select jsonb_agg(t order by t.team,t.role) from team_roles t),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create function public.scale_insights(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}')
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.scale_insights(p_org,p_unit,p_action,p_data);
$$;
revoke all on function private.scale_insights(uuid,uuid,text,jsonb),public.scale_insights(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.scale_insights(uuid,uuid,text,jsonb),public.scale_insights(uuid,uuid,text,jsonb) to authenticated;

-- Personal feed credentials are stored as hashes. Rotation immediately invalidates the old link.
create table private.scale_calendar_links (
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  person_id uuid not null,
  unit_id uuid not null,
  token_hash bytea not null unique,
  primary key(organization_id,user_id),
  foreign key(person_id,organization_id) references public.people(id,organization_id),
  foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index scale_calendar_user on private.scale_calendar_links(user_id);
create index scale_calendar_person on private.scale_calendar_links(person_id,organization_id);
create index scale_calendar_unit on private.scale_calendar_links(unit_id,organization_id);
alter table private.scale_calendar_links enable row level security;
revoke all on private.scale_calendar_links from public,anon,authenticated,service_role;

create function private.scale_calendar_manage(p_org uuid,p_action text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  person uuid;
  unit uuid;
  secret text;
begin
  perform private.require_confirmed_self_service_email();
  if p_action='revoke' then
    delete from private.scale_calendar_links where organization_id=p_org and user_id=auth.uid();
    return jsonb_build_object('active',false);
  end if;
  if p_action is null or p_action not in ('status','rotate') then
    raise exception 'scale_calendar_input' using errcode='22023';
  end if;
  person := private.community_identity(p_org,null,true);
  select p.unit_id into unit from public.people p where p.id=person and p.organization_id=p_org;
  if not exists(select 1 from public.organization_units where id=unit and organization_id=p_org and status='active')
     or not private.target_unit_module_enabled(p_org,unit,'scales')
     or not private.target_unit_module_enabled(p_org,unit,'people') then
    raise exception 'scale_access_denied' using errcode='42501';
  end if;
  if p_action='status' then
    return jsonb_build_object('active',exists(select 1 from private.scale_calendar_links
      where organization_id=p_org and user_id=auth.uid() and person_id=person and unit_id=unit));
  end if;
  secret := encode(extensions.gen_random_bytes(32),'hex');
  insert into private.scale_calendar_links(organization_id,user_id,person_id,unit_id,token_hash)
  values(p_org,auth.uid(),person,unit,extensions.digest(secret,'sha256'))
  on conflict(organization_id,user_id) do update
    set person_id=excluded.person_id,unit_id=excluded.unit_id,token_hash=excluded.token_hash;
  return jsonb_build_object('active',true,'token',secret);
end;
$$;

create function member_app_api.scale_calendar_feed(p_token text) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('timezone',private.unit_timezone(l.unit_id),'events',coalesce((
    select jsonb_agg(to_jsonb(e) order by e.starts_at,e.id)
    from (
      select s.id,s.title,s.starts_at,s.ends_at,s.version
      from private.scale_services s
      where s.organization_id=l.organization_id and s.unit_id=l.unit_id
        and s.status='published' and s.ends_at>=now() and s.starts_at<now()+interval '180 days'
        and exists(select 1 from private.scale_invites i join private.scale_members sm on sm.id=i.member_id
          where i.service_id=s.id and i.person_id=l.person_id and i.active and i.response='accepted' and sm.active)
      order by s.starts_at,s.id limit 250
    ) e
  ),'[]'::jsonb))
  from private.scale_calendar_links l
  join public.organizations o on o.id=l.organization_id and o.status in ('active','trial')
  join public.organization_units u on u.id=l.unit_id and u.organization_id=l.organization_id and u.status='active'
  join public.organization_memberships m on m.organization_id=l.organization_id and m.user_id=l.user_id and m.status='active'
  join public.people p on p.id=l.person_id and p.organization_id=l.organization_id and p.unit_id=l.unit_id
    and p.auth_user_id=l.user_id and p.status='active'
  join auth.users au on au.id=l.user_id and au.email_confirmed_at is not null
    and au.deleted_at is null and not coalesce(au.is_anonymous,false) and (au.banned_until is null or au.banned_until<now())
  where p_token ~ '^[0-9a-f]{64}$' and l.token_hash=extensions.digest(p_token,'sha256')
    and private.target_unit_module_enabled(l.organization_id,l.unit_id,'scales')
    and private.target_unit_module_enabled(l.organization_id,l.unit_id,'people')
    and (select count(*) from public.people peer
      where peer.organization_id=l.organization_id and peer.auth_user_id=l.user_id and peer.status='active')=1;
$$;

create function public.scale_calendar_manage(p_org uuid,p_action text) returns jsonb
language sql security invoker set search_path='' as $$
  select private.scale_calendar_manage(p_org,p_action);
$$;
create function public.scale_calendar_feed(p_token text) returns jsonb
language sql stable security invoker set search_path='' as $$
  select member_app_api.scale_calendar_feed(p_token);
$$;
revoke all on function private.scale_calendar_manage(uuid,text),public.scale_calendar_manage(uuid,text),
  member_app_api.scale_calendar_feed(text),public.scale_calendar_feed(text) from public,anon,authenticated,service_role;
grant execute on function private.scale_calendar_manage(uuid,text),public.scale_calendar_manage(uuid,text) to authenticated;
grant execute on function member_app_api.scale_calendar_feed(text),public.scale_calendar_feed(text) to anon,authenticated;
