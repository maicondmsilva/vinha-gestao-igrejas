begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('a8000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','net-owner@example.test',now(),now(),now()),
('a8000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','net-reader@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('b8000000-0000-4000-8000-000000000001','Redes fictícias A','network-test-a','active'),('b8000000-0000-4000-8000-000000000002','Redes fictícias B','network-test-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('c8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','Sede fictícia A','sede','headquarters'),
('c8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','Campus fictício A','campus','campus'),
('c8000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000002','Sede fictícia B','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('e8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','owner','active','c8000000-0000-4000-8000-000000000001'),
('e8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000002','secretary','active','c8000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values('e8000000-0000-4000-8000-000000000002','c8000000-0000-4000-8000-000000000001','read');
insert into public.people(id,organization_id,unit_id,full_name,status) values
('d8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','Supervisor fictício canônico','active'),
('d8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','Supervisor de outro campus','active');
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by) values
('f8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','Grupo fictício A',1,'19:00','presential','a8000000-0000-4000-8000-000000000001');
create function pg_temp.nsave(kind text,id uuid,v integer,d jsonb) returns jsonb language sql as $$select public.cell_networks_save('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001',kind,id,v,d)$$;
create function pg_temp.nread(kind text,n uuid default null,a uuid default null) returns jsonb language sql as $$select public.cell_networks_read('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001',kind,n,a)$$;
select ok(not has_table_privilege('authenticated','public.church_cell_networks','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'redes sem gravação direta');
select ok(not has_table_privilege('authenticated','public.church_cell_network_links','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'vínculos sem gravação direta');
select ok(not has_function_privilege('anon','public.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb)','EXECUTE'),'escrita não anônima');
select ok(not has_function_privilege('anon','public.cell_networks_read(uuid,uuid,text,uuid,uuid)','EXECUTE'),'leitura não anônima');
select ok(not(select prosecdef from pg_proc where oid='public.cell_networks_save(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure),'API invoker');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(pg_temp.nsave('network','fa800000-0000-4000-8000-000000000001',0,'{"name":"Rede inicial","supervisor_name":"Nome externo","supervisor_person_id":null,"status":"active"}')->>'version','1','rede manual criada');
select is(pg_temp.nsave('network','fa800000-0000-4000-8000-000000000001',0,'{"name":"Rede inicial","supervisor_name":"Nome externo","supervisor_person_id":null,"status":"active"}')->>'version','1','retry idempotente');
select is(pg_temp.nsave('network','fa800000-0000-4000-8000-000000000002',0,'{"name":"Rede com membro","supervisor_name":"Texto não confiável","supervisor_person_id":"d8000000-0000-4000-8000-000000000001","status":"active"}')->>'version','1','supervisor membro selecionado');
select is((select supervisor_name from public.church_cell_networks where id='fa800000-0000-4000-8000-000000000002'),'Supervisor fictício canônico','nome vem do cadastro');
select throws_ok($$select pg_temp.nsave('network','fa800000-0000-4000-8000-000000000003',0,'{"name":"rede inicial","supervisor_name":"","supervisor_person_id":null,"status":"active"}')$$,'23505',null,'nome ativo único sem distinção de caixa');
select throws_ok($$select pg_temp.nsave('network','fa800000-0000-4000-8000-000000000003',0,'{"name":"Outro campus","supervisor_name":"Teste","supervisor_person_id":"d8000000-0000-4000-8000-000000000002","status":"active"}')$$,'22023','invalid_network_person','não vincula pessoa de outra unidade');
select is(pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',0,'{"network_id":"fa800000-0000-4000-8000-000000000001"}')->>'version','1','associa grupo');
select is(pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',0,'{"network_id":"fa800000-0000-4000-8000-000000000001"}')->>'version','1','retry de vínculo idempotente');
select is(pg_temp.nread('cells')->'items'->0->>'network_name','Rede inicial','lista grupo com rede atual');
select throws_ok($$select pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',0,'{"network_id":"fa800000-0000-4000-8000-000000000002"}')$$,'40001','network_version_conflict','versão atrasada recusada');
select is(pg_temp.nsave('network','fa800000-0000-4000-8000-000000000001',1,'{"name":"Rede inicial","supervisor_name":"Nome externo","supervisor_person_id":null,"status":"archived"}')->>'version','2','arquiva sem apagar');
select is(pg_temp.nread('cells')->'items'->0->>'network_status','archived','vínculo arquivado permanece visível');
select throws_ok($$select pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',1,'{"network_id":"fa800000-0000-4000-8000-000000000001"}')$$,'22023','invalid_network_target','não associa a rede arquivada');
select is(pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',1,'{"network_id":null}')->>'version','2','desvincula preservando linha e versão');
select ok((pg_temp.nread('cells')->'items'->0->'network_id')='null'::jsonb,'grupo sem rede após desvincular');
select is(pg_temp.nsave('network','fa800000-0000-4000-8000-000000000002',1,'{"name":"Rede com membro","supervisor_name":"Responsável externo corrigido","supervisor_person_id":null,"status":"active"}')->>'version','2','editar para manual remove identidade');
select ok((select supervisor_person_id is null from public.church_cell_networks where id='fa800000-0000-4000-8000-000000000002'),'referência antiga removida');
select is((select count(*)::integer from public.people),2,'nenhuma pessoa criada automaticamente');
select throws_ok($$select public.cell_networks_read('b8000000-0000-4000-8000-000000000002','c8000000-0000-4000-8000-000000000003','networks')$$,'42501','cell_access_denied','outro ministério recusado');
select is(public.ministry_language_save('b8000000-0000-4000-8000-000000000001',0,'{"celulas.redes":"Redes de PG","celulas.supervisor":"Supervisor de PG"}')->'labels'->>'celulas.redes','Redes de PG','termos configuráveis');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(pg_temp.nread('networks')->>'canManage','false','leitor não gerencia');
select throws_ok($$select pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',2,'{"network_id":null}')$$,'42501','cell_access_denied','leitor não grava');
select throws_ok($$select public.cell_networks_read('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','networks')$$,'42501','cell_access_denied','leitor não vê campus sem acesso');
reset role;
select is((select count(*)::integer from public.audit_logs where organization_id='b8000000-0000-4000-8000-000000000001' and action like 'cell.network_%'),6,'auditoria sem duplicar retry');
select ok(exists(select 1 from public.audit_logs where organization_id='b8000000-0000-4000-8000-000000000001' and action='cell.network_assignment_saved' and metadata->>'previous_network_id'='fa800000-0000-4000-8000-000000000001' and metadata->'network_id'='null'::jsonb),'histórico guarda identidade da rede anterior');
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by)
select ('fa800000-0000-4000-9000-'||lpad(n::text,12,'0'))::uuid,'b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','Rede paginada '||n,'active','a8000000-0000-4000-8000-000000000001' from generate_series(1,101)n;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(pg_temp.nread('networks')->'items'),100,'paginação limitada');
select is(jsonb_array_length(pg_temp.nread('networks',null,(pg_temp.nread('networks')->>'nextCursor')::uuid)->'items'),3,'cursor não repete redes');
select is(jsonb_array_length(pg_temp.nread('cells','fa800000-0000-4000-8000-000000000001')->'items'),0,'filtro de rede não inclui grupo já desvinculado');
select throws_ok($$select public.cell_networks_save('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','network','fa800000-0000-4000-8000-000000000002',2,'{"name":"Transferência indevida","supervisor_name":"","supervisor_person_id":null,"status":"active"}')$$,'42501','cell_access_denied','não transfere rede para outro campus');
reset role;
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions) select 'b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001',id,'active','{"cells":true,"people":false}' from public.saas_plans where billing_cycle='monthly' limit 1;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select pg_temp.nread('networks')$$,'42501','cell_access_denied','bloqueio de Pessoas impede leitura');
select throws_ok($$select pg_temp.nsave('assignment','f8000000-0000-4000-8000-000000000001',2,'{"network_id":null}')$$,'42501','cell_access_denied','bloqueio impede gravação');
reset role;
update public.saas_unit_contracts set module_decisions='{"cells":false,"people":true}' where organization_id='b8000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.nread('cells')$$,'42501','cell_access_denied','bloqueio de Células impede leitura');
reset role;
update public.organization_memberships set status='suspended' where id='e8000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((select count(*)::integer from public.church_cell_networks),0,'RLS recusa conta suspensa');
select * from finish();
rollback;
