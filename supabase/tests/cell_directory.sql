begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('ac000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cell-owner@example.test',now(),now(),now()),
('ac000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cell-secretary@example.test',now(),now(),now()),
('ac000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cell-leader@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('bc000000-0000-4000-8000-000000000001','Células A','cells-a','active'),('bc000000-0000-4000-8000-000000000002','Células B','cells-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('cc000000-0000-4000-8000-000000000001','bc000000-0000-4000-8000-000000000001','Sede células','sede','headquarters'),
('cc000000-0000-4000-8000-000000000002','bc000000-0000-4000-8000-000000000001','Campus células','campus','campus'),
('cc000000-0000-4000-8000-000000000003','bc000000-0000-4000-8000-000000000002','Sede B','sede-b','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('dc000000-0000-4000-8000-000000000001','bc000000-0000-4000-8000-000000000001','ac000000-0000-4000-8000-000000000001','owner','active','cc000000-0000-4000-8000-000000000001'),
('dc000000-0000-4000-8000-000000000002','bc000000-0000-4000-8000-000000000001','ac000000-0000-4000-8000-000000000002','secretary','active','cc000000-0000-4000-8000-000000000001'),
('dc000000-0000-4000-8000-000000000003','bc000000-0000-4000-8000-000000000001','ac000000-0000-4000-8000-000000000003','leader','active','cc000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values
('dc000000-0000-4000-8000-000000000002','cc000000-0000-4000-8000-000000000001','read'),
('dc000000-0000-4000-8000-000000000003','cc000000-0000-4000-8000-000000000001','manage');
select ok(not has_table_privilege('anon','public.church_cells','SELECT'),'visitantes sem leitura');
select ok(not has_table_privilege('authenticated','public.church_cells','INSERT'),'sem inserção direta');
select ok(not has_table_privilege('authenticated','public.church_cells','UPDATE'),'sem atualização direta');
select ok(not has_table_privilege('authenticated','public.church_cells','DELETE'),'sem exclusão física');
select ok(not has_function_privilege('anon','public.cell_directory_save(uuid,uuid,uuid,integer,jsonb)','EXECUTE'),'visitantes sem RPC');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',0,'{"name":"Esperança","leader_name":"Responsável fictício","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala fictícia","status":"active"}')->>'version','1','cria célula');
select is(public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',0,'{"name":"Esperança","leader_name":"Responsável fictício","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala fictícia","status":"active"}')->>'version','1','repetir criação não duplica');
select is((select count(*)::integer from public.audit_logs where entity_id='ec000000-0000-4000-8000-000000000001'),1,'auditoria única e atômica');
select is(jsonb_array_length(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')->'items'),1,'lista da unidade');
select is(jsonb_array_length(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000002')->'items'),0,'não mistura unidades');
select throws_ok($$select public.cell_directory_list('bc000000-0000-4000-8000-000000000002','cc000000-0000-4000-8000-000000000003')$$,'42501','cell_access_denied','outro ministério bloqueado');
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000002','ec000000-0000-4000-8000-000000000001',1,'{"name":"Esperança","leader_name":"","meeting_day":3,"meeting_time":"19:30","meeting_format":"online","location":"","status":"active"}')$$,'42501','cell_access_denied','não transfere unidade');
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',99,'{"name":"Esperança","leader_name":"","meeting_day":3,"meeting_time":"19:30","meeting_format":"online","location":"","status":"active"}')$$,'40001','cell_version_conflict','edição desatualizada recusada');
select is(public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',1,'{"name":"Esperança","leader_name":"","meeting_day":3,"meeting_time":"19:30","meeting_format":"online","location":"","status":"archived"}')->>'version','2','arquiva sem apagar');
select is((select status from public.church_cells where id='ec000000-0000-4000-8000-000000000001'),'archived','histórico preservado');
select is(public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',2,'{"name":"Esperança","leader_name":"","meeting_day":3,"meeting_time":"19:30","meeting_format":"online","location":"","status":"active"}')->>'version','3','reativa cadastro');
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')->>'canManage','false','secretaria somente consulta');
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',3,'{}')$$,'42501','cell_access_denied','secretaria não grava');
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')->>'canManage','true','líder com gestão pode editar');
select throws_ok($$select public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000002')$$,'42501','cell_access_denied','líder não acessa campus sem concessão');
reset role;
update public.membership_unit_access set access_level='read' where membership_id='dc000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',3,'{}')$$,'42501','cell_access_denied','acesso revalidado após revogação');
reset role;
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by)
select extensions.gen_random_uuid(),'bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','Célula fictícia paginada '||g,3,'19:30','online','ac000000-0000-4000-8000-000000000001' from generate_series(1,101)g;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')->'items'),100,'página limitada a cem');
select is(jsonb_array_length(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001',(public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')->>'nextCursor')::uuid)->'items'),2,'cursor entrega os registros restantes sem repetir');
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',3,'{"name":"Esperança","leader_name":"","meeting_day":3,"meeting_time":"19:30","meeting_format":"online","location":"","status":"active","created_by":"fake"}')$$,'22023','invalid_cell_input','campos administrativos recusados no banco');
reset role;
update auth.users set email_confirmed_at=null where id='ac000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',3,'{}')$$,'42501','self_service_identity_unavailable','conta não confirmada não grava');
reset role;
update auth.users set email_confirmed_at=now() where id='ac000000-0000-4000-8000-000000000001';
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions)
select 'bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001',id,'active','{"cells":false}' from public.saas_plans where billing_cycle='monthly' limit 1;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')$$,'42501','cell_access_denied','contrato da unidade bloqueia consulta');
select throws_ok($$select public.cell_directory_save('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001','ec000000-0000-4000-8000-000000000001',3,'{}')$$,'42501','cell_access_denied','contrato da unidade bloqueia gravação');
select is((select count(*)::integer from public.church_cells),0,'RLS também bloqueia leitura direta');
reset role;
update public.organizations set status='suspended' where id='bc000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.cell_directory_list('bc000000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000001')$$,'42501','cell_access_denied','ministério suspenso recusado');
reset role;
select * from finish();
rollback;
