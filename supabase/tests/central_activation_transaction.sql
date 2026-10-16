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
declare operator_row record; owner_row record; created jsonb; organization_id uuid; token uuid; old_token uuid;
 invoice uuid; result jsonb; plan_id text; denied boolean; completed jsonb; child_created jsonb; child_id uuid; request_id uuid; ticket_id uuid; org_code bigint; daughter_code bigint;
begin
 select user_id,email into operator_row from public.platform_operators where user_id='f1000000-0000-4000-8000-000000000001' and active and role in ('owner','admin') limit 1;
 select u.id,u.email into owner_row from auth.users u join public.organization_memberships m on m.user_id=u.id where u.id='f1000000-0000-4000-8000-000000000002' and m.role='owner' and m.status='active' limit 1;
 if operator_row.user_id is null or owner_row.id is null then raise exception 'test_requires_existing_operator_and_owner'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',operator_row.user_id,'email',operator_row.email,'role','authenticated','aal','aal2')::text,true);
 execute 'set local role authenticated';
 select id into plan_id from public.saas_plans where active order by base_price_cents limit 1;
 created:=public.create_platform_organization('QA transacional '||extensions.gen_random_uuid()::text,'Responsável QA',owner_row.email,plan_id,false,'QA','#285c45','Pastor QA');
 organization_id:=(created->>'id')::uuid;
 select registration_code into org_code from public.organizations where id=organization_id;
 if org_code<1000 then raise exception 'ministry_registration_code_failed'; end if;
 old_token:=(created->>'invite_token')::uuid;
 token:=public.regenerate_platform_organization_invite(organization_id);
 if public.organization_invite_preview(old_token)->>'status'<>'revoked' then raise exception 'revocation_failed'; end if;
 perform public.update_platform_organization(organization_id,'{"status":"active"}'::jsonb);
 if public.generate_platform_invoices('2099-01',4071772800000,organization_id)<>1 then raise exception 'invoice_generation_failed'; end if;
 if public.generate_platform_invoices('2099-01',4071772800000,organization_id)<>0 then raise exception 'invoice_generation_not_idempotent'; end if;
 select id into invoice from public.saas_invoices where church_id=organization_id;
 perform public.record_platform_invoice_status(invoice,'paid');
 if not exists(select 1 from public.saas_invoices where id=invoice and status='paid') then raise exception 'invoice_payment_failed'; end if;
 child_created:=public.create_platform_organization('QA filha '||extensions.gen_random_uuid()::text,'Responsável QA',owner_row.email,plan_id,false,'QA filha','#285c45','Pastor QA');
 child_id:=(child_created->>'id')::uuid;
 perform public.change_platform_hierarchy('request',jsonb_build_object('parentChurchId',organization_id,'childChurchId',child_id,'billingMode','centralized'));
 select id into request_id from public.saas_hierarchy_requests where child_church_id=child_id;
 if exists(select 1 from public.saas_organization_links where child_church_id=child_id and status='active') then raise exception 'hierarchy_linked_without_approval'; end if;
 insert into public.saas_support_tickets(church_id,priority,subject,description,sla_due_at,created_at,updated_at) values(organization_id,'medium','QA suporte','Teste revertido',4071772800000,1,1) returning id into ticket_id;
 insert into public.saas_support_messages(ticket_id,author_platform_user_id,author_name,body,created_at) values(ticket_id,operator_row.user_id,'QA','Mensagem revertida',1);
 update public.saas_support_tickets set status='resolved',resolved_at=2 where id=ticket_id;
 if not exists(select 1 from public.saas_support_tickets where id=ticket_id and code like 'VIN-%' and status='resolved') then raise exception 'support_crud_failed'; end if;
 insert into public.saas_support_articles(slug,category,title,summary,body,created_at,updated_at) values('qa-'||extensions.gen_random_uuid()::text,'QA','QA','Resumo','Conteúdo',1,1);
 insert into public.saas_customer_tasks(church_id,rule_code,title,priority,created_at,updated_at) values(organization_id,'manual','QA tarefa','low',1,1);
 insert into public.saas_lifecycle_runs(trigger_type,status,started_at,finished_at) values('manual','completed',1,2);
 execute 'set local role anon';
 if public.organization_invite_preview(token)->>'status'<>'pending' then raise exception 'anonymous_preview_failed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_row.id,'email','wrong-email@example.invalid','role','authenticated','aal','aal1')::text,true);
 execute 'set local role authenticated';
 denied:=false;
 begin perform public.accept_organization_invite(token); exception when insufficient_privilege then denied:=true; end;
 if not denied then raise exception 'email_mismatch_was_allowed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_row.id,'email',owner_row.email,'role','authenticated','aal','aal1')::text,true);
 if exists(select 1 from public.saas_invoices where id=invoice) then raise exception 'church_can_read_central_invoices'; end if;
 result:=public.pending_organization_invitation();
 -- Both ministries have valid pending invitations for the same synthetic owner.
 if result is null or result->>'token' is null or result->>'token' not in(token::text,child_created->>'invite_token') then raise exception 'pending_invite_lookup_failed'; end if;
 result:=public.accept_organization_invite(token);
 if (result->>'alreadyAccepted')::boolean then raise exception 'first_accept_failed'; end if;
 if not exists(select 1 from public.organization_units u where u.organization_id=(created->>'id')::uuid and unit_type='headquarters' and registration_code=org_code) then raise exception 'headquarters_code_mismatch'; end if;
 result:=public.accept_organization_invite(token);
 if not (result->>'alreadyAccepted')::boolean then raise exception 'repeat_accept_failed'; end if;
 denied:=false;
 begin perform public.save_organization_onboarding(organization_id,'{"step":"completed"}'); exception when others then denied:=true; end;
 if not denied then raise exception 'incomplete_onboarding_was_allowed'; end if;
 perform public.save_organization_onboarding(organization_id,'{"step":"identity","name":"QA transacional","appName":"QA","seniorPastorName":"Pastor QA","primaryColor":"#285c45","accentColor":"#d9b960"}');
 perform public.save_organization_onboarding(organization_id,'{"step":"headquarters","name":"Sede QA","pastorName":"Pastor QA","email":"qa@example.invalid","city":"Cidade QA","state":"SP"}');
 insert into public.organization_units(organization_id,name,slug,unit_type,registration_code) values(organization_id,'QA filha local','qa-filha-local','congregation',999999) returning registration_code into daughter_code;
 if daughter_code=999999 or daughter_code=org_code or daughter_code<1000 then raise exception 'daughter_registration_code_failed'; end if;
 denied:=false;
 begin update public.organization_units u set registration_code=999999 where u.organization_id=(created->>'id')::uuid and slug='qa-filha-local'; exception when others then denied:=true; end;
 if not denied then raise exception 'registration_code_was_mutable'; end if;
 perform public.save_organization_onboarding(organization_id,'{"step":"structure"}');
 perform public.save_organization_onboarding(organization_id,'{"step":"people"}');
 completed:=public.save_organization_onboarding(organization_id,'{"step":"completed"}');
 if not ((completed->'completed') ? 'completed') then raise exception 'onboarding_completion_failed'; end if;
 perform public.accept_organization_invite((child_created->>'invite_token')::uuid);
 result:=public.approve_organization_hierarchy(request_id,organization_id,'approve');
 if result->>'status'<>'pending' then raise exception 'hierarchy_did_not_wait_second_approval'; end if;
 result:=public.approve_organization_hierarchy(request_id,child_id,'approve');
 if result->>'status'<>'approved' then raise exception 'hierarchy_dual_approval_failed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',operator_row.user_id,'email',operator_row.email,'role','authenticated','aal','aal2')::text,true);
 if not exists(select 1 from public.saas_billing_responsibilities where church_id=child_id and payer_church_id=organization_id and billing_mode='centralized') then raise exception 'centralized_payer_failed'; end if;
 denied:=false;
 begin perform public.change_platform_hierarchy('request',jsonb_build_object('parentChurchId',child_id,'childChurchId',organization_id)); exception when others then denied:=true; end;
 if not denied then raise exception 'hierarchy_cycle_was_allowed'; end if;
 perform set_config('vinha.central_test_result','passed',true);
end $$; $scenario$, 'central_activation_transaction');
reset role;
select * from finish();
rollback;
