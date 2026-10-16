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
declare actor record; viewer record; trial jsonb; repeat_result jsonb; org_id uuid; chat jsonb; cid uuid; denied boolean; secret text:=repeat('a',64); messages jsonb;
begin
 select u.id,u.email into actor from auth.users u where u.id='f1000000-0000-4000-8000-000000000003' and u.email_confirmed_at is not null and not exists(select 1 from public.organization_memberships m where m.user_id=u.id) limit 1;
 select u.id,u.email into viewer from auth.users u join public.organization_memberships m on m.user_id=u.id where u.id='f1000000-0000-4000-8000-000000000002' and m.status='active' and m.role='owner' limit 1;
 if actor.id is null or viewer.id is null then raise exception 'test_requires_existing_accounts'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor.id,'email',actor.email,'role','authenticated','aal','aal1')::text,true);
 execute 'set local role authenticated';
 trial:=public.register_organization_trial('{"fullName":"Responsável QA","ministry":"Ministério teste transacional","headquarters":"Sede QA","pastor":"Pastor QA","phone":"11999999999","city":"São Paulo","state":"SP","units":"3","accepted":true}');
 if not (trial->>'ok')::boolean then raise exception 'trial_registration_failed'; end if;
 repeat_result:=public.register_organization_trial('{}');
 if not (repeat_result->>'alreadyCreated')::boolean or repeat_result->>'slug'<>trial->>'slug' then raise exception 'trial_not_idempotent'; end if;
 select organization_id into org_id from public.saas_trial_registrations where user_id=actor.id;
 if not exists(select 1 from public.saas_onboarding_progress where organization_id=org_id and status='completed') then raise exception 'trial_access_not_ready'; end if;
 -- Trial dates are fixed by the existing trusted provisioning trigger.
 execute 'reset role';
 if not exists(select 1 from public.saas_subscriptions where organization_id=org_id and status='trialing' and trial_ends_at between now()+interval '29 days' and now()+interval '31 days') then raise exception 'trial_period_invalid'; end if;
 execute 'set local role authenticated';
 chat:=public.support_chat('start',null,null,jsonb_build_object('name','Responsável QA','email',actor.email,'body','Atendimento autenticado','organizationId',org_id));
 cid:=(chat->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer.id,'email',viewer.email,'role','authenticated','aal','aal1')::text,true);
 denied:=false;begin perform public.support_chat('read',cid,secret);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'customer_chat_leaked';end if;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 execute 'set local role anon';
 chat:=public.support_chat('start',null,secret,'{"name":"Visitante QA","email":"qa@example.invalid","body":"Teste público revertido"}');
 cid:=(chat->>'id')::uuid;
 denied:=false;begin perform public.support_chat('read',cid,repeat('b',64));exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'guest_chat_wrong_secret_allowed';end if;
 chat:=public.support_chat('send',cid,secret,'{"body":"Segunda mensagem"}');
 if jsonb_array_length(chat->'messages')<>2 then raise exception 'guest_send_failed';end if;
 denied:=false;begin perform count(*) from public.saas_chat_messages;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'anonymous_table_access_allowed';end if;
 execute 'reset role';
 select user_id,email into actor from public.platform_operators where user_id='f1000000-0000-4000-8000-000000000001' and active and role in ('owner','admin') limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor.user_id,'email',actor.email,'role','authenticated','aal','aal2')::text,true);
 execute 'set local role authenticated';
 insert into public.saas_chat_messages(conversation_id,sender,author_name,body,author_user_id) values(cid,'team','Equipe QA','Resposta revertida',actor.user_id);
 update public.saas_chat_conversations set last_sender='team',last_message_at=now() where id=cid;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);execute 'set local role anon';
 messages:=public.support_chat('read',cid,secret);
 if jsonb_array_length(messages->'messages')<>3 then raise exception 'team_reply_not_visible';end if;
 if (messages->'conversation') ? 'guest_secret_hash' then raise exception 'guest_secret_exposed';end if;
 perform set_config('vinha.trial_chat_test','passed',true);
end $$; $scenario$, 'trial_and_support_chat_transaction');
reset role;
select * from finish();
rollback;
