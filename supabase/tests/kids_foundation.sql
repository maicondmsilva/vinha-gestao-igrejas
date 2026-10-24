begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('a1000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','kids-owner@example.test',now(),now(),now()),
('a1000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','kids-secretary@example.test',now(),now(),now()),
('a1000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','kids-member@example.test',now(),now(),now()),
('a1000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','kids-unconfirmed@example.test',null,now(),now());
insert into public.organizations(id,name,slug,status) values
('b1000000-0000-4000-8000-000000000001','Kids fictício A','kids-test-a','active'),
('b1000000-0000-4000-8000-000000000002','Kids fictício B','kids-test-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('c1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','Sede fictícia','sede','headquarters'),
('c1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','Campus fictício','campus','campus'),
('c1000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000002','Outra sede','outra','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('e1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','owner','active','c1000000-0000-4000-8000-000000000001'),
('e1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','secretary','active','c1000000-0000-4000-8000-000000000001'),
('e1000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003','member','active','c1000000-0000-4000-8000-000000000001'),
('e1000000-0000-4000-8000-000000000004','b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000004','admin','active','c1000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values
('e1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000001','manage');
insert into public.people(id,organization_id,unit_id,full_name,birth_date,status) values
('d1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','Criança fictícia',current_date-interval '8 years','active'),
('d1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','Responsável fictício',current_date-interval '35 years','active'),
('d1000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000002','Criança de outra unidade',current_date-interval '6 years','active'),
('d1000000-0000-4000-8000-000000000004','b1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000003','Criança de outro ministério',current_date-interval '5 years','active');
create function pg_temp.ks(a text,i uuid,v integer,d jsonb) returns jsonb language sql as $$
 select public.kids_save('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',extensions.gen_random_uuid(),a,i,v,d);
$$;
create function pg_temp.kd() returns jsonb language sql as $$
 select public.kids_directory('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000001');
$$;
select ok(not has_function_privilege('anon','public.kids_save(uuid,uuid,uuid,text,uuid,integer,jsonb)','execute'),'anon não executa gravação');
select ok(not has_function_privilege('service_role','private.kids_save(uuid,uuid,uuid,text,uuid,integer,jsonb)','execute'),'serviço sem bypass direto do fluxo');
select ok((select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r' and relname like 'kids_%'),'RLS em todas as tabelas Kids');
select ok(not has_table_privilege('authenticated','private.kids_profiles','insert') and not has_table_privilege('authenticated','private.kids_history','delete') and not has_table_privilege('authenticated','private.kids_care','select'),'sem gravação, leitura de cuidado ou reescrita direta');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(pg_temp.ks('profile','f1000000-0000-4000-8000-000000000001',0,'{"personId":"d1000000-0000-4000-8000-000000000001","status":"active"}')->>'version','1','vincula pessoa sem copiar identidade');
select is(pg_temp.kd()->'detail'->>'name','Criança fictícia','nome vem de Pessoas');
select is(pg_temp.kd()->'detail'->>'reviewStatus','pending','vínculo novo exige revisão');
select is(jsonb_array_length(public.kids_choices('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','Criança')->'items'),1,'busca respeita unidade');
select is(jsonb_array_length(public.kids_choices('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','%%')->'items'),0,'busca não interpreta wildcard');
select throws_ok($$select pg_temp.ks('profile','f1000000-0000-4000-8000-000000000002',0,'{"personId":"d1000000-0000-4000-8000-000000000002","status":"active"}')$$,'22023','invalid_child','não cadastra adulto como criança');
select throws_ok($$select pg_temp.ks('profile','f1000000-0000-4000-8000-000000000002',0,'{"personId":"d1000000-0000-4000-8000-000000000003","status":"active"}')$$,'22023','invalid_child','não vincula criança de outra unidade');
select throws_ok($$select pg_temp.ks('profile','f1000000-0000-4000-8000-000000000002',0,'{"personId":"d1000000-0000-4000-8000-000000000004","status":"active"}')$$,'22023','invalid_child','não vincula criança de outro ministério');
select throws_ok($$select pg_temp.ks('profile','f1000000-0000-4000-8000-000000000001',9,'{"personId":"d1000000-0000-4000-8000-000000000001","status":"active"}')$$,'40001','kids_version_conflict','edição desatualizada não sobrescreve');
select lives_ok($$select pg_temp.ks('review','f1000000-0000-4000-8000-000000000001',1,'{}')$$,'gestão revisa Kids');
select lives_ok($$select pg_temp.ks('care','f1000000-0000-4000-8000-000000000001',0,'{"instructions":"Orientação fictícia restrita","source":"Responsável em atendimento de teste"}')$$,'gestão registra cuidado');
select is(pg_temp.kd()->'detail'->'care'->>'instructions','Orientação fictícia restrita','gestão consulta cuidado');
select lives_ok($$select pg_temp.ks('guardian','f2000000-0000-4000-8000-000000000001',0,'{"profileId":"f1000000-0000-4000-8000-000000000001","personId":"d1000000-0000-4000-8000-000000000002","relationship":"Responsável","verificationNote":"Autorização conferida em atendimento fictício","canPickup":true,"canEdit":false,"isEmergency":true,"status":"approved","validUntil":""}')$$,'aprova autorização com origem conferida');
select is(pg_temp.kd()->'detail'->'guardians'->0->>'status','approved','autorização aprovada');
select is(pg_temp.kd()->'items'->0->>'authorizedCount','1','conta somente retirada autorizada vigente');
select throws_ok($$select pg_temp.ks('guardian','f2000000-0000-4000-8000-000000000002',0,'{"profileId":"f1000000-0000-4000-8000-000000000001","personId":"d1000000-0000-4000-8000-000000000001","relationship":"Responsável","verificationNote":"Conferência fictícia","canPickup":true,"canEdit":false,"isEmergency":true,"status":"approved","validUntil":""}')$$,'22023','invalid_guardian','criança não autoriza a si mesma');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(pg_temp.kd()->'detail'->'care','null'::jsonb,'secretaria não recebe dados restritos');
select is(pg_temp.kd()->'detail'->'guardians'->0->>'verificationNote','','conferência restrita à gestão');
select throws_ok($$select pg_temp.ks('care','f1000000-0000-4000-8000-000000000001',1,'{"instructions":"Alteração indevida","source":"Teste"}')$$,'42501','kids_access_denied','secretaria não altera cuidado');
select throws_ok($$select pg_temp.ks('review','f1000000-0000-4000-8000-000000000001',2,'{}')$$,'42501','kids_access_denied','secretaria não aprova revisão');
select throws_ok($$select pg_temp.ks('guardian','f2000000-0000-4000-8000-000000000001',1,'{"profileId":"f1000000-0000-4000-8000-000000000001","personId":"d1000000-0000-4000-8000-000000000002","relationship":"Responsável","verificationNote":"Conferência fictícia","canPickup":true,"canEdit":true,"isEmergency":true,"status":"approved","validUntil":""}')$$,'42501','guardian_approval_denied','secretaria não amplia autorização aprovada');
select lives_ok($$select pg_temp.ks('guardian','f2000000-0000-4000-8000-000000000001',1,'{"profileId":"f1000000-0000-4000-8000-000000000001","personId":"d1000000-0000-4000-8000-000000000002","relationship":"Responsável","verificationNote":"","canPickup":true,"canEdit":false,"isEmergency":true,"status":"revoked","validUntil":""}')$$,'secretaria pode revogar por segurança');
select is(pg_temp.kd()->'items'->0->>'authorizedCount','0','revogada deixa de contar imediatamente');
select lives_ok($$select public.kids_save('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','person','d2000000-0000-4000-8000-000000000001',0,'{"name":"Visitante Kids fictício","birthDate":"2020-01-01","phone":""}')$$,'cadastro rápido cria visitante pendente');
select lives_ok($$select public.kids_save('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','person','d2000000-0000-4000-8000-000000000001',0,'{"name":"Visitante Kids fictício","birthDate":"2020-01-01","phone":""}')$$,'retry idêntico não duplica pessoa');
select throws_ok($$select public.kids_save('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','person','d2000000-0000-4000-8000-000000000001',0,'{"name":"Nome adulterado","birthDate":"2020-01-01","phone":""}')$$,'40001','kids_version_conflict','mesma operação com outro conteúdo é recusada');
select is((select status from public.people where id='d2000000-0000-4000-8000-000000000001'),'pending','não aprova visitante automaticamente');
select is((select journey_status from public.people where id='d2000000-0000-4000-8000-000000000001'),'Visitante','não promove a membro');
select is((select auth_user_id from public.people where id='d2000000-0000-4000-8000-000000000001'),null::uuid,'não vincula conta automaticamente');
select throws_ok($$select pg_temp.ks('personReview','d2000000-0000-4000-8000-000000000001',0,'{}')$$,'42501','kids_access_denied','secretaria não aprova pessoa');
select throws_ok($$select public.kids_directory('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000002')$$,'42501','kids_access_denied','secretaria não consulta outra unidade');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$select pg_temp.kd()$$,'42501','kids_access_denied','membro sem papel não consulta crianças');
select throws_ok($$select pg_temp.ks('profile','f1000000-0000-4000-8000-000000000001',2,'{"personId":"d1000000-0000-4000-8000-000000000001","status":"archived"}')$$,'42501','kids_access_denied','membro não altera criança');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select throws_ok($$select pg_temp.kd()$$,'42501','self_service_identity_unavailable','e-mail não confirmado bloqueado');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select pg_temp.ks('personReview','d2000000-0000-4000-8000-000000000001',0,'{}')$$,'gestão aprova visitante sem mudar jornada');
select is((select journey_status from public.people where id='d2000000-0000-4000-8000-000000000001'),'Visitante','aprovação preserva visitante');
select throws_ok($$select public.kids_directory('b1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000003')$$,'42501','kids_access_denied','proprietário não acessa outro ministério');
reset role;
select is((select count(*)::integer from public.people where id='d2000000-0000-4000-8000-000000000001'),1,'um único registro após retry');
select ok(not exists(select 1 from private.kids_history where changed_fields::text like '%Orientação fictícia restrita%'),'histórico não replica saúde');
select is((select approved_by from private.kids_guardians where id='f2000000-0000-4000-8000-000000000001'),null::uuid,'revogação retira aprovação vigente');
select ok(not exists(select 1 from information_schema.columns where table_schema='private' and table_name='kids_profiles' and column_name in ('full_name','birth_date')),'não duplica nome ou nascimento no Kids');
update public.organization_units set status='suspended' where id='c1000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.kd()$$,'42501','kids_access_denied','unidade inativa bloqueia leitura');
select throws_ok($$select pg_temp.ks('review','f1000000-0000-4000-8000-000000000001',2,'{}')$$,'42501','kids_access_denied','unidade inativa bloqueia gravação');
reset role;
update public.organization_units set status='active' where id='c1000000-0000-4000-8000-000000000001';
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions)
values('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','plan-essential','active','{"kids":false,"people":true}');
set local role authenticated;
select throws_ok($$select pg_temp.kd()$$,'42501','kids_access_denied','Kids bloqueado no contrato impede consulta');
select throws_ok($$select pg_temp.ks('care','f1000000-0000-4000-8000-000000000001',1,'{"instructions":"Indevido","source":"Teste"}')$$,'42501','kids_access_denied','Kids bloqueado impede alteração');
reset role;
update public.saas_unit_contracts set module_decisions='{"kids":true,"people":false}' where organization_id='b1000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.kd()$$,'42501','kids_access_denied','Pessoas bloqueado não permite contorno por Kids');
reset role;
update public.saas_unit_contracts set module_decisions='{"kids":true,"people":true}' where organization_id='b1000000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok($$select pg_temp.kd()$$,'contrato com módulos ativos permite consulta');
select throws_ok($$select pg_temp.ks('care','f1000000-0000-4000-8000-000000000001',0,'{"instructions":"Sobrescrever","source":"Teste"}')$$,'40001','kids_version_conflict','versão antiga de cuidados não sobrescreve informação');
select throws_ok($$select pg_temp.ks('profile','f1000000-0000-4000-8000-000000000001',2,'{"personId":"d1000000-0000-4000-8000-000000000001","status":"active","role":"owner"}')$$,'22023','invalid_kids_input','campos de acesso não são aceitos pelo Kids');
select throws_ok($$select pg_temp.ks('checkout','f1000000-0000-4000-8000-000000000001',2,'{}')$$,'22023','invalid_kids_input','K1 não libera retirada presencial');
select throws_ok($$select pg_temp.ks('person','d2000000-0000-4000-8000-000000000002',0,'{"name":"Criança fictícia","birthDate":"2020-01-01","phone":""}')$$,'23505','kids_possible_duplicate','nome igual exige revisão sem unir pessoas');
select lives_ok($$select pg_temp.ks('guardian','f2000000-0000-4000-8000-000000000001',2,'{"profileId":"f1000000-0000-4000-8000-000000000001","personId":"d1000000-0000-4000-8000-000000000002","relationship":"Responsável","verificationNote":"Conferência fictícia em atendimento","canPickup":true,"canEdit":false,"isEmergency":true,"status":"approved","validUntil":"2020-01-01"}')$$,'autorização histórica pode permanecer com validade expirada');
select is(pg_temp.kd()->'items'->0->>'authorizedCount','0','autorização expirada não conta como vigente');
reset role;
update public.people set unit_id='c1000000-0000-4000-8000-000000000002' where id='d1000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(jsonb_array_length(pg_temp.kd()->'detail'->'guardians'),0,'não mostra contato de adulto transferido para outra unidade');
reset role;
update public.organizations set status='suspended' where id='b1000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.kd()$$,'42501','kids_access_denied','ministério suspenso não consulta Kids');
reset role;
select * from finish();
rollback;
