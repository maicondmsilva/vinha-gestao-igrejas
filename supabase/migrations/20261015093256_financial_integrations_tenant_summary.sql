-- External recurring/fiscal operations remain sandbox-only until homologation.
create table public.saas_company_profile (
 id boolean primary key default true check(id),
 profile jsonb not null default '{}'::jsonb check(jsonb_typeof(profile)='object'),
 revision integer not null default 1,
 updated_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now()
);
create index company_profile_author_idx on public.saas_company_profile(updated_by);
alter table public.saas_company_profile enable row level security;
revoke all on public.saas_company_profile from anon,authenticated;
grant select on public.saas_company_profile to authenticated;
grant all on public.saas_company_profile to service_role;
create policy company_profile_manager on public.saas_company_profile for all to authenticated using(
 (select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
) with check((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create function private.save_vinha_company(p_profile jsonb,p_revision integer) returns integer
language plpgsql security definer set search_path='' as $$
declare r integer;
begin
 perform private.require_platform_manager();
 if jsonb_typeof(p_profile)<>'object' or octet_length(p_profile::text)>16000 then raise exception 'invalid_profile'; end if;
 insert into public.saas_company_profile(id,profile,revision,updated_by) values(true,p_profile,1,auth.uid())
 on conflict(id) do update set profile=excluded.profile,revision=saas_company_profile.revision+1,updated_by=auth.uid(),updated_at=now()
 where saas_company_profile.revision=p_revision returning revision into r;
 if r is null then raise exception 'Dados alterados por outro operador. Atualize a página.'; end if;
 insert into public.platform_audit_events(actor_user_id,action,entity_type,metadata)
 values(auth.uid(),'company.updated','vinha',jsonb_build_object('revision',r,'profile',p_profile));
 return r;
end $$;
revoke all on function private.save_vinha_company(jsonb,integer) from public,anon;
grant execute on function private.save_vinha_company(jsonb,integer) to authenticated;
create function public.save_vinha_company(p_profile jsonb,p_revision integer) returns integer
language sql security invoker set search_path='' as $$ select private.save_vinha_company(p_profile,p_revision) $$;
revoke all on function public.save_vinha_company(jsonb,integer) from public,anon;
grant execute on function public.save_vinha_company(jsonb,integer) to authenticated;

create table public.saas_financial_operations (
 id uuid primary key default extensions.gen_random_uuid(),
 invoice_id uuid not null references public.saas_invoices(id),
 unit_contract_id uuid references public.saas_unit_contracts(id),
 kind text not null check(kind in ('recurring','fiscal')),
 environment text not null default 'sandbox' check(environment='sandbox'),
 status text not null default 'prepared' check(status in ('prepared','sending','submitted','awaiting_confirmation','active','authorized','cancelled','rejected','uncertain')),
 amount_cents bigint not null check(amount_cents>0),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 provider_id text, subscription_id text, checkout_url text, pdf_url text, xml_url text, last_error text,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(invoice_id,kind,environment), check(kind<>'recurring' or unit_contract_id is not null)
);
create unique index financial_recurring_contract_unique on public.saas_financial_operations(unit_contract_id) where kind='recurring' and status<>'cancelled';
create index financial_operations_created_idx on public.saas_financial_operations(created_at desc);
create index financial_operations_author_idx on public.saas_financial_operations(created_by);
create unique index financial_operations_provider_idx on public.saas_financial_operations(kind,provider_id) where provider_id is not null;
alter table public.saas_financial_operations enable row level security;
revoke all on public.saas_financial_operations from anon,authenticated;
grant select on public.saas_financial_operations to authenticated;
grant all on public.saas_financial_operations to service_role;
create policy financial_operations_read on public.saas_financial_operations for select to authenticated using(
 (select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))
);

create table public.saas_delivery_events (
 provider text not null check(provider in ('resend','meta_whatsapp')), event_id text not null,
 message_id text not null, status text not null check(status in ('delivered','read','bounced','delivery_failed')),
 occurred_at timestamptz not null, created_at timestamptz not null default now(), primary key(provider,event_id)
);
create index delivery_message_idx on public.saas_delivery_events(provider,message_id);
alter table public.saas_delivery_events enable row level security;
revoke all on public.saas_delivery_events from anon,authenticated;
grant all on public.saas_delivery_events to service_role;
alter table public.saas_invoice_notifications drop constraint saas_invoice_notifications_status_check;
alter table public.saas_invoice_notifications add constraint saas_invoice_notifications_status_check check(status in ('pending','waiting_configuration','sending','submitted','failed','cancelled','delivered','read','bounced','delivery_failed'));
create index invoice_notifications_provider_message_idx on public.saas_invoice_notifications(channel,provider_message_id) where provider_message_id is not null;
create function public.record_billing_delivery(p_provider text,p_event text,p_message text,p_status text,p_occurred timestamptz) returns void
language plpgsql security invoker set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'service_required' using errcode='42501'; end if;
 insert into public.saas_delivery_events(provider,event_id,message_id,status,occurred_at)
 values(p_provider,p_event,p_message,p_status,p_occurred) on conflict do nothing;
 update public.saas_invoice_notifications n set status=e.status,updated_at=now(),last_error=null
 from (select status from public.saas_delivery_events where provider=p_provider and message_id=p_message
 order by case status when 'read' then 4 when 'delivered' then 3 else 2 end desc,occurred_at desc limit 1) e
 where n.channel=case p_provider when 'resend' then 'email' else 'whatsapp' end and n.provider_message_id=p_message;
end $$;
revoke all on function public.record_billing_delivery(text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.record_billing_delivery(text,text,text,text,timestamptz) to service_role;

-- A provider can call back before its send response is persisted locally.
create function private.apply_saved_billing_delivery() returns trigger language plpgsql security definer set search_path='' as $$
declare s text;
begin
 if new.provider_message_id is not null then
 select status into s from public.saas_delivery_events
 where provider=case new.channel when 'email' then 'resend' else 'meta_whatsapp' end and message_id=new.provider_message_id
 order by case status when 'read' then 4 when 'delivered' then 3 else 2 end desc,occurred_at desc limit 1;
 if s is not null then new.status=s; end if;
 end if;return new;
end $$;
revoke all on function private.apply_saved_billing_delivery() from public,anon,authenticated;
create trigger invoice_notification_saved_delivery before update of provider_message_id,status on public.saas_invoice_notifications
for each row execute function private.apply_saved_billing_delivery();

create table public.saas_financial_operation_events (
 event_id text primary key,
 operation_id uuid not null references public.saas_financial_operations(id),
 status text not null,created_at timestamptz not null default now()
);
create index financial_operation_events_operation_idx on public.saas_financial_operation_events(operation_id);
alter table public.saas_financial_operation_events enable row level security;
revoke all on public.saas_financial_operation_events from anon,authenticated;
grant all on public.saas_financial_operation_events to service_role;
create function public.apply_financial_sandbox_event(p_id uuid,p_event text,p_patch jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare op public.saas_financial_operations; target text:=p_patch->>'status';
begin
 if auth.role()<>'service_role' then raise exception 'service_required' using errcode='42501'; end if;
 select * into op from public.saas_financial_operations where id=p_id and environment='sandbox' for update;
 if op.id is null then raise exception 'operation_not_found'; end if;
 if target not in ('awaiting_confirmation','active','authorized','cancelled','rejected') then raise exception 'invalid_status'; end if;
 insert into public.saas_financial_operation_events values(p_event,p_id,target,now()) on conflict do nothing;
 if not found or op.status='cancelled' or (op.status='active' and target='awaiting_confirmation') or (op.status='authorized' and target='rejected') then return; end if;
 if (op.kind='fiscal' and target in ('active','awaiting_confirmation')) or (op.kind='recurring' and target in ('authorized','rejected')) then raise exception 'wrong_operation_kind'; end if;
 update public.saas_financial_operations set status=target,subscription_id=coalesce(p_patch->>'subscription_id',subscription_id),pdf_url=coalesce(p_patch->>'pdf_url',pdf_url),xml_url=coalesce(p_patch->>'xml_url',xml_url),updated_at=now() where id=p_id;
end $$;
revoke all on function public.apply_financial_sandbox_event(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.apply_financial_sandbox_event(uuid,text,jsonb) to service_role;

create function private.tenant_subscription_summary(p_organization uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; selected_unit uuid; contract public.saas_unit_contracts;
begin
 if auth.uid() is null or not private.is_organization_member(p_organization) then raise exception 'organization_access_required' using errcode='42501'; end if;
 select selected_unit_id into selected_unit from public.user_access_preferences where user_id=auth.uid() and selected_organization_id=p_organization;
 if selected_unit is null then select default_unit_id into selected_unit from public.organization_memberships where user_id=auth.uid() and organization_id=p_organization and status='active'; end if;
 if selected_unit is null then select id into selected_unit from public.organization_units where organization_id=p_organization and unit_type='headquarters' limit 1; end if;
 select * into contract from public.saas_unit_contracts where organization_id=p_organization and unit_id=selected_unit and status<>'draft';
 select jsonb_build_object(
 'church',jsonb_build_object('id',o.id,'name',o.name,'app_name',o.app_name,'slug',o.slug,'primary_color',o.primary_color,'accent_color',o.accent_color,'senior_pastor_name',o.senior_pastor_name),
 'subscription',(select jsonb_build_object('id',s.id,'status',case when contract.status='suspended' then 'suspended' else s.status end,'unit_contract_id',contract.id,'plan_name',p.name,'plan_description',p.description,'base_price_cents',p.base_price_cents,'app_addon',case when s.app_addon then 1 else 0 end,'trial_ends_at',extract(epoch from s.trial_ends_at)*1000) from public.saas_subscriptions s join public.saas_plans p on p.id=coalesce(contract.plan_id,s.plan_id) where s.organization_id=o.id),
 'modules',coalesce((select jsonb_agg(jsonb_build_object('module_code',case c.code when 'people' then 'members' else c.code end,'enabled',case when (case when contract.id is not null then private.unit_module_enabled(o.id,c.code) else exists(select 1 from public.saas_subscription_modules sm join public.saas_subscriptions ss on ss.id=sm.subscription_id where ss.organization_id=o.id and sm.module_code=c.code and sm.enabled) end) then 1 else 0 end)) from public.saas_module_catalog c where c.active),'[]'::jsonb)
 ) into result from public.organizations o where o.id=p_organization;
 return result;
end $$;
revoke all on function private.tenant_subscription_summary(uuid) from public,anon;
grant execute on function private.tenant_subscription_summary(uuid) to authenticated;
create function public.tenant_subscription_summary(p_organization uuid) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.tenant_subscription_summary(p_organization) $$;
revoke all on function public.tenant_subscription_summary(uuid) from public,anon;
grant execute on function public.tenant_subscription_summary(uuid) to authenticated;
