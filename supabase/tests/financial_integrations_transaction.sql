-- Local regression: synthetic accounts and all changes are rolled back. No external calls.
begin;

create extension if not exists pgtap with schema extensions;
select plan(1);
-- Isolated, synthetic identities: no existing operator/customer accounts are used.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
 ('f1000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator@fixture.example.invalid','',now(),now(),now()),
 ('f1000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner@fixture.example.invalid','',now(),now(),now()),
 ('f1000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','trial@fixture.example.invalid','',now(),now(),now());
insert into public.platform_operators(user_id,role,full_name,email)
values('f1000000-0000-4000-8000-000000000001','owner','Operador sintético','operator@fixture.example.invalid');
insert into public.organizations(id,name,slug)
values('f2000000-0000-4000-8000-000000000001','Ministério sintético','fixture-ministry');
insert into public.organization_units(id,organization_id,name,slug,unit_type)
values('f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001','Sede sintética','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status)
values('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000001','owner','active');

select lives_ok($scenario$ do $$
declare manager uuid; customer uuid; org uuid:=extensions.gen_random_uuid(); other_org uuid:=extensions.gen_random_uuid(); unit_id uuid:=extensions.gen_random_uuid(); inv uuid; notification uuid; op uuid; denied boolean; r integer; summary jsonb; stamp bigint:=(extract(epoch from now())*1000)::bigint;
begin
 select user_id into manager from public.platform_operators where user_id='f1000000-0000-4000-8000-000000000001' and active and role='owner' limit 1;
 select id into customer from auth.users where id='f1000000-0000-4000-8000-000000000002' limit 1;
 if manager is null or customer is null then raise exception 'test_requires_two_existing_auth_identities'; end if;
 insert into public.organizations(id,name,slug) values(org,'Empresa QA financeiro','qa-finance-'||org::text),(other_org,'Outra QA','qa-other-'||other_org::text);
 insert into public.organization_units(id,organization_id,name,slug,unit_type) values(unit_id,org,'Sede QA','sede','headquarters');
 insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(org,customer,unit_id,'owner','active');
 insert into public.saas_invoices(church_id,subscription_id,reference_month,due_at,amount_cents,payer_church_id,created_at,updated_at) select org,id,'2099-01',stamp,1000,org,stamp,stamp from public.saas_subscriptions where organization_id=org returning id into inv;
 if inv is null then raise exception 'invoice_fixture_missing'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',manager,'role','authenticated','aal','aal2')::text,true);execute 'set local role authenticated';
 select revision into r from public.saas_company_profile where id;
 perform public.save_vinha_company('{"legalName":"QA empresa"}',coalesce(r,0));
 denied:=false;begin update public.saas_company_profile set profile='{}' where id;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'direct_company_update_bypassed_audit'; end if;
 denied:=false;begin perform public.save_vinha_company('{"legalName":"QA sobrescrita"}',coalesce(r,0));exception when others then denied:=true;end;
 if not denied then raise exception 'optimistic_revision_failed'; end if;
 execute 'reset role';perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','aal','aal1')::text,true);execute 'set local role authenticated';
 summary:=public.tenant_subscription_summary(org);
 if summary->'church'->>'id'<>org::text or summary->'subscription' is null then raise exception 'tenant_summary_failed'; end if;
 denied:=false;begin perform public.tenant_subscription_summary(other_org);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'tenant_summary_cross_org_leak'; end if;
 denied:=false;begin perform public.save_vinha_company('{}',0);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'customer_changed_vinha_company'; end if;
 if exists(select 1 from public.saas_financial_operations) then raise exception 'customer_read_financial_operations'; end if;
 denied:=false;begin insert into public.saas_financial_operations(invoice_id,kind,amount_cents,snapshot) values(inv,'fiscal',1000,'{}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'browser_changed_provider_status'; end if;
 denied:=false;begin perform public.record_billing_delivery('resend','qa','qa','delivered',now());exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'customer_forged_delivery'; end if;
 execute 'reset role';perform set_config('request.jwt.claims','{"role":"service_role"}',true);execute 'set local role service_role';
 insert into public.saas_invoice_notifications(invoice_id,event,channel,status) values(inv,'paid','email','sending') returning id into notification;
 perform public.record_billing_delivery('resend','qa-delivered','qa-message','delivered',now());
 update public.saas_invoice_notifications set provider_message_id='qa-message',status='submitted' where id=notification;
 if not exists(select 1 from public.saas_invoice_notifications where id=notification and status='delivered') then raise exception 'early_delivery_callback_lost'; end if;
 perform public.record_billing_delivery('resend','qa-delivered','qa-message','delivered',now());
 perform public.record_billing_delivery('resend','qa-late-failed','qa-message','delivery_failed',now());
 if not exists(select 1 from public.saas_invoice_notifications where id=notification and status='delivered') then raise exception 'delivery_confirmation_regressed'; end if;
 insert into public.saas_financial_operations(invoice_id,kind,amount_cents,snapshot) values(inv,'fiscal',1000,'{}') returning id into op;
 denied:=false;begin insert into public.saas_financial_operations(invoice_id,kind,environment,amount_cents,snapshot) values(inv,'fiscal','production',1000,'{}');exception when check_violation then denied:=true;end;
 if not denied then raise exception 'production_fiscal_allowed'; end if;
 perform public.apply_financial_sandbox_event(op,'qa-authorized','{"status":"authorized"}');
 perform public.apply_financial_sandbox_event(op,'qa-authorized','{"status":"authorized"}');
 perform public.apply_financial_sandbox_event(op,'qa-late-error','{"status":"rejected"}');
 if not exists(select 1 from public.saas_financial_operations where id=op and status='authorized') then raise exception 'fiscal_confirmation_regressed'; end if;
 if (select count(*) from public.saas_financial_operation_events where event_id='qa-authorized')<>1 then raise exception 'financial_webhook_not_idempotent'; end if;
 execute 'reset role';perform set_config('vinha.financial_integration_test','passed',true);
end $$; $scenario$, 'financial_integrations_transaction');
reset role;
select * from finish();
rollback;
