begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Igreja P1: sede com uma filha; dono, administrador, secretaria e tesoureiro (papel membro).
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('a7100000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p1-owner@example.test',now(),now(),now()),
 ('a7100000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p1-admin@example.test',now(),now(),now()),
 ('a7100000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p1-secretary@example.test',now(),now(),now()),
 ('a7100000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p1-treasurer@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('b7100000-0000-4000-8000-000000000001','P1 A','p1-synthetic-a','active'),('b7100000-0000-4000-8000-000000000002','P1 B','p1-synthetic-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c7100000-0000-4000-8000-000000000001','b7100000-0000-4000-8000-000000000001','Sede P1','sede','headquarters'),
 ('c7100000-0000-4000-8000-000000000003','b7100000-0000-4000-8000-000000000002','Sede P1 B','sede','headquarters');
insert into public.organization_units(id,organization_id,name,slug,unit_type,parent_unit_id) values
 ('c7100000-0000-4000-8000-000000000002','b7100000-0000-4000-8000-000000000001','Filha P1','filha','campus','c7100000-0000-4000-8000-000000000001');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7100000-0000-4000-8000-000000000001','b7100000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000001','owner','active','c7100000-0000-4000-8000-000000000001'),
 ('d7100000-0000-4000-8000-000000000002','b7100000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000002','admin','active','c7100000-0000-4000-8000-000000000001'),
 ('d7100000-0000-4000-8000-000000000003','b7100000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000003','secretary','active','c7100000-0000-4000-8000-000000000001'),
 ('d7100000-0000-4000-8000-000000000004','b7100000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000004','member','active','c7100000-0000-4000-8000-000000000001');

insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by) values('e7100000-0000-4000-8000-000000000001','b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','Célula P1',3,'20:00','presential','a7100000-0000-4000-8000-000000000001');
select ok(not has_table_privilege('authenticated','private.permission_grants','SELECT'),'concessões não são lidas direto');
select ok(not has_function_privilege('anon','public.permission_admin(uuid,text,jsonb)','EXECUTE'),'visitante sem gestão de permissões');
select ok((select count(*) from private.permission_catalog)>=30,'catálogo de seções carregado');
select ok((select count(*) from private.permission_templates)=8,'oito modelos prontos');

set local role authenticated;
-- Sem concessão, nada muda: a regra nova só concede o que foi dado explicitamente.
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select ok(not private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','church.settings','view'),'sem concessão, sem acesso');
-- O dono tem tudo.
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select ok(private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000002','church.settings','edit'),'dono tem tudo');
select ok(not private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','church.settings','delete'),'ação fora do catálogo é recusada até para o dono');
select ok(not private.can('b7100000-0000-4000-8000-000000000002','c7100000-0000-4000-8000-000000000003','church.settings','view'),'dono de uma organização não acessa outra');
-- Concessão na sede incluindo filhas.
select lives_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000004","permission":"church.settings","unit":"c7100000-0000-4000-8000-000000000001","actions":["view"],"includeChildren":true}')$$,'dono concede seção com abrangência');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000004","permission":"church.settings","actions":["delete"]}')$$,'22023','invalid_actions','ação inexistente na seção é recusada');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000001","permission":"church.settings","actions":["view"]}')$$,'22023','owner_has_all_permissions','dono não recebe concessões');
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select ok(private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','church.settings','view'),'concessão vale na sede');
select ok(private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000002','church.settings','view'),'e nas filhas quando incluídas');
select ok(not private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','church.settings','edit'),'só as ações concedidas');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','catalog','{}')$$,'42501','permission_admin_denied','membro comum não gerencia permissões');
-- Sem filhas, a concessão fica só na igreja indicada.
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000004","permission":"church.settings","unit":"c7100000-0000-4000-8000-000000000001","actions":["view","edit"],"includeChildren":false}')$$,'concessão atualizada');
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select ok(private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','church.settings','edit'),'nova ação vale');
select ok(not private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000002','church.settings','view'),'filha fora quando não incluída');
-- Limite a grupos: só nas células concedidas.
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000003","permission":"cells.reports","actions":["view","create"],"groupKind":"cell","groups":["e7100000-0000-4000-8000-000000000001"]}')$$,'administrador concede seção limitada a grupos');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000003","permission":"settings.users","actions":["view"]}')$$,'42501','permission_admin_denied','só o dono concede Usuários e permissões');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000002","permission":"church.settings","actions":["view"]}')$$,'42501','permission_admin_denied','administrador não altera outro administrador');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000003","permission":"finance.entries","actions":["view"],"groupKind":"cell","groups":["e7100000-0000-4000-8000-000000000001"]}')$$,'22023','invalid_groups','seção sem grupos não aceita limite');
select throws_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','set','{"membership":"d7100000-0000-4000-8000-000000000003","permission":"cells.reports","actions":["view"],"groupKind":"cell","groups":["c7100000-0000-4000-8000-000000000001"]}')$$,'22023','invalid_groups','grupo precisa ser célula da própria organização');
select ok(jsonb_array_length(public.permission_admin('b7100000-0000-4000-8000-000000000001','groups','{}')->'cell')=1,'lista de células para limitar');
select lives_ok($$select public.permission_admin('b7100000-0000-4000-8000-000000000001','apply_template','{"membership":"d7100000-0000-4000-8000-000000000003","template":"secretaria"}')$$,'modelo aplicado');
select is(jsonb_array_length(public.permission_admin('b7100000-0000-4000-8000-000000000001','list','{"membership":"d7100000-0000-4000-8000-000000000003"}')->'grants'),9,'modelo + concessão limitada');
reset role;
select is((select count(*)::integer from public.audit_logs where organization_id='b7100000-0000-4000-8000-000000000001' and action like 'permissions.%'),4,'toda alteração vai para a auditoria');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a7100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select ok(private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','cells.reports','create','e7100000-0000-4000-8000-000000000001'),'grupo concedido');
select ok(not private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','cells.reports','create','e7100000-0000-4000-8000-000000000002'),'outro grupo recusado');
select ok(not private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000001','cells.reports','create'),'sem grupo informado, recusado');
select ok(private.can('b7100000-0000-4000-8000-000000000001','c7100000-0000-4000-8000-000000000002','people.members','edit'),'modelo sem igreja vale em todo o ministério');
reset role;
select * from finish();
rollback;
