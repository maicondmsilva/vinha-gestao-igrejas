begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select ('aa000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','org-fields-'||i||'@example.test','',now(),now(),now() from generate_series(1,6)i;
insert into public.organizations(id,name,slug,status,bootstrap_user_id) values
 ('ba000000-0000-4000-8000-000000000001','Configuração A','org-fields-a','active','aa000000-0000-4000-8000-000000000001'),
 ('ba000000-0000-4000-8000-000000000002','Configuração B','org-fields-b','active','aa000000-0000-4000-8000-000000000005');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('ca000000-0000-4000-8000-000000000001','ba000000-0000-4000-8000-000000000001','Sede','sede','headquarters'),
 ('ca000000-0000-4000-8000-000000000002','ba000000-0000-4000-8000-000000000002','Sede','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
select 'ba000000-0000-4000-8000-000000000001',('aa000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 (case i when 1 then 'owner' when 2 then 'admin' when 3 then 'pastor' else 'viewer' end)::public.membership_role,'active','ca000000-0000-4000-8000-000000000001' from generate_series(1,4)i;
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
values('ba000000-0000-4000-8000-000000000002','aa000000-0000-4000-8000-000000000005','owner','active','ca000000-0000-4000-8000-000000000002');
select ok(not prosecdef,'gatilho não executa com poderes elevados') from pg_proc where oid='private.guard_organization_client_fields()'::regprocedure;
select ok(not has_function_privilege('authenticated','private.guard_organization_client_fields()','EXECUTE'),'cliente não chama gatilho diretamente');
select ok(not has_function_privilege('anon','private.guard_organization_client_fields()','EXECUTE'),'visitante não chama gatilho diretamente');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$update public.organizations set name='Nome permitido',legal_name='Razão permitida',tax_id='DOCUMENTO-SINTETICO',primary_color='#123456',accent_color='#654321',app_name='Aplicativo permitido',senior_pastor_name='Pastor sintético' where id='ba000000-0000-4000-8000-000000000001'$$,'proprietário mantém os sete campos de configuração');
select is((select name from public.organizations where id='ba000000-0000-4000-8000-000000000001'),'Nome permitido','configuração autorizada persiste');
select throws_ok($$update public.organizations set status='active'::public.organization_status,slug='endereco-trocado' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','endereço digital não é trocado diretamente');
select throws_ok($$update public.organizations set bootstrap_user_id='aa000000-0000-4000-8000-000000000005' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','criador original não é transferido');
select throws_ok($$update public.organizations set created_at=now()-interval '1 year' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','data original não é reescrita');
select throws_ok($$update public.organizations set id='ba000000-0000-4000-8000-000000000099' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','identidade do ministério não é transferida');
select throws_ok($$update public.organizations set status='suspended' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','proprietário não muda estado comercial diretamente');
select lives_ok($$update public.organizations set updated_at=now()-interval '1 year' where id='ba000000-0000-4000-8000-000000000001'$$,'horário enviado pelo cliente é substituído');
select is((select updated_at from public.organizations where id='ba000000-0000-4000-8000-000000000001'),transaction_timestamp(),'horário de atualização vem do banco');
select lives_ok($$select public.save_organization_onboarding('ba000000-0000-4000-8000-000000000001','{"step":"identity","name":"Ministério permitido","appName":"App permitido","seniorPastorName":"Pastor sintético","primaryColor":"#285c45","accentColor":"#d9b960"}')$$,'configuração inicial invoker continua funcionando');
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$update public.organizations set app_name='Atualizado pelo administrador' where id='ba000000-0000-4000-8000-000000000001'$$,'administrador mantém configuração permitida');
select throws_ok($$update public.organizations set status='cancelled' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','administrador não cancela estado comercial diretamente');
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$update public.organizations set app_name='Atualizado pelo pastor' where id='ba000000-0000-4000-8000-000000000001'$$,'pastor mantém configuração permitida');
select throws_ok($$update public.organizations set status='trial' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','pastor não reinicia estado de demonstração');
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select lives_ok($query$do $$declare affected int; begin update public.organizations set name='Indevido' where id='ba000000-0000-4000-8000-000000000001'; get diagnostics affected=row_count; if affected<>0 then raise exception 'unexpected_write'; end if; end $$;$query$,'leitor não altera configuração');
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select lives_ok($query$do $$declare affected int; begin update public.organizations set name='Outra igreja' where id='ba000000-0000-4000-8000-000000000001'; get diagnostics affected=row_count; if affected<>0 then raise exception 'unexpected_write'; end if; end $$;$query$,'gestor de outro ministério não altera configuração');
reset role;
update public.organizations set status='suspended' where id='ba000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$update public.organizations set status='active' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_admin_fields_immutable','gestor não reativa ministério suspenso');
select throws_ok($$update public.organizations set app_name='Mudança suspensa' where id='ba000000-0000-4000-8000-000000000001'$$,'42501','organization_configuration_unavailable','ministério suspenso não recebe mudanças de configuração');
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
select throws_ok($$insert into public.organizations(name,slug,status) values('Criação indevida','org-fields-invalid-state','active')$$,'42501','organization_bootstrap_fields_denied','cadastro direto não inicia como contrato ativo');
select throws_ok($$insert into public.organizations(name,slug,bootstrap_user_id) values('Criador indevido','org-fields-invalid-creator','aa000000-0000-4000-8000-000000000005')$$,'42501','organization_bootstrap_fields_denied','cadastro direto não fabrica outro criador');
select throws_ok($$insert into public.organizations(name,slug,created_at) values('Data indevida','org-fields-invalid-date',now()-interval '1 year')$$,'42501','organization_bootstrap_fields_denied','cadastro direto não fabrica data antiga');
select lives_ok($$select public.bootstrap_organization('Novo ministério sintético','org-fields-bootstrap','Sede sintética','Responsável sintético')$$,'bootstrap legítimo continua criando proprietário e sede');
select is((select status::text from public.organizations where slug='org-fields-bootstrap'),'trial','cadastro legítimo começa em demonstração');
reset role;
-- Trusted subscription synchronization is still the commercial source of truth.
update public.saas_subscriptions set status='active' where organization_id='ba000000-0000-4000-8000-000000000001';
select is((select status::text from public.organizations where id='ba000000-0000-4000-8000-000000000001'),'active','sincronização interna do contrato continua autorizada');
select * from finish();
rollback;
