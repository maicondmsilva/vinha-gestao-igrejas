-- Central operations use organization UUIDs. church_id is retained only in
-- response-compatible operational tables; every FK points to organizations.
alter table public.organizations add column if not exists accent_color text not null default '#d9b960' check (accent_color ~ '^#[0-9A-Fa-f]{6}$');

create table public.saas_billing_profiles (
 church_id uuid primary key references public.organizations(id), legal_name text not null, tax_id text not null,
 email text not null, phone text, postal_code text, address text, address_number text, district text, city text, state text,
 created_at bigint not null, updated_at bigint not null
);
create table public.saas_billing_provider_settings (
 id uuid primary key default extensions.gen_random_uuid(), provider text unique not null check(provider in ('asaas','mercado_pago','safe2pay')),
 environment text not null check(environment in ('sandbox','production')), status text not null default 'inactive' check(status in ('active','inactive')),
 is_primary boolean not null default false, credential_ciphertext text, credential_iv text, credential_hint text,
 webhook_token_ciphertext text, webhook_token_iv text, webhook_token_hint text, last_tested_at bigint, last_test_status text,
 created_at bigint not null, updated_at bigint not null
);
create unique index saas_one_primary_provider on public.saas_billing_provider_settings(is_primary) where is_primary;
create table public.saas_billing_responsibilities (
 church_id uuid primary key references public.organizations(id), payer_church_id uuid not null references public.organizations(id),
 billing_mode text not null check(billing_mode in ('individual','centralized')), updated_at bigint not null
);
create index billing_responsibilities_payer_idx on public.saas_billing_responsibilities(payer_church_id);
create table public.saas_invoices (
 id uuid primary key default extensions.gen_random_uuid(), church_id uuid not null references public.organizations(id),
 subscription_id uuid not null references public.saas_subscriptions(id), reference_month text not null check(reference_month ~ '^\d{4}-\d{2}$'),
 due_at bigint not null, amount_cents bigint not null check(amount_cents>=0), status text not null default 'open' check(status in ('open','paid','cancelled')),
 payer_church_id uuid not null references public.organizations(id), paid_at bigint, provider text, provider_invoice_id text, payment_url text, checkout_expires_at bigint,
 created_at bigint not null, updated_at bigint not null, unique(subscription_id,reference_month)
);
create index invoices_church_idx on public.saas_invoices(church_id);
create index invoices_payer_idx on public.saas_invoices(payer_church_id,reference_month);
create table public.saas_consolidated_invoices (
 id uuid primary key default extensions.gen_random_uuid(), payer_church_id uuid not null references public.organizations(id), reference_month text not null,
 due_at bigint not null, amount_cents bigint not null check(amount_cents>=0), status text not null default 'open' check(status in ('open','paid','cancelled')),
 paid_at bigint, provider text, provider_invoice_id text, payment_url text, checkout_expires_at bigint,
 created_at bigint not null, updated_at bigint not null, unique(payer_church_id,reference_month)
);
create table public.saas_consolidated_invoice_items (
 id uuid primary key default extensions.gen_random_uuid(), consolidated_invoice_id uuid not null references public.saas_consolidated_invoices(id),
 invoice_id uuid not null unique references public.saas_invoices(id), amount_cents bigint not null, created_at bigint not null
);
create index consolidated_items_parent_idx on public.saas_consolidated_invoice_items(consolidated_invoice_id);
create table public.saas_billing_events (
 id uuid primary key default extensions.gen_random_uuid(), provider text not null, external_event_id text not null,
 invoice_id uuid references public.saas_invoices(id), event_type text not null, payload jsonb not null default '{}', processed_at bigint not null,
 unique(provider,external_event_id)
);
create index billing_events_invoice_idx on public.saas_billing_events(invoice_id);
create table public.saas_organization_links (
 id uuid primary key default extensions.gen_random_uuid(), parent_church_id uuid not null references public.organizations(id), child_church_id uuid not null references public.organizations(id),
 relationship_type text not null default 'daughter', status text not null default 'active' check(status in ('active','inactive')),
 linked_at bigint not null, unlinked_at bigint, created_by uuid references auth.users(id), check(parent_church_id<>child_church_id)
);
create unique index organization_links_one_parent_idx on public.saas_organization_links(child_church_id) where status='active';
create index organization_links_parent_idx on public.saas_organization_links(parent_church_id);
create index organization_links_creator_idx on public.saas_organization_links(created_by);
create table public.saas_hierarchy_requests (
 id uuid primary key default extensions.gen_random_uuid(), parent_church_id uuid not null references public.organizations(id), child_church_id uuid not null references public.organizations(id),
 billing_mode text not null check(billing_mode in ('individual','centralized')), status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_by uuid references auth.users(id), parent_approved_at bigint, child_approved_at bigint, created_at bigint not null,
 check(parent_church_id<>child_church_id)
);
create unique index hierarchy_request_pending_idx on public.saas_hierarchy_requests(child_church_id) where status='pending';
create index hierarchy_requests_parent_idx on public.saas_hierarchy_requests(parent_church_id);
create index hierarchy_requests_actor_idx on public.saas_hierarchy_requests(requested_by);
create table public.saas_support_tickets (
 id uuid primary key default extensions.gen_random_uuid(), number bigint generated always as identity unique,
 code text generated always as ('VIN-'||lpad(number::text,6,'0')) stored,
 church_id uuid not null references public.organizations(id), category text not null default 'general',
 priority text not null check(priority in ('low','medium','high','critical')), status text not null default 'new' check(status in ('new','open','waiting_customer','resolved','closed')),
 subject text not null check(length(trim(subject))>0), description text not null,
 requester_name text, requester_email text, assigned_platform_user_id uuid references public.platform_operators(user_id),
 sla_due_at bigint not null, first_response_at bigint, resolved_at bigint, customer_rating integer check(customer_rating between 1 and 5), customer_feedback text,
 created_at bigint not null, updated_at bigint not null
);
create index support_tickets_church_idx on public.saas_support_tickets(church_id);
create index support_tickets_assigned_idx on public.saas_support_tickets(assigned_platform_user_id);
create table public.saas_support_messages (
 id uuid primary key default extensions.gen_random_uuid(), ticket_id uuid not null references public.saas_support_tickets(id),
 author_platform_user_id uuid references public.platform_operators(user_id), author_name text not null, body text not null check(length(trim(body))>0),
 internal boolean not null default false, created_at bigint not null
);
create index support_messages_ticket_idx on public.saas_support_messages(ticket_id,created_at);
create index support_messages_author_idx on public.saas_support_messages(author_platform_user_id);
create table public.saas_support_articles (
 id uuid primary key default extensions.gen_random_uuid(), slug text not null unique, category text not null, title text not null, summary text not null, body text not null,
 keywords text, featured boolean not null default false, active boolean not null default true, created_at bigint not null, updated_at bigint not null
);
create table public.saas_lifecycle_rules (
 code text primary key, name text not null, description text not null, enabled boolean not null default true,
 threshold_days integer not null check(threshold_days between 0 and 90), priority text not null check(priority in ('low','medium','high','critical')), updated_at bigint not null
);
create table public.saas_customer_tasks (
 id uuid primary key default extensions.gen_random_uuid(), church_id uuid not null references public.organizations(id), rule_code text not null,
 title text not null, description text, priority text not null check(priority in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','in_progress','done','dismissed')), due_at bigint, assigned_to text,
 source_key text unique, completed_at bigint, created_at bigint not null, updated_at bigint not null
);
create index customer_tasks_church_idx on public.saas_customer_tasks(church_id);
create table public.saas_notification_channels (
 channel text primary key check(channel in ('email','push','whatsapp')), provider text not null, enabled boolean not null default false, status text not null default 'inactive',
 default_recipient text, sender_name text, sender_address text, credential_ciphertext text, credential_iv text, credential_hint text, provider_config jsonb not null default '{}',
 last_tested_at bigint, last_test_status text, updated_at bigint not null
);
create table public.saas_lifecycle_templates (
 id uuid primary key default extensions.gen_random_uuid(), rule_code text not null references public.saas_lifecycle_rules(code), channel text not null references public.saas_notification_channels(channel),
 subject text, body text not null, enabled boolean not null default true, updated_at bigint not null, unique(rule_code,channel)
);
create index lifecycle_templates_channel_idx on public.saas_lifecycle_templates(channel);
create table public.saas_lifecycle_deliveries (
 id uuid primary key default extensions.gen_random_uuid(), task_id uuid not null references public.saas_customer_tasks(id), channel text not null references public.saas_notification_channels(channel),
 recipient_address text, subject text, body text not null, status text not null default 'queued' check(status in ('queued','sending','delivered','retry','failed','waiting_configuration')),
 attempts integer not null default 0, provider_message_id text, sent_at bigint, last_error text, next_attempt_at bigint,
 created_at bigint not null, updated_at bigint not null, unique(task_id,channel)
);
create index lifecycle_deliveries_channel_idx on public.saas_lifecycle_deliveries(channel);
create table public.saas_lifecycle_runs (
 id uuid primary key default extensions.gen_random_uuid(), trigger_type text not null, status text not null check(status in ('running','completed','failed')),
 tasks_created integer not null default 0, alerts_created integer not null default 0, alerts_delivered integer not null default 0,
 alerts_pending integer not null default 0, alerts_failed integer not null default 0, started_at bigint not null, finished_at bigint, error_message text
);

-- Central data is inaccessible to anonymous visitors and church users.
do $$ declare t text; begin
 foreach t in array array['saas_billing_profiles','saas_billing_provider_settings','saas_billing_responsibilities','saas_invoices','saas_consolidated_invoices','saas_consolidated_invoice_items','saas_billing_events','saas_organization_links','saas_hierarchy_requests','saas_support_tickets','saas_support_messages','saas_support_articles','saas_lifecycle_rules','saas_customer_tasks','saas_notification_channels','saas_lifecycle_templates','saas_lifecycle_deliveries','saas_lifecycle_runs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
  execute format('create policy central_read on public.%I for select to authenticated using (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'',''support'',''read_only'']::public.platform_operator_role[]))',t);
  execute format('create policy central_write on public.%I for all to authenticated using (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array[''owner'',''admin'']::public.platform_operator_role[]))',t);
 end loop;
end $$;
grant usage on sequence public.saas_support_tickets_number_seq to authenticated;
-- Encrypted credentials are visible only to managers, not support/read-only.
drop policy central_read on public.saas_billing_provider_settings;
drop policy central_read on public.saas_notification_channels;

insert into public.saas_lifecycle_rules values
 ('trial_ending','Fim da avaliação','Acompanhar clientes próximos do fim do teste.',true,7,'high',0),
 ('onboarding_stalled','Configuração parada','Retomar configurações sem avanço.',true,3,'medium',0),
 ('payment_overdue','Pagamento vencido','Acompanhar cobranças em aberto.',true,1,'high',0);
insert into public.saas_notification_channels(channel,provider,updated_at) values ('email','resend',0),('push','firebase',0),('whatsapp','meta_whatsapp',0);
insert into public.saas_lifecycle_templates(rule_code,channel,subject,body,updated_at)
 select r.code,c.channel,'Vinha: {{tarefa}}','{{igreja}}: {{tarefa}}. Prazo: {{data}}.',0 from public.saas_lifecycle_rules r cross join public.saas_notification_channels c;

create policy onboarding_tenant_read on public.saas_onboarding_progress for select to authenticated
 using(private.has_organization_role(organization_id,array['owner','admin','pastor']::public.membership_role[]));
create policy onboarding_tenant_insert on public.saas_onboarding_progress for insert to authenticated
 with check(private.has_organization_role(organization_id,array['owner','admin','pastor']::public.membership_role[]));
create policy onboarding_tenant_update on public.saas_onboarding_progress for update to authenticated
 using(private.has_organization_role(organization_id,array['owner','admin','pastor']::public.membership_role[]))
 with check(private.has_organization_role(organization_id,array['owner','admin','pastor']::public.membership_role[]));

create function public.save_organization_onboarding(p_organization_id uuid,p_data jsonb) returns jsonb
 language plpgsql security invoker set search_path='' as $$
 declare step text:=p_data->>'step'; done jsonb; next_step text; begin
 if auth.uid() is null or not private.has_organization_role(p_organization_id,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'organization_access_denied' using errcode='42501'; end if;
 if step is null or step not in ('identity','headquarters','structure','people','completed') then raise exception 'invalid_step'; end if;
 insert into public.saas_onboarding_progress(organization_id,status,started_at) values(p_organization_id,'in_progress',now()) on conflict do nothing;
 select completed_steps into done from public.saas_onboarding_progress where organization_id=p_organization_id for update;
 if step='identity' then
  if length(trim(coalesce(p_data->>'name','')))<2 or length(trim(coalesce(p_data->>'appName','')))<2 or length(trim(coalesce(p_data->>'seniorPastorName','')))<2 or coalesce(p_data->>'primaryColor','') !~ '^#[0-9A-Fa-f]{6}$' or coalesce(p_data->>'accentColor','') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid_identity'; end if;
  update public.organizations set name=trim(p_data->>'name'),app_name=trim(p_data->>'appName'),senior_pastor_name=trim(p_data->>'seniorPastorName'),primary_color=p_data->>'primaryColor',accent_color=p_data->>'accentColor' where id=p_organization_id;
 elsif step='headquarters' then
  if not done ? 'identity' then raise exception 'complete_identity_first'; end if;
  if length(trim(coalesce(p_data->>'name','')))<2 or length(trim(coalesce(p_data->>'pastorName','')))<2 or position('@' in coalesce(p_data->>'email',''))<2 then raise exception 'invalid_headquarters'; end if;
  update public.organization_units set name=trim(p_data->>'name'),legal_name=p_data->>'legalName',tax_id=p_data->>'taxId',pastor_name=p_data->>'pastorName',email=lower(trim(p_data->>'email')),phone=p_data->>'phone',address=jsonb_build_object('postal_code',p_data->>'postalCode','street',p_data->>'street','number',p_data->>'number','complement',p_data->>'complement','district',p_data->>'district','city',p_data->>'city','state',upper(p_data->>'state')) where organization_id=p_organization_id and unit_type='headquarters';
  if not found then raise exception 'headquarters_not_found'; end if;
 elsif step in ('structure','people','completed') then
  if not done ?& array['identity','headquarters'] then raise exception 'complete_required_steps'; end if;
 end if;
 if not done ? step then done:=done||jsonb_build_array(step); end if;
 next_step:=case step when 'identity' then 'headquarters' when 'headquarters' then 'structure' when 'structure' then 'people' else 'completed' end;
 update public.saas_onboarding_progress set completed_steps=done,current_step=next_step,status=case when step='completed' then 'completed' else 'in_progress' end,completed_at=case when step='completed' then now() else null end,updated_at=now() where organization_id=p_organization_id;
 return jsonb_build_object('ok',true,'nextStep',next_step,'completed',done);
 end $$;
revoke all on function public.save_organization_onboarding(uuid,jsonb) from public,anon;
grant execute on function public.save_organization_onboarding(uuid,jsonb) to authenticated;

-- Auto-registration obtains the same initial subscription as Central-created
-- customers. This trigger has no callable API and cannot change existing plans.
create function private.seed_organization_commercial_state() returns trigger language plpgsql security definer set search_path='' as $$
 declare sid uuid; pid text; begin
 if new.role<>'owner' or new.status<>'active' then return new; end if;
 select id into pid from public.saas_plans where active order by (code='essential') desc,base_price_cents limit 1;
 if pid is null then raise exception 'no_active_plan'; end if;
 insert into public.saas_subscriptions(organization_id,plan_id,status,app_addon,trial_ends_at) values(new.organization_id,pid,'trialing',false,now()+interval '30 days') on conflict(organization_id) do nothing returning id into sid;
 if sid is not null then insert into public.saas_subscription_modules(subscription_id,module_code) select sid,module_code from public.saas_plan_modules where plan_id=pid and included on conflict do nothing; end if;
 insert into public.saas_onboarding_progress(organization_id) values(new.organization_id) on conflict do nothing;
 insert into public.saas_customer_operations(organization_id) values(new.organization_id) on conflict do nothing;
 return new; end $$;
revoke all on function private.seed_organization_commercial_state() from public,anon,authenticated;
create trigger seed_organization_commercial_state after insert or update of role,status on public.organization_memberships for each row execute function private.seed_organization_commercial_state();

create function public.generate_platform_invoices(p_reference text,p_due bigint,p_organization uuid default null) returns integer
language plpgsql security invoker set search_path='' as $$ declare affected integer; begin
 perform private.require_platform_manager();
 if p_reference !~ '^\d{4}-(0[1-9]|1[0-2])$' or p_due is null then raise exception 'invalid_billing_period'; end if;
 insert into public.saas_invoices(church_id,subscription_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at)
 select s.organization_id,s.id,p_reference,p_due,
 greatest(0,round((p.base_price_cents+coalesce((select sum(c.monthly_price_cents) from public.saas_subscription_modules sm join public.saas_module_catalog c on c.code=sm.module_code where sm.subscription_id=s.id and sm.enabled and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=s.plan_id and pm.module_code=sm.module_code and pm.included)),0))*(1-coalesce(d.custom_percent,0)::numeric/100))-coalesce(d.custom_amount_cents,0)),
 coalesce(r.payer_church_id,s.organization_id),(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint
 from public.saas_subscriptions s join public.saas_plans p on p.id=s.plan_id
 left join public.saas_billing_responsibilities r on r.church_id=s.organization_id
 left join public.saas_subscription_discounts d on d.subscription_id=s.id and (d.valid_until is null or d.valid_until>now())
 where (s.status='active' or (s.status='trialing' and s.trial_ends_at<=now())) and (p_organization is null or s.organization_id=p_organization)
 on conflict(subscription_id,reference_month) do nothing;
 get diagnostics affected=row_count; return affected; end $$;

create function public.consolidate_platform_invoices(p_reference text) returns integer
language plpgsql security invoker set search_path='' as $$ declare g record; cid uuid; affected integer:=0; begin
 perform private.require_platform_manager();
 perform pg_advisory_xact_lock(hashtext('consolidate:'||p_reference));
 for g in select i.payer_church_id,min(i.due_at) due_at,sum(i.amount_cents) amount_cents from public.saas_invoices i where i.reference_month=p_reference and i.status='open' and i.payment_url is null and not exists(select 1 from public.saas_consolidated_invoice_items x where x.invoice_id=i.id) group by i.payer_church_id having count(*)>1 loop
  insert into public.saas_consolidated_invoices(payer_church_id,reference_month,due_at,amount_cents,created_at,updated_at) values(g.payer_church_id,p_reference,g.due_at,g.amount_cents,(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint) on conflict(payer_church_id,reference_month) do nothing returning id into cid;
  if cid is null then continue; end if;
  insert into public.saas_consolidated_invoice_items(consolidated_invoice_id,invoice_id,amount_cents,created_at) select cid,i.id,i.amount_cents,(extract(epoch from now())*1000)::bigint from public.saas_invoices i where i.payer_church_id=g.payer_church_id and i.reference_month=p_reference and i.status='open' and i.payment_url is null and not exists(select 1 from public.saas_consolidated_invoice_items x where x.invoice_id=i.id);
  affected:=affected+1;
 end loop; return affected; end $$;

create function public.set_platform_primary_provider(p_provider text) returns void
language plpgsql security invoker set search_path='' as $$ begin
 perform private.require_platform_manager(); perform pg_advisory_xact_lock(hashtext('primary-provider'));
 if not exists(select 1 from public.saas_billing_provider_settings where provider=p_provider and status='active' and last_test_status='success') then raise exception 'test_provider_first'; end if;
 update public.saas_billing_provider_settings set is_primary=false where is_primary;
 update public.saas_billing_provider_settings set is_primary=true where provider=p_provider;
end $$;

create function public.change_platform_hierarchy(p_action text,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare parent_id uuid:=nullif(p_data->>'parentChurchId','')::uuid; child_id uuid:=nullif(p_data->>'childChurchId','')::uuid; mode text:=coalesce(p_data->>'billingMode','individual'); stamp bigint:=(extract(epoch from now())*1000)::bigint; begin
 perform private.require_platform_manager(); perform pg_advisory_xact_lock(hashtext('organization-hierarchy'));
 if child_id is null or mode not in ('individual','centralized') then raise exception 'invalid_hierarchy'; end if;
 if p_action='unlink' then
  update public.saas_organization_links set status='inactive',unlinked_at=stamp where child_church_id=child_id and status='active'; parent_id:=child_id; mode:='individual';
 elsif p_action='billing' then
  select parent_church_id into parent_id from public.saas_organization_links where child_church_id=child_id and status='active';
  if parent_id is null then raise exception 'link_not_found'; end if;
 elsif p_action in ('link','request') then
  if parent_id is null or parent_id=child_id then raise exception 'invalid_hierarchy'; end if;
  if exists(select 1 from public.saas_organization_links where child_church_id=child_id and status='active') then raise exception 'child_already_linked'; end if;
  if exists(with recursive descendants(id) as (select child_church_id from public.saas_organization_links where parent_church_id=child_id and status='active' union select l.child_church_id from public.saas_organization_links l join descendants d on l.parent_church_id=d.id where l.status='active') select 1 from descendants where id=parent_id) then raise exception 'hierarchy_cycle'; end if;
  if p_action='request' then
   insert into public.saas_hierarchy_requests(parent_church_id,child_church_id,billing_mode,requested_by,created_at) values(parent_id,child_id,mode,auth.uid(),stamp); return jsonb_build_object('ok',true);
  end if;
  -- New relationships require both church owners to approve. Operators create
  -- requests; this API cannot bypass the two approvals.
  raise exception 'use_hierarchy_request';
 else raise exception 'invalid_action'; end if;
 insert into public.saas_billing_responsibilities(church_id,payer_church_id,billing_mode,updated_at) values(child_id,case when mode='centralized' then parent_id else child_id end,mode,stamp) on conflict(church_id) do update set payer_church_id=excluded.payer_church_id,billing_mode=excluded.billing_mode,updated_at=excluded.updated_at;
 return jsonb_build_object('ok',true); end $$;

revoke all on function public.generate_platform_invoices(text,bigint,uuid),public.consolidate_platform_invoices(text),public.set_platform_primary_provider(text),public.change_platform_hierarchy(text,jsonb) from public,anon;
grant execute on function public.generate_platform_invoices(text,bigint,uuid),public.consolidate_platform_invoices(text),public.set_platform_primary_provider(text),public.change_platform_hierarchy(text,jsonb) to authenticated;

create function public.record_platform_invoice_status(p_invoice uuid,p_status text) returns void
language plpgsql security invoker set search_path='' as $$ declare sid uuid; begin
 perform private.require_platform_manager();
 if p_status not in ('paid','cancelled') then raise exception 'invalid_status'; end if;
 update public.saas_invoices set status=p_status,paid_at=case when p_status='paid' then (extract(epoch from now())*1000)::bigint else null end,updated_at=(extract(epoch from now())*1000)::bigint where id=p_invoice and status='open' returning subscription_id into sid;
 if sid is null then raise exception 'invoice_not_open'; end if;
 if p_status='paid' then update public.saas_subscriptions set status='active',current_period_end=now()+interval '1 month',updated_at=now() where id=sid; end if;
end $$;
revoke all on function public.record_platform_invoice_status(uuid,text) from public,anon;
grant execute on function public.record_platform_invoice_status(uuid,text) to authenticated;

create policy hierarchy_request_participant on public.saas_hierarchy_requests for select to authenticated using (
 private.has_organization_role(parent_church_id,array['owner','admin','pastor']::public.membership_role[]) or
 private.has_organization_role(child_church_id,array['owner','admin','pastor']::public.membership_role[]));

create function public.approve_organization_hierarchy(p_request uuid,p_organization uuid,p_decision text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.saas_hierarchy_requests; stamp bigint:=(extract(epoch from now())*1000)::bigint; begin
 if auth.uid() is null or not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'organization_access_denied' using errcode='42501'; end if;
 if p_decision not in ('approve','reject') then raise exception 'invalid_decision'; end if;
 perform pg_advisory_xact_lock(hashtext('organization-hierarchy'));
 select * into r from public.saas_hierarchy_requests where id=p_request for update;
 if r.id is null or p_organization not in (r.parent_church_id,r.child_church_id) then raise exception 'request_not_found' using errcode='42501'; end if;
 if r.status<>'pending' then return jsonb_build_object('ok',true,'status',r.status); end if;
 if p_decision='reject' then update public.saas_hierarchy_requests set status='rejected' where id=r.id; return jsonb_build_object('ok',true,'status','rejected'); end if;
 if p_organization=r.parent_church_id then r.parent_approved_at:=stamp; else r.child_approved_at:=stamp; end if;
 update public.saas_hierarchy_requests set parent_approved_at=r.parent_approved_at,child_approved_at=r.child_approved_at where id=r.id;
 if r.parent_approved_at is not null and r.child_approved_at is not null then
  if exists(select 1 from public.saas_organization_links where child_church_id=r.child_church_id and status='active') then raise exception 'child_already_linked'; end if;
  if exists(with recursive descendants(id) as (select child_church_id from public.saas_organization_links where parent_church_id=r.child_church_id and status='active' union select l.child_church_id from public.saas_organization_links l join descendants d on l.parent_church_id=d.id where l.status='active') select 1 from descendants where id=r.parent_church_id) then raise exception 'hierarchy_cycle'; end if;
  insert into public.saas_organization_links(parent_church_id,child_church_id,linked_at,created_by) values(r.parent_church_id,r.child_church_id,stamp,auth.uid());
  insert into public.saas_billing_responsibilities(church_id,payer_church_id,billing_mode,updated_at) values(r.child_church_id,case when r.billing_mode='centralized' then r.parent_church_id else r.child_church_id end,r.billing_mode,stamp) on conflict(church_id) do update set payer_church_id=excluded.payer_church_id,billing_mode=excluded.billing_mode,updated_at=excluded.updated_at;
  update public.saas_hierarchy_requests set status='approved' where id=r.id; r.status:='approved';
 end if;
 return jsonb_build_object('ok',true,'status',r.status);
end $$;
revoke all on function public.approve_organization_hierarchy(uuid,uuid,text) from public,anon;
grant execute on function public.approve_organization_hierarchy(uuid,uuid,text) to authenticated;

-- Participants can see names of organizations on their request without gaining
-- access to the other organization's people, finances or internal records.
create function public.organization_hierarchy_requests(p_organization uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null or not private.has_organization_role(p_organization,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'organization_access_denied' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q)) from (select r.*,p.name parent_name,c.name child_name from public.saas_hierarchy_requests r join public.organizations p on p.id=r.parent_church_id join public.organizations c on c.id=r.child_church_id where p_organization in (r.parent_church_id,r.child_church_id) order by r.created_at desc) q),'[]');
end $$;
revoke all on function public.organization_hierarchy_requests(uuid) from public,anon;
grant execute on function public.organization_hierarchy_requests(uuid) to authenticated;
