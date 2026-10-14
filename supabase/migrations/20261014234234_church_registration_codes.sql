-- Public-facing registration numbers; UUIDs remain all internal primary keys.
create sequence public.church_registration_code_seq as bigint minvalue 1000 start 1000 no cycle;
revoke all on sequence public.church_registration_code_seq from public,anon,authenticated;
grant usage on sequence public.church_registration_code_seq to authenticated,service_role;
alter table public.organizations add column registration_code bigint;
alter table public.organization_units add column registration_code bigint;
-- Allocate existing ministries first in stable creation order.
do $$ declare r record; begin
 for r in select id from public.organizations order by created_at,id loop
  update public.organizations set registration_code=nextval('public.church_registration_code_seq') where id=r.id;
 end loop;
 update public.organization_units u set registration_code=o.registration_code from public.organizations o where o.id=u.organization_id and u.unit_type='headquarters';
 for r in select id from public.organization_units where registration_code is null order by created_at,id loop
  update public.organization_units set registration_code=nextval('public.church_registration_code_seq') where id=r.id;
 end loop;
end $$;
alter table public.organizations alter column registration_code set not null;
alter table public.organizations add constraint organizations_registration_code_unique unique(registration_code);
alter table public.organizations add constraint organizations_registration_code_min check(registration_code>=1000);
alter table public.organization_units alter column registration_code set not null;
alter table public.organization_units add constraint units_registration_code_unique unique(registration_code);
alter table public.organization_units add constraint units_registration_code_min check(registration_code>=1000);

create function private.assign_church_registration_code() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.registration_code is distinct from old.registration_code then raise exception 'registration_code_immutable' using errcode='22023'; end if;
  return new;
 end if;
 if tg_table_name='organization_units' and new.unit_type='headquarters' then
  select registration_code into new.registration_code from public.organizations where id=new.organization_id;
 else new.registration_code:=nextval('public.church_registration_code_seq');
 end if;
 return new;
end $$;
-- No callable Data API endpoint; RLS still authorizes each table write.
revoke all on function private.assign_church_registration_code() from public,anon,authenticated;
create trigger assign_registration_code before insert or update of registration_code on public.organizations for each row execute function private.assign_church_registration_code();
create trigger assign_registration_code before insert or update of registration_code on public.organization_units for each row execute function private.assign_church_registration_code();
comment on column public.organizations.registration_code is 'Permanent public identifier allocated at creation from 1000; not an authorization credential.';
comment on column public.organization_units.registration_code is 'Permanent public identifier; headquarters reuses its ministry code, other units receive their own.';

-- Add the code to the existing, permission-checked overview without changing authorization.
create or replace function private.platform_organizations_overview()
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
  if not private.has_aal2() or not private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]) then
    raise exception 'platform_operator_required' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(result) order by result.created_at desc) from (
    select o.id,o.registration_code,o.name,coalesce(o.app_name,o.name) app_name,o.slug,o.primary_color,o.senior_pastor_name,o.created_at,
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
