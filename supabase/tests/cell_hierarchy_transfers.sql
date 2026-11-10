begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('a9000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','flow-owner@example.test',now(),now(),now()),
('a9000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','flow-leader@example.test',now(),now(),now()),
('a9000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','flow-reader@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('b9000000-0000-4000-8000-000000000001','Fluxos fictícios','cell-flow-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','Sede fictícia','sede','headquarters'),
('c9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','Campus fictício','campus','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('e9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','owner','active','c9000000-0000-4000-8000-000000000001'),
('e9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000002','leader','active','c9000000-0000-4000-8000-000000000001'),
('e9000000-0000-4000-8000-000000000003','b9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000003','secretary','active','c9000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values
('e9000000-0000-4000-8000-000000000002','c9000000-0000-4000-8000-000000000001','manage'),
('e9000000-0000-4000-8000-000000000003','c9000000-0000-4000-8000-000000000001','read');
insert into public.people(id,organization_id,unit_id,full_name,status) values('d9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Participante fictício','active');
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by)
select ('f9000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b9000000-0000-4000-8000-000000000001',case when n=3 then 'c9000000-0000-4000-8000-000000000002'::uuid else 'c9000000-0000-4000-8000-000000000001'::uuid end,'Grupo fictício '||n,1,'19:00','presential','a9000000-0000-4000-8000-000000000001' from generate_series(1,3)n;
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by)
select ('fa900000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b9000000-0000-4000-8000-000000000001',case when n=4 then 'c9000000-0000-4000-8000-000000000002'::uuid else 'c9000000-0000-4000-8000-000000000001'::uuid end,'Rede fictícia '||n,'active','a9000000-0000-4000-8000-000000000001' from generate_series(1,4)n;
insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values
('fb900000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','d9000000-0000-4000-8000-000000000001','active','a9000000-0000-4000-8000-000000000001');
create function pg_temp.flow(k text,id uuid,v integer,d jsonb default '{}') returns jsonb language sql as $$select public.cell_flows_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',k,id,v,d)$$;
create function pg_temp.flows(k text,a uuid default null) returns jsonb language sql as $$select public.cell_flows_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',k,a)$$;
select ok(not has_table_privilege('authenticated','public.church_cell_network_parents','INSERT,UPDATE,DELETE,TRUNCATE'),'hierarquia sem gravação direta');
select ok(not has_table_privilege('authenticated','public.church_cell_transfers','INSERT,UPDATE,DELETE,TRUNCATE'),'transferência sem gravação direta');
select ok(not has_function_privilege('anon','public.cell_flows_save(uuid,uuid,text,uuid,integer,jsonb)','EXECUTE'),'sem escrita anônima');
select ok(not has_function_privilege('anon','public.cell_flows_read(uuid,uuid,text,uuid)','EXECUTE'),'sem leitura anônima');
select ok(not(select prosecdef from pg_proc where oid='public.cell_flows_save(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure),'wrapper invoker');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000002',0,'{"parent_id":"fa900000-0000-4000-8000-000000000001"}')->>'version','1','segundo nível');
select is(pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000003',0,'{"parent_id":"fa900000-0000-4000-8000-000000000002"}')->>'version','1','terceiro nível');
select is(pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000003',0,'{"parent_id":"fa900000-0000-4000-8000-000000000002"}')->>'version','1','retry idempotente');
select is(pg_temp.flows('hierarchy')->'items'->2->>'path','Rede fictícia 1 → Rede fictícia 2 → Rede fictícia 3','caminho em vários níveis');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000001',0,'{"parent_id":"fa900000-0000-4000-8000-000000000003"}')$$,'22023','cell_hierarchy_cycle','ciclo indireto recusado');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000001',0,'{"parent_id":"fa900000-0000-4000-8000-000000000001"}')$$,'22023','cell_hierarchy_cycle','autovínculo recusado');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000001',0,'{"parent_id":"fa900000-0000-4000-8000-000000000004"}')$$,'42501','cell_access_denied','outro campus recusado');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000003',0,'{"parent_id":null}')$$,'40001','cell_flow_conflict','versão antiga recusada');
select lives_ok($$select public.cell_operations_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','meeting','f9000000-0000-4000-8000-000000000001','fc900000-0000-4000-8000-000000000001',0,'{"topic":"Encontro histórico","meeting_date":"2026-10-19","meeting_time":"19:00","status":"completed","present":["fb900000-0000-4000-8000-000000000001"]}')$$,'encontro antes da transferência');
select is(pg_temp.flow('request','fd900000-0000-4000-8000-000000000001',0,'{"source_id":"fb900000-0000-4000-8000-000000000001","target_cell_id":"f9000000-0000-4000-8000-000000000002","source_version":1}')->>'version','1','solicita sem mover');
select is((select status from public.church_cell_participants where id='fb900000-0000-4000-8000-000000000001'),'active','origem continua ativa até aceite');
select is(pg_temp.flow('request','fd900000-0000-4000-8000-000000000001',0,'{"source_id":"fb900000-0000-4000-8000-000000000001","target_cell_id":"f9000000-0000-4000-8000-000000000002","source_version":1}')->>'version','1','solicitação repetida idempotente');
select throws_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000002',0,'{"source_id":"fb900000-0000-4000-8000-000000000001","target_cell_id":"f9000000-0000-4000-8000-000000000002","source_version":1}')$$,'23505',null,'uma solicitação pendente por origem');
select is(pg_temp.flow('accept','fd900000-0000-4000-8000-000000000001',1)->>'version','2','aceite atômico');
select is(pg_temp.flow('accept','fd900000-0000-4000-8000-000000000001',1)->>'version','2','repetir aceite não duplica');
select is((select status from public.church_cell_participants where id='fb900000-0000-4000-8000-000000000001'),'inactive','origem inativada');
select is((select count(*)::integer from public.church_cell_participants where cell_id='f9000000-0000-4000-8000-000000000002' and status='active'),1,'destino ativo único');
select is((select count(*)::integer from public.church_cell_attendance where meeting_id='fc900000-0000-4000-8000-000000000001' and participant_id='fb900000-0000-4000-8000-000000000001' and present),1,'presença histórica preservada');
select throws_ok($$select pg_temp.flow('reject','fd900000-0000-4000-8000-000000000001',2)$$,'40001','cell_flow_conflict','não reescreve decisão');
select is(pg_temp.flows('transfers')->'items'->0->>'person_name','Participante fictício','nome vem do cadastro');
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is(pg_temp.flows('hierarchy')->>'canManage','false','leitor sem gestão');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000003',1,'{"parent_id":null}')$$,'42501','cell_access_denied','leitor não altera');
select throws_ok($$select public.cell_flows_read('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000002','hierarchy')$$,'42501','cell_access_denied','escopo sem concessão invisível');
reset role;
-- A new request from a manager, then suspension before decision.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000003',0,jsonb_build_object('source_id',(select id from public.church_cell_participants where cell_id='f9000000-0000-4000-8000-000000000002'),'target_cell_id','f9000000-0000-4000-8000-000000000001','source_version',1))$$,'líder solicita retorno');
reset role;
update public.organization_memberships set status='suspended' where id='e9000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select pg_temp.flow('accept','fd900000-0000-4000-8000-000000000003',1)$$,'42501','cell_access_denied','emissor suspenso impede aceite');
select is(pg_temp.flow('reject','fd900000-0000-4000-8000-000000000003',1)->>'version','2','gestor pode recusar pendência inválida');
select lives_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000004',0,jsonb_build_object('source_id',(select id from public.church_cell_participants where cell_id='f9000000-0000-4000-8000-000000000002'),'target_cell_id','f9000000-0000-4000-8000-000000000001','source_version',1))$$,'nova solicitação');
select is(pg_temp.flow('cancel','fd900000-0000-4000-8000-000000000004',1)->>'version','2','emissor cancela sem mover');
select lives_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000005',0,jsonb_build_object('source_id',(select id from public.church_cell_participants where cell_id='f9000000-0000-4000-8000-000000000002'),'target_cell_id','f9000000-0000-4000-8000-000000000001','source_version',1))$$,'solicita retorno válido');
select is(pg_temp.flow('accept','fd900000-0000-4000-8000-000000000005',1)->>'version','2','retorno reativa origem antiga');
select is((select version from public.church_cell_participants where id='fb900000-0000-4000-8000-000000000001'),3,'mesmo vínculo reativado com versão nova');
select throws_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000006',0,'{"source_id":"fb900000-0000-4000-8000-000000000001","target_cell_id":"f9000000-0000-4000-8000-000000000003","source_version":3}')$$,'42501','cell_access_denied','transferência entre unidades recusada');
select throws_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000006',0,'{"source_id":"fb900000-0000-4000-8000-000000000001","target_cell_id":"f9000000-0000-4000-8000-000000000002","source_version":1}')$$,'40001','cell_flow_conflict','versão antiga do participante recusada');
select lives_ok($$select pg_temp.flow('request','fd900000-0000-4000-8000-000000000006',0,'{"source_id":"fb900000-0000-4000-8000-000000000001","target_cell_id":"f9000000-0000-4000-8000-000000000002","source_version":3}')$$,'solicita para validar mudança posterior');
select lives_ok($$select public.cell_operations_save('b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','participant','f9000000-0000-4000-8000-000000000001','fb900000-0000-4000-8000-000000000001',3,'{"person_id":"d9000000-0000-4000-8000-000000000001","status":"inactive"}')$$,'gestor inativa vínculo após solicitação');
select throws_ok($$select pg_temp.flow('accept','fd900000-0000-4000-8000-000000000006',1)$$,'40001','cell_flow_conflict','aceite revalida vínculo atual');
select is(pg_temp.flow('cancel','fd900000-0000-4000-8000-000000000006',1)->>'version','2','solicitante encerra pendência obsoleta');
reset role;
select is((select count(*)::integer from public.audit_logs where organization_id='b9000000-0000-4000-8000-000000000001' and action like 'cell.flow_%'),12,'auditoria de cada transição sem duplicar retries');
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by)
select ('fa900000-0000-4000-9000-'||lpad(n::text,12,'0'))::uuid,'b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Nível fictício '||n,'active','a9000000-0000-4000-8000-000000000001' from generate_series(1,101)n;
insert into public.church_cell_network_parents(network_id,organization_id,unit_id,parent_id,updated_by)
select ('fa900000-0000-4000-9000-'||lpad(n::text,12,'0'))::uuid,'b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001',('fa900000-0000-4000-9000-'||lpad((n-1)::text,12,'0'))::uuid,'a9000000-0000-4000-8000-000000000001' from generate_series(2,32)n;
set local role authenticated;
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-9000-000000000033',0,'{"parent_id":"fa900000-0000-4000-9000-000000000032"}')$$,'22023','cell_hierarchy_depth','mais de 32 níveis recusado');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-9000-000000000001',0,'{"parent_id":"fa900000-0000-4000-8000-000000000003"}')$$,'22023','cell_hierarchy_depth','movimentação considera profundidade de descendentes');
select is(jsonb_array_length(pg_temp.flows('hierarchy')->'items'),100,'hierarquia paginada');
select is(jsonb_array_length(pg_temp.flows('hierarchy',(pg_temp.flows('hierarchy')->>'nextCursor')::uuid)->'items'),4,'cursor continua sem duplicar');
reset role;
update public.organizations set status='suspended' where id='b9000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.flows('transfers')$$,'42501','cell_access_denied','ministério suspenso recusa leitura');
select throws_ok($$select pg_temp.flow('hierarchy','fa900000-0000-4000-8000-000000000003',1,'{"parent_id":null}')$$,'42501','cell_access_denied','ministério suspenso recusa gestão');
select is((select count(*)::integer from public.church_cell_transfers),0,'RLS oculta transferências suspensas');
reset role;
select * from finish();
rollback;
