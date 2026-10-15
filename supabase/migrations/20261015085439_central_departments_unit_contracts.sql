-- Sectors are public directory entries; memberships and transcripts are private.
grant insert on public.platform_audit_events to authenticated;
create policy platform_audit_append_operator on public.platform_audit_events for insert to authenticated with check(actor_user_id=(select auth.uid()) and (select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support']::public.platform_operator_role[])));
create policy units_operator_read on public.organization_units for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])));
create function private.chat_operator_directory() returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is not null and private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]) then
 (select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'full_name',full_name,'role',role,'active',active)),'[]') from public.platform_operators where active) else '[]'::jsonb end
$$;
revoke all on function private.chat_operator_directory() from public,anon,authenticated;
create function public.chat_operator_directory() returns jsonb language sql security definer set search_path='' as $$ select private.chat_operator_directory() $$;
revoke all on function public.chat_operator_directory() from public,anon;
grant execute on function public.chat_operator_directory() to authenticated;
create table public.saas_chat_departments (
 id uuid primary key default extensions.gen_random_uuid(),
 name text not null unique check(length(trim(name)) between 2 and 60),
 active boolean not null default true, created_at timestamptz not null default now()
);
create table public.saas_chat_department_members (
 department_id uuid not null references public.saas_chat_departments(id),
 operator_id uuid not null references public.platform_operators(user_id),
 primary key(department_id,operator_id)
);
create index chat_department_members_operator_idx on public.saas_chat_department_members(operator_id);
insert into public.saas_chat_departments(name) values ('Comercial'),('Suporte'),('Financeiro');
alter table public.saas_chat_conversations add column department_id uuid references public.saas_chat_departments(id);
update public.saas_chat_conversations set department_id=(select id from public.saas_chat_departments where name='Suporte');
alter table public.saas_chat_conversations alter column department_id set not null;
create index chat_conversations_department_idx on public.saas_chat_conversations(department_id,status,last_message_at desc);
alter table public.saas_chat_departments enable row level security;
alter table public.saas_chat_department_members enable row level security;
revoke all on public.saas_chat_departments,public.saas_chat_department_members from public,anon,authenticated;
grant select on public.saas_chat_departments to anon,authenticated;
grant insert,update on public.saas_chat_departments to authenticated;
grant select,insert,delete on public.saas_chat_department_members to authenticated;
create policy department_directory on public.saas_chat_departments for select to anon,authenticated using(active or ((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))));
create policy department_admin on public.saas_chat_departments for all to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))) with check((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create policy department_members_read on public.saas_chat_department_members for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])));
create policy department_members_admin on public.saas_chat_department_members for all to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))) with check((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create function public.save_chat_department(p_id uuid,p_name text,p_active boolean,p_operators uuid[]) returns void language plpgsql security invoker set search_path='' as $$ begin
 perform private.require_platform_manager();
 if not exists(select 1 from public.saas_chat_departments where id=p_id) then raise exception 'department_not_found'; end if;
 if exists(select 1 from unnest(p_operators) x where not exists(select 1 from public.platform_operators o where o.user_id=x and o.active and o.role in ('owner','admin','support','read_only'))) then raise exception 'invalid_operator'; end if;
 if not p_active and exists(select 1 from public.saas_chat_conversations where department_id=p_id and status='open') then raise exception 'Transfira ou encerre os atendimentos antes de desativar o setor.'; end if;
 update public.saas_chat_departments set name=trim(p_name),active=p_active where id=p_id;
 delete from public.saas_chat_department_members where department_id=p_id;
 insert into public.saas_chat_department_members select p_id,x from (select distinct unnest(p_operators) x) q;
end $$;
revoke all on function public.save_chat_department(uuid,text,boolean,uuid[]) from public,anon;
grant execute on function public.save_chat_department(uuid,text,boolean,uuid[]) to authenticated;

create function private.chat_department_access(p_department uuid,p_write boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.has_aal2() and exists(
 select 1 from public.platform_operators o where o.user_id=auth.uid() and o.active and
 (o.role in ('owner','admin') or (o.role in ('support','read_only') and (not p_write or o.role='support') and
 exists(select 1 from public.saas_chat_department_members m where m.operator_id=o.user_id and m.department_id=p_department))))
$$;
revoke all on function private.chat_department_access(uuid,boolean) from public,anon;
grant execute on function private.chat_department_access(uuid,boolean) to authenticated;
drop policy chat_conversations_operator_read on public.saas_chat_conversations;
drop policy chat_conversations_operator_write on public.saas_chat_conversations;
drop policy chat_messages_operator_read on public.saas_chat_messages;
drop policy chat_messages_operator_write on public.saas_chat_messages;
create policy chat_sector_read on public.saas_chat_conversations for select to authenticated using(private.chat_department_access(department_id));
create policy chat_sector_update on public.saas_chat_conversations for update to authenticated using(private.chat_department_access(department_id,true)) with check(private.chat_department_access(department_id,true));
create policy chat_sector_messages_read on public.saas_chat_messages for select to authenticated using(exists(select 1 from public.saas_chat_conversations c where c.id=conversation_id));
create policy chat_sector_messages_insert on public.saas_chat_messages for insert to authenticated with check(sender='team' and author_user_id=(select auth.uid()) and exists(select 1 from public.saas_chat_conversations c where c.id=conversation_id and c.status='open' and private.chat_department_access(c.department_id,true)));

-- Preserve the capability/ownership/rate-limit validation of the existing chat.
alter function private.support_chat(text,uuid,text,jsonb) rename to support_chat_core;
-- The existing core inserts a conversation; a trigger assigns a safe default.
create function private.assign_default_chat_department() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if new.department_id is null then select id into new.department_id from public.saas_chat_departments where active order by (name='Suporte') desc,created_at limit 1; end if;
 if new.department_id is null then raise exception 'chat_department_unavailable'; end if;
 new.operator_last_read_at:='epoch';
 return new; end $$;
revoke all on function private.assign_default_chat_department() from public,anon,authenticated;
create trigger assign_default_chat_department before insert on public.saas_chat_conversations for each row execute function private.assign_default_chat_department();
create function private.support_chat(p_action text,p_id uuid default null,p_secret text default null,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; sector uuid; begin
 if p_action='start' and nullif(p_data->>'departmentId','') is not null then
  select id into sector from public.saas_chat_departments where id=(p_data->>'departmentId')::uuid and active;
  if sector is null then raise exception 'chat_department_unavailable'; end if;
 end if;
 result:=private.support_chat_core(p_action,p_id,p_secret,p_data);
 if p_action='start' and sector is not null then update public.saas_chat_conversations set department_id=sector where id=(result->>'id')::uuid; end if;
 return result;
end $$;
revoke all on function private.support_chat(text,uuid,text,jsonb) from public,anon,authenticated;
-- Rebind wrapper: SQL function bodies may retain the original function OID.
create or replace function public.support_chat(p_action text,p_id uuid default null,p_secret text default null,p_data jsonb default '{}') returns jsonb
language sql security definer set search_path='' as $$ select private.support_chat(p_action,p_id,p_secret,p_data) $$;

create function private.transfer_platform_chat(p_id uuid,p_department uuid,p_operator uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare current_sector uuid; begin
 select department_id into current_sector from public.saas_chat_conversations where id=p_id for update;
 if current_sector is null or not private.chat_department_access(current_sector,true) then raise exception 'chat_access_denied' using errcode='42501'; end if;
 if not exists(select 1 from public.saas_chat_departments where id=p_department and active) then raise exception 'invalid_department'; end if;
 if p_operator is not null and not exists(select 1 from public.platform_operators o where user_id=p_operator and active and role in ('owner','admin','support') and
 (role in ('owner','admin') or exists(select 1 from public.saas_chat_department_members m where m.department_id=p_department and m.operator_id=p_operator))) then raise exception 'operator_outside_department'; end if;
 update public.saas_chat_conversations set department_id=p_department,assigned_operator_id=p_operator,operator_last_read_at='epoch' where id=p_id;
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'chat.transferred','chat_conversation',p_id,jsonb_build_object('from',current_sector,'to',p_department,'operator',p_operator));
end $$;
revoke all on function private.transfer_platform_chat(uuid,uuid,uuid) from public,anon,authenticated;
create function public.transfer_platform_chat(p_id uuid,p_department uuid,p_operator uuid default null) returns void language sql security definer set search_path='' as $$ select private.transfer_platform_chat(p_id,p_department,p_operator) $$;
revoke all on function public.transfer_platform_chat(uuid,uuid,uuid) from public,anon;
grant execute on function public.transfer_platform_chat(uuid,uuid,uuid) to authenticated;

-- Unit contracts do not replace organizations and never move their data.
create table public.saas_unit_contracts (
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null unique, payer_unit_id uuid not null,
 plan_id text not null references public.saas_plans(id),
 status text not null default 'draft' check(status in ('draft','active','suspended')),
 module_decisions jsonb not null default '{}' check(jsonb_typeof(module_decisions)='object'),
 requested_modules text[] not null default '{}', due_day integer not null default 10 check(due_day between 1 and 28),
 financial_profile jsonb not null default '{}' check(jsonb_typeof(financial_profile)='object'),
 email_enabled boolean not null default false, whatsapp_enabled boolean not null default false,
 whatsapp_consent_at timestamptz, whatsapp_number text,
 autopay_requested boolean not null default false,
 updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(payer_unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index unit_contracts_org_idx on public.saas_unit_contracts(organization_id);
create index unit_contracts_payer_idx on public.saas_unit_contracts(payer_unit_id,organization_id);
create index unit_contracts_plan_idx on public.saas_unit_contracts(plan_id);
alter table public.saas_unit_contracts add column requested_due_day integer check(requested_due_day between 1 and 28);
alter table public.saas_unit_contracts add column request_updated_at timestamptz;
alter table public.saas_unit_contracts enable row level security;
revoke all on public.saas_unit_contracts from public,anon,authenticated;
grant select,insert,update on public.saas_unit_contracts to authenticated;
create policy unit_contracts_read on public.saas_unit_contracts for select to authenticated using(((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]))) or private.has_organization_role(organization_id,array['owner','admin']::public.membership_role[]));
create policy unit_contracts_manage on public.saas_unit_contracts for all to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))) with check((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));
create function public.save_unit_contract(p_data jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare u public.organization_units; cid uuid; sector record; begin
 perform private.require_platform_manager();
 select * into u from public.organization_units where id=(p_data->>'unitId')::uuid;
 if u.id is null then raise exception 'unit_not_found'; end if;
 if not exists(select 1 from public.saas_plans where id=p_data->>'planId' and billing_cycle='monthly') then raise exception 'Use um pacote mensal nesta modalidade.'; end if;
 if p_data->>'status'='active' and u.unit_type<>'headquarters' and not exists(select 1 from public.saas_unit_contracts h join public.organization_units hu on hu.id=h.unit_id where h.organization_id=u.organization_id and hu.unit_type='headquarters' and h.status='active') then raise exception 'Ative primeiro o contrato da sede.'; end if;
 if jsonb_typeof(coalesce(p_data->'modules','{}'))<>'object' then raise exception 'invalid_modules'; end if;
 for sector in select key,value from jsonb_each(coalesce(p_data->'modules','{}')) loop
  if jsonb_typeof(sector.value)<>'boolean' or not exists(select 1 from public.saas_module_catalog where code=sector.key) then raise exception 'invalid_module'; end if;
 end loop;
 if (p_data->>'whatsappEnabled')::boolean and (coalesce(p_data->>'whatsappConsent','false')<>'true' or coalesce(p_data->>'whatsappNumber','') !~ '^[0-9]{10,15}$') then raise exception 'whatsapp_consent_required'; end if;
 insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions,due_day,financial_profile,email_enabled,whatsapp_enabled,whatsapp_number,whatsapp_consent_at,autopay_requested)
 values(u.organization_id,u.id,(p_data->>'payerUnitId')::uuid,p_data->>'planId',p_data->>'status',coalesce(p_data->'modules','{}'),(p_data->>'dueDay')::integer,coalesce(p_data->'profile','{}'),coalesce((p_data->>'emailEnabled')::boolean,false),coalesce((p_data->>'whatsappEnabled')::boolean,false),p_data->>'whatsappNumber',case when (p_data->>'whatsappEnabled')::boolean then now() end,coalesce((p_data->>'autopayRequested')::boolean,false))
 on conflict(unit_id) do update set payer_unit_id=excluded.payer_unit_id,plan_id=excluded.plan_id,status=excluded.status,module_decisions=excluded.module_decisions,due_day=excluded.due_day,financial_profile=excluded.financial_profile,email_enabled=excluded.email_enabled,whatsapp_enabled=excluded.whatsapp_enabled,whatsapp_number=excluded.whatsapp_number,whatsapp_consent_at=case when excluded.whatsapp_enabled and public.saas_unit_contracts.whatsapp_number=excluded.whatsapp_number then coalesce(public.saas_unit_contracts.whatsapp_consent_at,excluded.whatsapp_consent_at) else excluded.whatsapp_consent_at end,autopay_requested=excluded.autopay_requested,updated_at=now() returning id into cid;
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id) values(auth.uid(),'unit_contract.saved','unit_contract',cid);
 return cid;
end $$;
revoke all on function public.save_unit_contract(jsonb) from public,anon;
grant execute on function public.save_unit_contract(jsonb) to authenticated;
create function private.request_unit_modules(p_unit uuid,p_modules text[],p_due_day integer,p_autopay boolean) returns void language plpgsql security definer set search_path='' as $$
declare oid uuid; begin
 select organization_id into oid from public.organization_units where id=p_unit;
 if auth.uid() is null or not private.has_organization_role(oid,array['owner','admin']::public.membership_role[]) then raise exception 'access_denied' using errcode='42501'; end if;
 if p_due_day not between 1 and 28 or p_due_day is null or p_modules is null or cardinality(p_modules)>30 or exists(select 1 from unnest(p_modules) x where not exists(select 1 from public.saas_module_catalog m where m.code=x and m.active)) then raise exception 'invalid_request'; end if;
 update public.saas_unit_contracts set requested_modules=p_modules,requested_due_day=p_due_day,autopay_requested=p_autopay,request_updated_at=now() where unit_id=p_unit;
 if not found then raise exception 'contract_not_configured'; end if;
end $$;
revoke all on function private.request_unit_modules(uuid,text[],integer,boolean) from public,anon,authenticated;
create function public.request_unit_modules(p_unit uuid,p_modules text[],p_due_day integer,p_autopay boolean) returns void language sql security definer set search_path='' as $$ select private.request_unit_modules(p_unit,p_modules,p_due_day,p_autopay) $$;
revoke all on function public.request_unit_modules(uuid,text[],integer,boolean) from public,anon;
grant execute on function public.request_unit_modules(uuid,text[],integer,boolean) to authenticated;
create function public.unit_contract_module_directory() returns jsonb language sql security invoker set search_path='' as $$ select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name)),'[]') from public.saas_module_catalog where active $$;
revoke all on function public.unit_contract_module_directory() from public,anon;
grant execute on function public.unit_contract_module_directory() to authenticated;
create policy modules_customer_directory on public.saas_module_catalog for select to authenticated using(active and exists(select 1 from public.organization_memberships where user_id=(select auth.uid()) and status='active'));
-- Enforce explicit contract blocks in the shared server authorization guards.
create function private.unit_module_enabled(p_organization uuid,p_module text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare selected_unit uuid; c public.saas_unit_contracts; begin
 if auth.uid() is null or not exists(select 1 from public.organization_memberships where user_id=auth.uid() and organization_id=p_organization and status='active') then return false; end if;
 select selected_unit_id into selected_unit from public.user_access_preferences where user_id=auth.uid() and selected_organization_id=p_organization;
 if selected_unit is null then select default_unit_id into selected_unit from public.organization_memberships where user_id=auth.uid() and organization_id=p_organization and status='active'; end if;
 if selected_unit is null then select id into selected_unit from public.organization_units where organization_id=p_organization and unit_type='headquarters' limit 1; end if;
 select * into c from public.saas_unit_contracts where unit_id=selected_unit and organization_id=p_organization;
 if c.id is null or c.status='draft' then return true; end if;
 if c.status='suspended' then return false; end if;
 if c.module_decisions ? p_module then return (c.module_decisions->>p_module)::boolean; end if;
 return exists(select 1 from public.saas_plan_modules where plan_id=c.plan_id and module_code=p_module and included);
end $$;
revoke all on function private.unit_module_enabled(uuid,text) from public,anon,authenticated;
create function public.unit_module_enabled(p_organization uuid,p_module text) returns boolean language sql security definer set search_path='' as $$ select private.unit_module_enabled(p_organization,p_module) $$;
revoke all on function public.unit_module_enabled(uuid,text) from public,anon;
grant execute on function public.unit_module_enabled(uuid,text) to authenticated;

-- Preferred due day for existing ministry subscriptions; existing invoices stay immutable.
alter table public.saas_billing_profiles add column due_day integer not null default 10 check(due_day between 1 and 28);
alter table public.saas_billing_profiles add column email_enabled boolean not null default false;
alter table public.saas_billing_profiles add column whatsapp_enabled boolean not null default false;
alter table public.saas_billing_profiles add column whatsapp_number text;
alter table public.saas_billing_profiles add column whatsapp_consent_at timestamptz;
alter table public.saas_invoices alter column subscription_id drop not null;
alter table public.saas_invoices add column unit_contract_id uuid references public.saas_unit_contracts(id);
alter table public.saas_invoices add column unit_id uuid references public.organization_units(id);
alter table public.saas_invoices add column payer_unit_id uuid references public.organization_units(id);
alter table public.saas_invoices add constraint invoice_contract_kind check((subscription_id is not null)<>(unit_contract_id is not null));
create unique index invoices_unit_contract_month_idx on public.saas_invoices(unit_contract_id,reference_month) where unit_contract_id is not null;
create index invoices_unit_idx on public.saas_invoices(unit_id);
create index invoices_payer_unit_idx on public.saas_invoices(payer_unit_id);
create table public.saas_invoice_notifications(
 id uuid primary key default extensions.gen_random_uuid(),invoice_id uuid not null references public.saas_invoices(id),
 event text not null check(event in ('upcoming','overdue','paid')),channel text not null check(channel in ('email','whatsapp')),
 status text not null default 'pending' check(status in ('pending','waiting_configuration','sending','submitted','failed','cancelled')),
 attempts integer not null default 0,last_error text,provider_message_id text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(invoice_id,event,channel)
);
create index invoice_notifications_queue_idx on public.saas_invoice_notifications(status,created_at);
alter table public.saas_invoice_notifications enable row level security;
revoke all on public.saas_invoice_notifications from public,anon,authenticated;
grant select,insert,update on public.saas_invoice_notifications to authenticated;
grant all on public.saas_invoice_notifications to service_role;
create policy invoice_notifications_read on public.saas_invoice_notifications for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])));
create policy invoice_notifications_write on public.saas_invoice_notifications for all to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]))) with check((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])));

create or replace function public.generate_platform_invoices(p_reference text,p_due bigint,p_organization uuid default null) returns integer
language plpgsql security invoker set search_path='' as $$ declare affected integer; units_affected integer; begin
 perform private.require_platform_manager();
 if p_reference !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_billing_period'; end if;
 insert into public.saas_invoices(church_id,subscription_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at)
 select s.organization_id,s.id,p_reference,coalesce(p_due,(extract(epoch from ((p_reference||'-'||lpad(coalesce(bp.due_day,10)::text,2,'0')||' 12:00:00')::timestamp at time zone 'America/Sao_Paulo'))*1000)::bigint),
 greatest(0,round((p.base_price_cents+coalesce((select sum(c.monthly_price_cents) from public.saas_subscription_modules sm join public.saas_module_catalog c on c.code=sm.module_code where sm.subscription_id=s.id and sm.enabled and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=s.plan_id and pm.module_code=sm.module_code and pm.included)),0))*(1-coalesce(d.custom_percent,0)::numeric/100))-coalesce(d.custom_amount_cents,0)),
 coalesce(r.payer_church_id,s.organization_id),(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint
 from public.saas_subscriptions s join public.saas_plans p on p.id=s.plan_id
 left join public.saas_billing_responsibilities r on r.church_id=s.organization_id
 left join public.saas_billing_profiles bp on bp.church_id=coalesce(r.payer_church_id,s.organization_id)
 left join public.saas_subscription_discounts d on d.subscription_id=s.id and (d.valid_until is null or d.valid_until>now())
 where (s.status='active' or (s.status='trialing' and s.trial_ends_at<=now())) and (p_organization is null or s.organization_id=p_organization)
 and not exists(select 1 from public.saas_unit_contracts uc join public.organization_units u on u.id=uc.unit_id where uc.organization_id=s.organization_id and uc.status in ('active','suspended') and u.unit_type='headquarters')
 and not exists(select 1 from public.saas_invoices prior where prior.church_id=s.organization_id and prior.reference_month=p_reference and prior.unit_contract_id is not null)
 on conflict(subscription_id,reference_month) do nothing;
 get diagnostics affected=row_count;
 insert into public.saas_invoices(church_id,unit_contract_id,unit_id,payer_unit_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at)
 select uc.organization_id,uc.id,uc.unit_id,uc.payer_unit_id,p_reference,
 coalesce(p_due,(extract(epoch from ((p_reference||'-'||lpad(coalesce(payer.due_day,uc.due_day)::text,2,'0')||' 12:00:00')::timestamp at time zone 'America/Sao_Paulo'))*1000)::bigint),
 p.base_price_cents+coalesce((select sum(m.monthly_price_cents) from public.saas_module_catalog m where uc.module_decisions->m.code='true'::jsonb and not exists(select 1 from public.saas_plan_modules pm where pm.plan_id=uc.plan_id and pm.module_code=m.code and pm.included)),0),
 uc.organization_id,(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint
 from public.saas_unit_contracts uc join public.saas_plans p on p.id=uc.plan_id
 join public.saas_subscriptions s on s.organization_id=uc.organization_id
 left join public.saas_unit_contracts payer on payer.unit_id=uc.payer_unit_id
 where uc.status='active' and (s.status='active' or (s.status='trialing' and s.trial_ends_at<=now())) and (p_organization is null or uc.organization_id=p_organization)
 and exists(select 1 from public.saas_unit_contracts head join public.organization_units u on u.id=head.unit_id where head.organization_id=uc.organization_id and head.status='active' and u.unit_type='headquarters')
 and not exists(select 1 from public.saas_invoices prior where prior.church_id=uc.organization_id and prior.reference_month=p_reference and prior.subscription_id is not null)
 on conflict(unit_contract_id,reference_month) where unit_contract_id is not null do nothing;
 get diagnostics units_affected=row_count; return affected+units_affected;
end $$;

-- Unit invoices identify their payer independently; do not mix them in the
-- legacy organization-level consolidation (one CNPJ can pay several links).
create or replace function public.consolidate_platform_invoices(p_reference text) returns integer
language plpgsql security invoker set search_path='' as $$ declare g record; cid uuid; affected integer:=0; begin
 perform private.require_platform_manager(); perform pg_advisory_xact_lock(hashtext('consolidate:'||p_reference));
 for g in select i.payer_church_id,min(i.due_at) due_at,sum(i.amount_cents) amount_cents from public.saas_invoices i where i.unit_contract_id is null and i.reference_month=p_reference and i.status='open' and i.payment_url is null and not exists(select 1 from public.saas_consolidated_invoice_items x where x.invoice_id=i.id) group by i.payer_church_id having count(*)>1 loop
  insert into public.saas_consolidated_invoices(payer_church_id,reference_month,due_at,amount_cents,created_at,updated_at) values(g.payer_church_id,p_reference,g.due_at,g.amount_cents,(extract(epoch from now())*1000)::bigint,(extract(epoch from now())*1000)::bigint) on conflict(payer_church_id,reference_month) do nothing returning id into cid;
  if cid is null then continue; end if;
  insert into public.saas_consolidated_invoice_items(consolidated_invoice_id,invoice_id,amount_cents,created_at) select cid,i.id,i.amount_cents,(extract(epoch from now())*1000)::bigint from public.saas_invoices i where i.unit_contract_id is null and i.payer_church_id=g.payer_church_id and i.reference_month=p_reference and i.status='open' and i.payment_url is null and not exists(select 1 from public.saas_consolidated_invoice_items x where x.invoice_id=i.id);
  affected:=affected+1;
 end loop; return affected; end $$;

create or replace function public.record_platform_invoice_status(p_invoice uuid,p_status text) returns void
language plpgsql security invoker set search_path='' as $$ declare sid uuid; cid uuid; begin
 perform private.require_platform_manager();
 if p_status not in ('paid','cancelled') then raise exception 'invalid_status'; end if;
 update public.saas_invoices set status=p_status,paid_at=case when p_status='paid' then (extract(epoch from now())*1000)::bigint else null end,updated_at=(extract(epoch from now())*1000)::bigint where id=p_invoice and status='open' returning subscription_id,unit_contract_id into sid,cid;
 if sid is null and cid is null then raise exception 'invoice_not_open'; end if;
 if p_status='paid' and sid is not null then update public.saas_subscriptions set status='active',current_period_end=now()+interval '1 month',updated_at=now() where id=sid; end if;
end $$;
