-- Private study files. No public URL, replacement or client purge.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('cell-studies-private','cell-studies-private',false,4194304,array['application/pdf','image/png','image/jpeg']) on conflict(id) do nothing;
create function private.cell_study_file_allowed(p_name text,p_write boolean default false) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare parts text[]=string_to_array(p_name,'/');m private.cell_study_materials; actor uuid=auth.uid();
begin
 if actor is null or cardinality(parts)<>4 or exists(select 1 from unnest(parts[1:3])p where p!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') or parts[4]!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|png|jpg)$' then return false;end if;
 if not exists(select 1 from auth.users where id=actor and email_confirmed_at is not null and not coalesce(is_anonymous,false) and deleted_at is null and(banned_until is null or banned_until<now())) then return false;end if;
 select * into m from private.cell_study_materials where id=parts[3]::uuid and organization_id=parts[1]::uuid and unit_id=parts[2]::uuid;
 if m.id is null or not private.cell_plus_active(m.organization_id,m.unit_id,actor) or not private.can_access_unit(m.organization_id,m.unit_id) then return false;end if;
 if private.cell_flow_manager(m.organization_id,m.unit_id,actor) then return true;end if;
 if p_write or m.status<>'published' then return false;end if;
 return (m.network_id is not null and private.cell_plus_network(m.organization_id,m.unit_id,m.network_id,actor)) or (m.network_id is null and exists(select 1 from private.cell_supervisor_grants g where g.organization_id=m.organization_id and g.unit_id=m.unit_id and private.cell_plus_network(m.organization_id,m.unit_id,g.network_id,actor)));
end $$;
revoke all on function private.cell_study_file_allowed(text,boolean) from public,anon,service_role;
grant execute on function private.cell_study_file_allowed(text,boolean) to authenticated;
create policy cell_study_read on storage.objects for select to authenticated using(bucket_id='cell-studies-private' and private.cell_study_file_allowed(name,false));
create policy cell_study_insert on storage.objects for insert to authenticated with check(bucket_id='cell-studies-private' and private.cell_study_file_allowed(name,true));

-- One snapshot across explicitly selected units of the SAME ministry. No automatic cross-tenant linkage.
create function private.cell_consolidated(p_org uuid,p_units uuid[],p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid;allowed uuid[]='{}';part jsonb;rows jsonb='[]';summary jsonb;
begin
 if auth.uid() is null or p_units is null or cardinality(p_units) not between 1 and 100 or cardinality(p_units)<>(select count(distinct x) from unnest(p_units)x) or array_position(p_units,null) is not null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'invalid_cell_scope' using errcode='22023';end if;
 foreach u in array p_units loop
  part=private.cell_plus_read(p_org,u,'reports',null,null,p_from,p_to,null);
  allowed=allowed||array(select (x->>'id')::uuid from jsonb_array_elements(part->'cells')x);
  if cardinality(allowed)>10000 then raise exception 'cell_scope_too_large' using errcode='22023';end if;
  rows=rows||jsonb_build_array(jsonb_build_object('unitId',u,'name',(select name from public.organization_units where id=u and organization_id=p_org),'summary',part->'summary'));
 end loop;
 select jsonb_build_object('groups',cardinality(allowed),'participants',(select count(distinct p.person_id) from public.church_cell_participants p where p.cell_id=any(allowed) and p.organization_id=p_org and p.status='active'),'meetings',count(distinct m.id),'expected',count(a.participant_id),'present',count(a.participant_id) filter(where a.present)) into summary
 from public.church_cell_meetings m left join public.church_cell_attendance a on a.meeting_id=m.id where m.organization_id=p_org and m.unit_id=any(p_units) and m.cell_id=any(allowed) and m.status='completed' and m.meeting_date between p_from and p_to;
 return jsonb_build_object('units',rows,'summary',summary,'from',p_from,'to',p_to);
end $$;
revoke all on function private.cell_consolidated(uuid,uuid[],date,date) from public,anon,service_role;
grant execute on function private.cell_consolidated(uuid,uuid[],date,date) to authenticated;
create function public.cell_consolidated(p_org uuid,p_units uuid[],p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$select private.cell_consolidated(p_org,p_units,p_from,p_to)$$;
revoke all on function public.cell_consolidated(uuid,uuid[],date,date) from public,anon,service_role;
grant execute on function public.cell_consolidated(uuid,uuid[],date,date) to authenticated;

-- Independent database scheduler: never calls billing or external messaging.
create table private.cell_reminder_runs(id bigint generated always as identity primary key,started_at timestamptz not null default clock_timestamp(),finished_at timestamptz,created integer not null default 0,scanned integer not null default 0,unreachable integer not null default 0,has_more boolean not null default false);
alter table private.cell_reminder_runs enable row level security;
create policy internal_only on private.cell_reminder_runs using(false);
revoke all on private.cell_reminder_runs from public,anon,authenticated,service_role;
create function private.run_cell_reminders() returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;after_id uuid;total_created integer=0;total_scanned integer=0;total_unreachable integer=0;run_id bigint;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('cell-reminder-run',0)) then return jsonb_build_object('busy',true);end if;
 insert into private.cell_reminder_runs default values returning id into run_id;
 for i in 1..10 loop
  r=private.cell_report_reminder_batch(after_id);total_created=total_created+(r->>'created')::integer;total_scanned=total_scanned+(r->>'scanned')::integer;total_unreachable=total_unreachable+(r->>'unreachable')::integer;after_id=(r->>'nextCursor')::uuid;exit when after_id is null;
 end loop;
 update private.cell_reminder_runs set finished_at=clock_timestamp(),created=total_created,scanned=total_scanned,unreachable=total_unreachable,has_more=after_id is not null where id=run_id;
 return jsonb_build_object('created',total_created,'scanned',total_scanned,'unreachable',total_unreachable,'hasMore',after_id is not null);
end $$;
revoke all on function private.run_cell_reminders() from public,anon,authenticated,service_role;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('vinha-cell-report-reminders','0 11 * * *','select private.run_cell_reminders();');
-- Deployment activates after isolated tests. No other cron job is modified.
select cron.alter_job(jobid,active:=false) from cron.job where jobname='vinha-cell-report-reminders';

-- Self opt-in only. Authentication SMTP credentials are never read or copied.
create table private.cell_delivery_preferences(
 organization_id uuid not null,unit_id uuid not null,user_id uuid not null references auth.users(id) on delete restrict,
 email_enabled boolean not null default false,whatsapp_enabled boolean not null default false,consented_at timestamptz not null default clock_timestamp(),version integer not null default 1,
 primary key(organization_id,unit_id,user_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id) on delete restrict
);
create index cell_preferences_user_idx on private.cell_delivery_preferences(user_id);
create index cell_preferences_unit_idx on private.cell_delivery_preferences(unit_id,organization_id);
create table private.cell_external_deliveries(
 id uuid primary key default gen_random_uuid(),notification_id uuid not null references private.cell_report_notifications(id) on delete restrict,
 channel text not null check(channel in('email','whatsapp')),status text not null default 'pending' check(status in('pending','sending','submitted','uncertain','cancelled')),
 claim_token uuid,claimed_at timestamptz,submitted_at timestamptz,provider_id text,unique(notification_id,channel)
);
create index cell_external_deliveries_pending_idx on private.cell_external_deliveries(status,id);
alter table private.cell_delivery_preferences enable row level security;
alter table private.cell_external_deliveries enable row level security;
create policy internal_only on private.cell_delivery_preferences using(false);
create policy internal_only on private.cell_external_deliveries using(false);
revoke all on private.cell_delivery_preferences,private.cell_external_deliveries from public,anon,authenticated,service_role;
create function private.cell_delivery_preferences(p_org uuid,p_unit uuid,p_email boolean,p_whatsapp boolean,p_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old private.cell_delivery_preferences;mail text;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org for share;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for share;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() for share;
 if not private.cell_plus_active(p_org,p_unit,auth.uid()) or not private.can_access_unit(p_org,p_unit) then raise exception 'cell_access_denied' using errcode='42501';end if;
 select u.email into mail from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<now()) for share;
 if mail is null then raise exception 'cell_access_denied' using errcode='42501';end if;
 select * into old from private.cell_delivery_preferences where organization_id=p_org and unit_id=p_unit and user_id=auth.uid() for update;
 if p_version is not null then
  if p_email is null or p_whatsapp is null or p_version<>coalesce(old.version,0) then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if p_whatsapp and not exists(select 1 from auth.users where id=auth.uid() and phone_confirmed_at is not null and auth.users.phone ~ '^\+?[1-9][0-9]{9,14}$') then raise exception 'verified_phone_required' using errcode='22023';end if;
  insert into private.cell_delivery_preferences(organization_id,unit_id,user_id,email_enabled,whatsapp_enabled) values(p_org,p_unit,auth.uid(),p_email,p_whatsapp)
  on conflict(organization_id,unit_id,user_id) do update set email_enabled=excluded.email_enabled,whatsapp_enabled=excluded.whatsapp_enabled,consented_at=clock_timestamp(),version=cell_delivery_preferences.version+1 returning * into old;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'cell.notification_preferences','organization_unit',p_unit::text,jsonb_build_object('email',p_email,'whatsapp',p_whatsapp));
 end if;
 return jsonb_build_object('version',coalesce(old.version,0),'emailEnabled',coalesce(old.email_enabled,false),'whatsappEnabled',coalesce(old.whatsapp_enabled,false),'email',mail,'verifiedPhone',exists(select 1 from auth.users where id=auth.uid() and phone_confirmed_at is not null and auth.users.phone ~ '^\+?[1-9][0-9]{9,14}$'),
 'deliveries',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from(select e.id,e.channel,e.status,e.submitted_at from private.cell_external_deliveries e join private.cell_report_notifications n on n.id=e.notification_id where n.organization_id=p_org and n.unit_id=p_unit and n.recipient_id=auth.uid() order by n.created_at desc,e.id limit 20)r));
end $$;
revoke all on function private.cell_delivery_preferences(uuid,uuid,boolean,boolean,integer) from public,anon,service_role;
grant execute on function private.cell_delivery_preferences(uuid,uuid,boolean,boolean,integer) to authenticated;
create function public.cell_delivery_preferences(p_org uuid,p_unit uuid,p_email boolean default null,p_whatsapp boolean default null,p_version integer default null) returns jsonb language sql security invoker set search_path='' as $$select private.cell_delivery_preferences(p_org,p_unit,p_email,p_whatsapp,p_version)$$;
revoke all on function public.cell_delivery_preferences(uuid,uuid,boolean,boolean,integer) from public,anon,service_role;
grant execute on function public.cell_delivery_preferences(uuid,uuid,boolean,boolean,integer) to authenticated;

create function private.cell_delivery_claim(p_channels text[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.cell_external_deliveries;n private.cell_report_notifications;pref private.cell_delivery_preferences;u auth.users;m public.church_cell_meetings;token uuid;result jsonb='[]';
begin
 if p_channels is null or cardinality(p_channels)>2 or exists(select 1 from unnest(p_channels)c where c not in('email','whatsapp') or c is null) then raise exception 'invalid_channel' using errcode='22023';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('cell-delivery-claim',0)) then return result;end if;
 -- An abandoned claim is ambiguous: never blindly resend.
 update private.cell_external_deliveries set status='uncertain' where status='sending' and claimed_at<clock_timestamp()-interval '10 minutes';
 insert into private.cell_external_deliveries(notification_id,channel)
 select notice.id,c from private.cell_report_notifications notice join private.cell_delivery_preferences p on p.organization_id=notice.organization_id and p.unit_id=notice.unit_id and p.user_id=notice.recipient_id
 cross join unnest(p_channels)c where notice.created_at>=p.consented_at and notice.read_at is null and(c='email' and p.email_enabled or c='whatsapp' and p.whatsapp_enabled)
 and not exists(select 1 from private.cell_external_deliveries e where e.notification_id=notice.id and e.channel=c)
 order by notice.id,c limit 100 on conflict(notification_id,channel) do nothing;
 for d in select * from private.cell_external_deliveries where status='pending' and channel=any(p_channels) order by id limit 25 for update skip locked loop
  select * into n from private.cell_report_notifications where id=d.notification_id for share;
  perform 1 from public.organizations where id=n.organization_id for share;
  perform 1 from public.organization_units where id=n.unit_id for share;
  perform 1 from public.saas_unit_contracts where organization_id=n.organization_id and unit_id=n.unit_id for share;
  perform 1 from public.organization_memberships where organization_id=n.organization_id and user_id=n.recipient_id for share;
  perform 1 from public.membership_unit_access a join public.organization_memberships b on b.id=a.membership_id where b.organization_id=n.organization_id and b.user_id=n.recipient_id for share of a;
  perform 1 from public.church_cell_networks where organization_id=n.organization_id and unit_id=n.unit_id order by id for share;
  perform 1 from private.cell_supervisor_grants where organization_id=n.organization_id and unit_id=n.unit_id order by id for share;
  perform 1 from public.church_cell_network_links where cell_id=n.cell_id for share;
  select * into pref from private.cell_delivery_preferences where organization_id=n.organization_id and unit_id=n.unit_id and user_id=n.recipient_id for share;
  select * into u from auth.users where id=n.recipient_id for share;
  select * into m from public.church_cell_meetings where id=n.meeting_id for share;
  if n.created_at<pref.consented_at or n.read_at is not null or m.status<>'scheduled' or not exists(select 1 from public.church_cells where id=n.cell_id and status='active') or not private.cell_plus_cell(n.organization_id,n.unit_id,n.cell_id,n.recipient_id) or u.deleted_at is not null or u.is_anonymous or u.email_confirmed_at is null or u.banned_until>now() or(d.channel='email' and not pref.email_enabled) or(d.channel='whatsapp' and(not pref.whatsapp_enabled or u.phone_confirmed_at is null)) then
   update private.cell_external_deliveries set status='cancelled' where id=d.id;continue;
  end if;
  token=gen_random_uuid();update private.cell_external_deliveries set status='sending',claim_token=token,claimed_at=clock_timestamp() where id=d.id;
  -- No member/group names or attendance go to external providers.
  result=result||jsonb_build_array(jsonb_build_object('id',d.id,'token',token,'channel',d.channel,'recipient',case when d.channel='email' then u.email else ltrim(u.phone,'+') end));
 end loop;
 return result;
end $$;
create function private.cell_delivery_finish(p_id uuid,p_token uuid,p_provider text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 update private.cell_external_deliveries set status=case when p_provider is null then 'uncertain' else 'submitted' end,provider_id=left(p_provider,300),submitted_at=case when p_provider is not null then clock_timestamp() end where id=p_id and claim_token=p_token and status='sending';return found;
end $$;
revoke all on function private.cell_delivery_claim(text[]),private.cell_delivery_finish(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.cell_delivery_claim(text[]),private.cell_delivery_finish(uuid,uuid,text) to service_role;
create function public.cell_delivery_claim(p_channels text[]) returns jsonb language sql security invoker set search_path='' as $$select private.cell_delivery_claim(p_channels)$$;
create function public.cell_delivery_finish(p_id uuid,p_token uuid,p_provider text) returns boolean language sql security invoker set search_path='' as $$select private.cell_delivery_finish(p_id,p_token,p_provider)$$;
revoke all on function public.cell_delivery_claim(text[]),public.cell_delivery_finish(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.cell_delivery_claim(text[]),public.cell_delivery_finish(uuid,uuid,text) to service_role;
