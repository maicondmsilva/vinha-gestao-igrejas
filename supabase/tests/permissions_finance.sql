begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Igreja P3 com duas igrejas; dono, tesouraria (papel antigo) e um membro que recebe permissões.
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('a7300000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p3-owner@example.test',now(),now(),now()),
 ('a7300000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p3-finance@example.test',now(),now(),now()),
 ('a7300000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p3-member@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('b7300000-0000-4000-8000-000000000001','P3 A','p3-synthetic-a','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c7300000-0000-4000-8000-000000000001','b7300000-0000-4000-8000-000000000001','Sede P3','sede','headquarters'),
 ('c7300000-0000-4000-8000-000000000002','b7300000-0000-4000-8000-000000000001','Outra P3','outra','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7300000-0000-4000-8000-000000000001','b7300000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','owner','active','c7300000-0000-4000-8000-000000000001'),
 ('d7300000-0000-4000-8000-000000000002','b7300000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000002','finance','active','c7300000-0000-4000-8000-000000000001'),
 ('d7300000-0000-4000-8000-000000000003','b7300000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000003','member','active','c7300000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level,include_children,organization_id) values('d7300000-0000-4000-8000-000000000002','c7300000-0000-4000-8000-000000000001','manage',false,'b7300000-0000-4000-8000-000000000001');
select ok(not has_function_privilege('authenticated','private.finance_f1_before_permissions(uuid,uuid[],text,jsonb)','EXECUTE'),'entrada antiga não é chamada direto');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('p3.q',jsonb_build_object('from',current_date,'to',current_date,'page',1)::text,true);
select lives_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'catalog','{"id":"f7300000-0000-4000-8000-000000000001","kind":"account","name":"Conta P3","direction":"","parent":"","shared":false,"version":0,"active":true,"details":{}}')$$,'dono cadastra conta');
select lives_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'catalog','{"id":"f7300000-0000-4000-8000-000000000002","kind":"category","name":"Ofertas P3","direction":"income","parent":"","shared":false,"version":0,"active":true,"details":{}}')$$,'dono cadastra categoria');
select set_config('p3.entry',jsonb_build_object('id','f7300000-0000-4000-8000-000000000010','kind','income','amountCents','5000','description','Oferta P3','account','f7300000-0000-4000-8000-000000000001','destination','','category','f7300000-0000-4000-8000-000000000002','center','','supplier','','person','','party','','method','pix','notes','','competence',current_date,'due',current_date,'paid',current_date)::text,true);

-- Papel antigo continua igual.
select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'snapshot',current_setting('p3.q')::jsonb)$$,'tesouraria antiga continua vendo');
select lives_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'entry',current_setting('p3.entry')::jsonb)$$,'tesouraria antiga continua lançando');
select throws_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000002']::uuid[],'snapshot',current_setting('p3.q')::jsonb)$$,'42501',null,'tesouraria antiga continua sem a outra igreja');

-- Membro sem permissão: nada.
select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'snapshot',current_setting('p3.q')::jsonb)$$,'42501',null,'membro sem permissão não vê o Financeiro');

-- Dono concede só "ver lançamentos" e "ver relatórios" na sede.
select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.permission_admin('b7300000-0000-4000-8000-000000000001','set','{"membership":"d7300000-0000-4000-8000-000000000003","permission":"finance.entries","unit":"c7300000-0000-4000-8000-000000000001","actions":["view"],"includeChildren":false}')$$,'concede ver lançamentos');
select lives_ok($$select public.permission_admin('b7300000-0000-4000-8000-000000000001','set','{"membership":"d7300000-0000-4000-8000-000000000003","permission":"finance.reports","unit":"c7300000-0000-4000-8000-000000000001","actions":["view"],"includeChildren":false}')$$,'concede ver relatórios');

select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'snapshot',current_setting('p3.q')::jsonb)$$,'membro com permissão vê lançamentos');
select throws_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'entry',jsonb_set(current_setting('p3.entry')::jsonb,'{id}','"f7300000-0000-4000-8000-000000000011"'))$$,'42501','finance_permission_denied','só ver não permite lançar');
select throws_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000002']::uuid[],'snapshot',current_setting('p3.q')::jsonb)$$,'42501',null,'fora da abrangência concedida');
select lives_ok($$select public.finance_f6('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'report',jsonb_build_object('from',current_date,'to',current_date,'dateBy','cash','report','book'))$$,'relatório na tela');
select throws_ok($$select public.finance_f6('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'report',jsonb_build_object('from',current_date,'to',current_date,'dateBy','cash','report','book','export',true))$$,'42501','finance_permission_denied','exportar exige a ação exportar');
select throws_ok($$select public.finance_f2('b7300000-0000-4000-8000-000000000001','c7300000-0000-4000-8000-000000000001','history','{"title":"f7300000-0000-4000-8000-000000000010"}')$$,'42501','finance_permission_denied','contas a receber/pagar não concedidas');
select ok((select r->'units' @> '[{"id":"c7300000-0000-4000-8000-000000000001"}]' from (select jsonb_path_query_first(public.access_context(),'$.organizations[*] ? (@.id=="b7300000-0000-4000-8000-000000000001")') r) x) is not false,'igreja concedida aparece para escolher');

-- Com "criar", passa a lançar.
select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.permission_admin('b7300000-0000-4000-8000-000000000001','set','{"membership":"d7300000-0000-4000-8000-000000000003","permission":"finance.entries","unit":"c7300000-0000-4000-8000-000000000001","actions":["view","create"],"includeChildren":false}')$$,'concede criar');
select set_config('request.jwt.claims','{"sub":"a7300000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'entry',jsonb_set(current_setting('p3.entry')::jsonb,'{id}','"f7300000-0000-4000-8000-000000000012"'))$$,'com criar, lança');
select throws_ok($$select public.finance_f1('b7300000-0000-4000-8000-000000000001',array['c7300000-0000-4000-8000-000000000001']::uuid[],'delete','{"id":"f7300000-0000-4000-8000-000000000012","version":1}')$$,'42501','finance_permission_denied','excluir exige a ação excluir');
reset role;
select * from finish();
rollback;
