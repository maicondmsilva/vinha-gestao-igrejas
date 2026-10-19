begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('ad000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operations-owner@example.test',now(),now(),now()),
('ad000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operations-secretary@example.test',now(),now(),now()),
('ad000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operations-leader@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('bd000000-0000-4000-8000-000000000001','Operações fictícias A','cell-ops-a','active'),('bd000000-0000-4000-8000-000000000002','Operações fictícias B','cell-ops-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('cd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','Sede fictícia','sede','headquarters'),
('cd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','Campus fictício','campus','campus'),
('cd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000002','Sede B','sede-b','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('ae000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000001','owner','active','cd000000-0000-4000-8000-000000000001'),
('ae000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000002','secretary','active','cd000000-0000-4000-8000-000000000001'),
('ae000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000003','leader','active','cd000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values('ae000000-0000-4000-8000-000000000002','cd000000-0000-4000-8000-000000000001','read'),('ae000000-0000-4000-8000-000000000003','cd000000-0000-4000-8000-000000000001','manage');
insert into public.people(id,organization_id,unit_id,full_name,status) values
('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','Pessoa fictícia um','active'),
('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','Pessoa fictícia dois','active'),
('dd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000002','Pessoa de outro campus','active');

select ok(not has_function_privilege('anon','public.member_choices(uuid,uuid,text)','EXECUTE') and not has_function_privilege('anon','public.cell_overview(uuid,uuid,date)','EXECUTE'),'lookup e visão geral não são públicos');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(public.member_choices('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','Pessoa')->'items'),2,'busca somente nomes da unidade');
select is(jsonb_array_length(public.member_choices('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','%%')->'items'),0,'caracteres de busca são literais');

select throws_ok($$select public.member_choices('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','P')$$,'22023','invalid_search','mínimo de duas letras');
select is(public.cell_directory_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','ef000000-0000-4000-8000-000000000001',0,'{"name":"Grupo de teste","leader_name":"Texto não confiável","leader_person_id":"dd000000-0000-4000-8000-000000000001","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala de teste","status":"active"}'::jsonb)->>'version','1','cria líder vinculado');
select is((select leader_name from public.church_cells where id='ef000000-0000-4000-8000-000000000001'),'Pessoa fictícia um','nome vem do cadastro, não do navegador');
select is(public.cell_directory_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','ef000000-0000-4000-8000-000000000001',0,'{"name":"Grupo de teste","leader_name":"Texto não confiável","leader_person_id":"dd000000-0000-4000-8000-000000000001","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala de teste","status":"active"}'::jsonb)->>'version','1','repetição vinculada é idempotente');
select is((select leader_person_id::text from public.church_cells where id='ef000000-0000-4000-8000-000000000001'),'dd000000-0000-4000-8000-000000000001','guarda identidade do membro');
select ok(not ((public.cell_directory_list('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001')->'items'->0) ? 'leader_person_id'),'consulta antiga mantém formato durante publicação');
select is(public.cell_directory_list_v2('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001')->'items'->0->>'leader_person_id','dd000000-0000-4000-8000-000000000001','consulta nova retorna vínculo de membro');
select throws_ok($$select public.cell_directory_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','ef000000-0000-4000-8000-000000000001',1,'{"name":"Grupo de teste","leader_name":"Texto não confiável","leader_person_id":"dd000000-0000-4000-8000-000000000003","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala de teste","status":"active"}'::jsonb)$$,'22023','invalid_leader','líder de outra unidade recusado');
select is(public.cell_directory_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','ef000000-0000-4000-8000-000000000001',1,'{"name":"Grupo de teste","leader_name":"Pessoa fictícia um","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala de teste","status":"active"}'::jsonb)->>'version','2','cliente antigo preserva vínculo se não muda nome');
select is((select leader_person_id::text from public.church_cells where id='ef000000-0000-4000-8000-000000000001'),'dd000000-0000-4000-8000-000000000001','identidade preservada após edição antiga');
select is(public.cell_directory_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','ef000000-0000-4000-8000-000000000001',2,'{"name":"Grupo de teste","leader_name":"Líder externo sem cadastro","leader_person_id":null,"meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala de teste","status":"active"}'::jsonb)->>'version','3','nome manual remove vínculo explicitamente');
select ok((select leader_person_id is null from public.church_cells where id='ef000000-0000-4000-8000-000000000001'),'nome manual não mantém identidade anterior');
select is((select count(*)::integer from public.people),3,'nome manual não cria membro');
select is(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->>'active','1','visão geral conta todos os grupos da unidade');
select is(jsonb_array_length(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->'series'),31,'série de dias completa');
select is(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->>'present','0','ausência de chamadas não inventa presença');
select is(public.ministry_language_save('bd000000-0000-4000-8000-000000000001',0,'{"celulas.geral":"Panorama"}')->'labels'->>'celulas.geral','Panorama','visão geral também pode ter nome personalizado');
select public.cell_operations_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','participant','ef000000-0000-4000-8000-000000000001','fa000000-0000-4000-8000-000000000001',0,'{"person_id":"dd000000-0000-4000-8000-000000000001","status":"active"}');
select public.cell_operations_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','participant','ef000000-0000-4000-8000-000000000001','fa000000-0000-4000-8000-000000000002',0,'{"person_id":"dd000000-0000-4000-8000-000000000002","status":"active"}');
select public.cell_operations_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','meeting','ef000000-0000-4000-8000-000000000001','fb000000-0000-4000-8000-000000000001',0,'{"topic":"Encontro fictício","meeting_date":"2026-10-10","meeting_time":"19:30","status":"completed","present":["fa000000-0000-4000-8000-000000000001"]}');
select is(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->>'completed','1','encontro contado sem multiplicar por participantes');
select is(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->>'expected','2','denominador usa chamada congelada');
select is(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->>'present','1','presença somente de quem compareceu');
select is(public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')->>'participants','2','pessoas participantes distintas');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.member_choices('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000002','Pessoa')$$,'42501','member_lookup_denied','líder não busca nomes de campus sem acesso');
select throws_ok($$select public.cell_overview('bd000000-0000-4000-8000-000000000002','cd000000-0000-4000-8000-000000000003','2026-10-01')$$,'42501','cell_access_denied','outro ministério não expõe indicadores');
reset role;
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions) select 'bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001',id,'active','{"cells":true,"people":false}' from public.saas_plans where billing_cycle='monthly' limit 1;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.member_choices('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','Pessoa')$$,'42501','member_lookup_denied','bloqueio de Pessoas impede busca');
select throws_ok($$select public.cell_overview('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','2026-10-01')$$,'42501','cell_access_denied','bloqueio de Pessoas impede consolidação');
select throws_ok($$select public.cell_directory_save('bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000001','ef000000-0000-4000-8000-000000000001',3,'{"name":"Grupo de teste","leader_name":"Texto não confiável","leader_person_id":"dd000000-0000-4000-8000-000000000001","meeting_day":3,"meeting_time":"19:30","meeting_format":"presential","location":"Sala de teste","status":"active"}'::jsonb)$$,'42501','cell_people_denied','não vincula membro com módulo bloqueado');
reset role;
select * from finish();
rollback;
