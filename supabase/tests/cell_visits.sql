begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('a9000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','visits-owner@example.test',now(),now(),now()),
('a9000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','visits-reader@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('b9000000-0000-4000-8000-000000000001','Visitas fictícias A','visits-test-a','active'),('b9000000-0000-4000-8000-000000000002','Visitas fictícias B','visits-test-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','Sede fictícia A','sede','headquarters'),
('c9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','Campus fictício A','campus','campus'),
('c9000000-0000-4000-8000-000000000003','b9000000-0000-4000-8000-000000000002','Sede fictícia B','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('e9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','owner','active','c9000000-0000-4000-8000-000000000001'),
('e9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000002','secretary','active','c9000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values('e9000000-0000-4000-8000-000000000002','c9000000-0000-4000-8000-000000000001','read');
insert into public.people(id,organization_id,unit_id,full_name,status) values
('d9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Membro fictício canônico','active'),
('d9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000002','Membro de outro campus','active');
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by) values
('f9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Grupo fictício A',1,'19:00','presential','a9000000-0000-4000-8000-000000000001'),
('f9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000002','Grupo fictício campus',1,'19:00','presential','a9000000-0000-4000-8000-000000000001');
select ok(not has_table_privilege('authenticated','public.church_cell_visits','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'nenhuma gravação direta');
select ok(not has_function_privilege('anon','public.cell_visits_save(uuid,uuid,uuid,uuid,integer,jsonb)','EXECUTE'),'anônimo não grava');
select ok(not has_function_privilege('anon','public.cell_visits_read(uuid,uuid,uuid,date,date,uuid)','EXECUTE'),'anônimo não lê');
select ok((select relrowsecurity from pg_class where oid='public.church_cell_visits'::regclass),'RLS ativa');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000001',0,'{"person_id":null,"visitor_name":"Visitante externo fictício","visit_date":"2026-01-01","status":"recorded"}')->>'version','1','registra nome manual');
select is(public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000001',0,'{"person_id":null,"visitor_name":"Visitante externo fictício","visit_date":"2026-01-01","status":"recorded"}')->>'version','1','repetição idempotente');
select is((select count(*)::integer from public.people),2,'manual não cria membro');
select is(public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000002',0,'{"person_id":"d9000000-0000-4000-8000-000000000001","visitor_name":"Texto do navegador","visit_date":"2026-01-01","status":"recorded"}')->>'version','1','registra membro escolhido');
select is((select visitor_name from public.church_cell_visits where id='fa900000-0000-4000-8000-000000000002'),'Membro fictício canônico','nome canônico do banco');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000003',0,'{"person_id":"d9000000-0000-4000-8000-000000000001","visitor_name":"Teste duplicado","visit_date":"2026-01-01","status":"recorded"}')$$,'23505',null,'não duplica membro na mesma data e grupo');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000003',0,'{"person_id":"d9000000-0000-4000-8000-000000000002","visitor_name":"Outro campus","visit_date":"2026-01-01","status":"recorded"}')$$,'22023','invalid_visit_person','membro de outra unidade recusado');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000003',0,'{"person_id":null,"visitor_name":"Visita futura","visit_date":"2200-01-01","status":"recorded"}')$$,'22023','invalid_visit','visita futura recusada');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000002','f9000000-0000-4000-8000-000000000002','fa900000-0000-4000-8000-000000000001',1,'{"person_id":null,"visitor_name":"Mudando identidade","visit_date":"2026-01-01","status":"recorded"}')$$,'42501','cell_access_denied','não transfere visita entre unidades');
select is(public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000001',1,'{"person_id":null,"visitor_name":"Visitante externo corrigido","visit_date":"2026-01-02","status":"cancelled"}')->>'version','2','cancelamento lógico com versão');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000001',1,'{"person_id":null,"visitor_name":"Alteração atrasada","visit_date":"2026-01-02","status":"recorded"}')$$,'40001','visit_version_conflict','versão antiga recusada');
select is(jsonb_array_length(public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')->'items'),2,'histórico inclui canceladas');
select throws_ok($$select public.cell_visits_read('b9000000-0000-4000-8000-000000000002','c9000000-0000-4000-8000-000000000003',null,'2026-01-01','2026-01-31')$$,'42501','cell_access_denied','outro ministério recusado');
select throws_ok($$select public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2024-01-01','2026-01-31')$$,'22023','invalid_period','consulta limitada a 366 dias');
select is(public.ministry_language_save('b9000000-0000-4000-8000-000000000001',0,'{"celulas.visitantes":"Visitas dos PGs"}')->'labels'->>'celulas.visitantes','Visitas dos PGs','termo personalizável');
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(jsonb_array_length(public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')->'items'),2,'leitor autorizado vê visitas');
select is(public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')->>'canManage','false','leitor não gerencia');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000003',0,'{"person_id":null,"visitor_name":"Teste sem poder","visit_date":"2026-01-01","status":"recorded"}')$$,'42501','cell_access_denied','leitor não grava');
select throws_ok($$select public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000002',null,'2026-01-01','2026-01-31')$$,'42501','cell_access_denied','campus não autorizado recusado');
reset role;
select is((select count(*)::integer from public.audit_logs where organization_id='b9000000-0000-4000-8000-000000000001' and action like 'cell.visit_%'),3,'histórico atômico sem duplicar retry');
select ok(not exists(select 1 from public.audit_logs where organization_id='b9000000-0000-4000-8000-000000000001' and action like 'cell.visit_%' and metadata::text like '%fictício%'),'auditoria não copia nomes');
insert into public.church_cell_visits(id,organization_id,unit_id,cell_id,visitor_name,visit_date,status,created_by)
select ('fa900000-0000-4000-9000-'||lpad(n::text,12,'0'))::uuid,'b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','Paginação fictícia '||n,'2026-01-01','recorded','a9000000-0000-4000-8000-000000000001' from generate_series(1,101)n;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')->'items'),100,'página limitada a cem visitas');
select is(jsonb_array_length(public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31',
 (public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')->>'nextCursor')::uuid)->'items'),3,'cursor traz somente as três visitas restantes');
reset role;
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions)
select 'b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',id,'active','{"cells":true,"people":false}' from public.saas_plans where billing_cycle='monthly' limit 1;
set local role authenticated;
select throws_ok($$select public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')$$,'42501','cell_access_denied','bloqueio de Pessoas impede leitura');
select throws_ok($$select public.cell_visits_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','fa900000-0000-4000-8000-000000000003',0,'{"person_id":null,"visitor_name":"Teste bloqueado","visit_date":"2026-01-01","status":"recorded"}')$$,'42501','cell_access_denied','nome manual também respeita módulo bloqueado');
reset role;
update public.saas_unit_contracts set module_decisions='{"cells":false,"people":true}' where organization_id='b9000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.cell_visits_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',null,'2026-01-01','2026-01-31')$$,'42501','cell_access_denied','bloqueio de Células impede leitura');
reset role;
update public.organization_memberships set status='suspended' where id='e9000000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*)::integer from public.church_cell_visits),0,'RLS não expõe visitas após suspensão');
select * from finish();
rollback;
