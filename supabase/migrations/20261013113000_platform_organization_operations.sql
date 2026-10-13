alter table public.organizations
  add column if not exists app_name text,
  add column if not exists senior_pastor_name text;

create table public.saas_organization_invites (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  owner_name text not null,
  owner_email text not null check (owner_email = lower(owner_email) and position('@' in owner_email) > 1),
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  invite_token uuid not null unique default extensions.gen_random_uuid(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index saas_organization_invites_org_created_idx on public.saas_organization_invites(organization_id,created_at desc);
create unique index saas_organization_invites_pending_email_idx on public.saas_organization_invites(organization_id,owner_email) where status='pending';

create table public.saas_customer_operations (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  customer_success_owner text,
  health_status text not null default 'attention' check (health_status in ('healthy','attention','risk')),
  internal_notes text,
  next_action_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.saas_onboarding_progress (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  status text not null default 'not_started' check (status in ('not_started','in_progress','completed')),
  current_step text not null default 'identity',
  completed_steps jsonb not null default '[]'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.platform_audit_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  ip_address inet,
  created_at timestamptz not null default now()
);
create index platform_audit_events_created_idx on public.platform_audit_events(created_at desc);
create index platform_audit_events_entity_idx on public.platform_audit_events(entity_type,entity_id,created_at desc);

alter table public.saas_organization_invites enable row level security;
alter table public.saas_customer_operations enable row level security;
alter table public.saas_onboarding_progress enable row level security;
alter table public.platform_audit_events enable row level security;

create policy platform_audit_events_read_operator on public.platform_audit_events for select to authenticated
using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));

create or replace function private.require_platform_manager()
returns void language plpgsql stable security definer set search_path=''
as $$ begin
  if not private.has_aal2() or not private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]) then
    raise exception 'platform_manager_required' using errcode='42501';
  end if;
end $$;

create or replace function private.platform_organizations_overview()
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
  if not private.has_aal2() or not private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]) then
    raise exception 'platform_operator_required' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(result) order by result.created_at desc) from (
    select o.id,o.name,coalesce(o.app_name,o.name) app_name,o.slug,o.primary_color,o.senior_pastor_name,o.created_at,
      s.status subscription_status,s.app_addon,s.trial_ends_at,s.current_period_end,p.id plan_id,p.name plan_name,p.code plan_code,p.base_price_cents,
      (select count(*) from public.organization_units u where u.organization_id=o.id and u.status='active') units_count,
      (select count(*) from public.people pe where pe.organization_id=o.id and pe.status<>'rejected') people_count,
      (select count(*) from public.organization_memberships m where m.organization_id=o.id and m.status='active') users_count,
      i.owner_name,i.owner_email,i.status invite_status,i.invite_token,
      false billing_profile_complete,coalesce(ob.status,'not_started') onboarding_status,coalesce(ob.current_step,'identity') onboarding_step,
      coalesce(ob.completed_steps,'[]'::jsonb) onboarding_completed_steps,op.customer_success_owner,coalesce(op.health_status,'attention') health_status,
      op.internal_notes,op.next_action_at
    from public.organizations o
    left join public.saas_subscriptions s on s.organization_id=o.id
    left join public.saas_plans p on p.id=s.plan_id
    left join public.saas_customer_operations op on op.organization_id=o.id
    left join public.saas_onboarding_progress ob on ob.organization_id=o.id
    left join lateral (select x.owner_name,x.owner_email,x.status,x.invite_token from public.saas_organization_invites x where x.organization_id=o.id order by x.created_at desc limit 1) i on true
  ) result),'[]'::jsonb);
end $$;

create or replace function private.create_platform_organization(p_name text,p_owner_name text,p_owner_email text,p_plan_id text,p_app_addon boolean default false,p_app_name text default null,p_primary_color text default '#285c45',p_senior_pastor_name text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare
  v_org_id uuid:=extensions.gen_random_uuid(); v_unit_id uuid:=extensions.gen_random_uuid(); v_subscription_id uuid:=extensions.gen_random_uuid();
  v_token uuid:=extensions.gen_random_uuid(); v_slug text; v_base_slug text; v_suffix integer:=1; v_trial timestamptz:=now()+interval '30 days';
begin
  perform private.require_platform_manager();
  if char_length(trim(p_name)) not between 2 and 120 or char_length(trim(p_owner_name))<2 or position('@' in lower(trim(p_owner_email)))<2 then raise exception 'invalid_organization_data' using errcode='22023'; end if;
  if not exists(select 1 from public.saas_plans where id=p_plan_id and active) then raise exception 'invalid_plan' using errcode='22023'; end if;
  v_base_slug:=trim(both '-' from regexp_replace(translate(lower(trim(p_name)),'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),'[^a-z0-9]+','-','g')); v_slug:=v_base_slug;
  while exists(select 1 from public.organizations where slug=v_slug) loop v_suffix:=v_suffix+1; v_slug:=v_base_slug||'-'||v_suffix; end loop;
  insert into public.organizations(id,name,app_name,slug,status,primary_color,senior_pastor_name) values(v_org_id,trim(p_name),coalesce(nullif(trim(p_app_name),''),trim(p_name)),v_slug,'trial',p_primary_color,coalesce(nullif(trim(p_senior_pastor_name),''),trim(p_owner_name)));
  insert into public.organization_units(id,organization_id,name,slug,unit_type,status,pastor_name,financial_autonomy,communication_autonomy,branding_autonomy) values(v_unit_id,v_org_id,trim(p_name),'sede','headquarters','active',coalesce(nullif(trim(p_senior_pastor_name),''),trim(p_owner_name)),true,true,true);
  insert into public.saas_subscriptions(id,organization_id,plan_id,status,app_addon,trial_ends_at) values(v_subscription_id,v_org_id,p_plan_id,'trialing',p_app_addon,v_trial);
  insert into public.saas_subscription_modules(subscription_id,module_code) select v_subscription_id,module_code from public.saas_plan_modules where plan_id=p_plan_id and included;
  if p_app_addon then insert into public.saas_subscription_modules(subscription_id,module_code) values(v_subscription_id,'custom_app') on conflict do nothing; end if;
  insert into public.saas_organization_invites(organization_id,owner_name,owner_email,invite_token,created_by) values(v_org_id,trim(p_owner_name),lower(trim(p_owner_email)),v_token,auth.uid());
  insert into public.saas_customer_operations(organization_id) values(v_org_id);
  insert into public.saas_onboarding_progress(organization_id) values(v_org_id);
  insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'organization.created','organization',v_org_id::text,jsonb_build_object('name',trim(p_name),'owner_email',lower(trim(p_owner_email)),'plan_id',p_plan_id,'app_addon',p_app_addon));
  return jsonb_build_object('id',v_org_id,'slug',v_slug,'trial_ends_at',v_trial,'invite_token',v_token);
end $$;

create or replace function private.update_platform_organization(p_organization_id uuid,p_patch jsonb)
returns void language plpgsql security definer set search_path=''
as $$ begin
  perform private.require_platform_manager();
  if not exists(select 1 from public.organizations where id=p_organization_id) then raise exception 'organization_not_found' using errcode='P0002'; end if;
  if p_patch ? 'planId' and not exists(select 1 from public.saas_plans where id=p_patch->>'planId' and active) then raise exception 'invalid_plan' using errcode='22023'; end if;
  update public.organizations set name=coalesce(nullif(trim(p_patch->>'name'),''),name),app_name=coalesce(nullif(trim(p_patch->>'appName'),''),app_name),primary_color=coalesce(nullif(p_patch->>'primaryColor',''),primary_color),senior_pastor_name=coalesce(nullif(trim(p_patch->>'seniorPastorName'),''),senior_pastor_name) where id=p_organization_id;
  update public.saas_subscriptions set plan_id=coalesce(p_patch->>'planId',plan_id),status=coalesce(p_patch->>'status',status),app_addon=case when p_patch ? 'appAddon' then (p_patch->>'appAddon')::boolean else app_addon end,trial_ends_at=case when p_patch ? 'trialEndsAt' then to_timestamp((p_patch->>'trialEndsAt')::double precision/1000) else trial_ends_at end,updated_at=now() where organization_id=p_organization_id;
  update public.saas_organization_invites set owner_name=coalesce(nullif(trim(p_patch->>'ownerName'),''),owner_name),owner_email=coalesce(nullif(lower(trim(p_patch->>'ownerEmail')),''),owner_email) where id=(select id from public.saas_organization_invites where organization_id=p_organization_id order by created_at desc limit 1);
  insert into public.saas_customer_operations(organization_id,customer_success_owner,health_status,internal_notes,next_action_at) values(p_organization_id,nullif(trim(p_patch->>'customerSuccessOwner'),''),coalesce(nullif(p_patch->>'healthStatus',''),'attention'),nullif(trim(p_patch->>'internalNotes'),''),case when nullif(p_patch->>'nextActionAt','') is null then null else to_timestamp((p_patch->>'nextActionAt')::double precision/1000) end) on conflict(organization_id) do update set customer_success_owner=excluded.customer_success_owner,health_status=excluded.health_status,internal_notes=excluded.internal_notes,next_action_at=excluded.next_action_at,updated_at=now();
  insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'organization.updated','organization',p_organization_id::text,p_patch);
end $$;

create or replace function private.regenerate_platform_organization_invite(p_organization_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_latest public.saas_organization_invites; v_token uuid:=extensions.gen_random_uuid(); begin
  perform private.require_platform_manager();
  select * into v_latest from public.saas_organization_invites where organization_id=p_organization_id order by created_at desc limit 1;
  if v_latest.id is null then raise exception 'invite_not_found' using errcode='P0002'; end if;
  update public.saas_organization_invites set status='revoked' where organization_id=p_organization_id and status='pending';
  insert into public.saas_organization_invites(organization_id,owner_name,owner_email,invite_token,created_by) values(p_organization_id,v_latest.owner_name,v_latest.owner_email,v_token,auth.uid());
  insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'organization.invite_regenerated','organization',p_organization_id::text,jsonb_build_object('owner_email',v_latest.owner_email));
  return v_token;
end $$;

create or replace function public.platform_organizations_overview() returns jsonb language sql security invoker set search_path='' as $$ select private.platform_organizations_overview() $$;
create or replace function public.create_platform_organization(p_name text,p_owner_name text,p_owner_email text,p_plan_id text,p_app_addon boolean default false,p_app_name text default null,p_primary_color text default '#285c45',p_senior_pastor_name text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.create_platform_organization(p_name,p_owner_name,p_owner_email,p_plan_id,p_app_addon,p_app_name,p_primary_color,p_senior_pastor_name) $$;
create or replace function public.update_platform_organization(p_organization_id uuid,p_patch jsonb) returns void language sql security invoker set search_path='' as $$ select private.update_platform_organization(p_organization_id,p_patch) $$;
create or replace function public.regenerate_platform_organization_invite(p_organization_id uuid) returns uuid language sql security invoker set search_path='' as $$ select private.regenerate_platform_organization_invite(p_organization_id) $$;

grant select on public.platform_audit_events to authenticated;
revoke all on public.saas_organization_invites,public.saas_customer_operations,public.saas_onboarding_progress,public.platform_audit_events from anon;
revoke all on function private.require_platform_manager(),private.platform_organizations_overview(),private.create_platform_organization(text,text,text,text,boolean,text,text,text),private.update_platform_organization(uuid,jsonb),private.regenerate_platform_organization_invite(uuid) from public,anon;
grant execute on function private.require_platform_manager(),private.platform_organizations_overview(),private.create_platform_organization(text,text,text,text,boolean,text,text,text),private.update_platform_organization(uuid,jsonb),private.regenerate_platform_organization_invite(uuid) to authenticated;
revoke all on function public.platform_organizations_overview(),public.create_platform_organization(text,text,text,text,boolean,text,text,text),public.update_platform_organization(uuid,jsonb),public.regenerate_platform_organization_invite(uuid) from public,anon;
grant execute on function public.platform_organizations_overview(),public.create_platform_organization(text,text,text,text,boolean,text,text,text),public.update_platform_organization(uuid,jsonb),public.regenerate_platform_organization_invite(uuid) to authenticated;
