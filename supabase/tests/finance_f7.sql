begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values('af770000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f7-owner@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('bf770000-0000-4000-8000-000000000001','Revisão fictício','f7-synthetic','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values('cf770000-0000-4000-8000-000000000001','bf770000-0000-4000-8000-000000000001','Sede Revisão','sede','headquarters'),('cf770000-0000-4000-8000-000000000002','bf770000-0000-4000-8000-000000000001','Campus Revisão','campus','campus');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values('bf770000-0000-4000-8000-000000000001','af770000-0000-4000-8000-000000000001','owner','active','cf770000-0000-4000-8000-000000000001');
select set_config('f7.org','bf770000-0000-4000-8000-000000000001',true);select set_config('f7.unit','cf770000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"af770000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.finance_f1(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'catalog','{"id":"df770000-0000-4000-8000-000000000001","kind":"account","name":"Banco Revisão"}');
select public.finance_f1(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'catalog','{"id":"df770000-0000-4000-8000-000000000002","kind":"category","name":"Doações Revisão","direction":"income"}');
select public.finance_f1(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'entry',jsonb_build_object('id','ab770000-0000-4000-8000-000000000001','kind','income','amountCents','1000','description','Previsão inicial fictícia','account','df770000-0000-4000-8000-000000000001','category','df770000-0000-4000-8000-000000000002','competence',current_date,'due',current_date,'method','pix'));
reset role;

set local role authenticated;
select public.finance_f1(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'entry',jsonb_build_object('id','ab770000-0000-4000-8000-000000000002','kind','income','amountCents','10000','description','Receita fictícia F6','account','df770000-0000-4000-8000-000000000001','category','df770000-0000-4000-8000-000000000002','party','Pessoa fictícia F6','competence',current_date,'due',current_date,'paid',current_date,'method','pix'));
select set_config('f7.filters',jsonb_build_object('from',current_date,'to',current_date,'dateBy','cash','report','book')::text,true);

-- F7 assertions
select lives_ok($$select public.finance_f6(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'report',current_setting('f7.filters')::jsonb||'{"export":true}')$$,'preparação de exportação é autorizada no mesmo escopo');
select set_config('f7.export',public.finance_f6(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'report',current_setting('f7.filters')::jsonb||'{"export":true}')::text,true);
select ok(current_setting('f7.export')::jsonb->>'exportId' is not null,'exportação tem correlação com auditoria');
select throws_ok($$select public.finance_f6(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'report',current_setting('f7.filters')::jsonb||'{"report":"providers","dateBy":"competence"}')$$,'22023',null,'não inventa competência para prova externa');
select throws_ok($$select public.finance_f6('bf770000-0000-4000-8000-000000000099'::uuid,array[current_setting('f7.unit')::uuid],'report',current_setting('f7.filters')::jsonb||'{"export":true}')$$,'42501',null,'outro ministério não pode emitir exportação');
select lives_ok($$select public.finance_f6(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'budget',jsonb_build_object('id','ab770000-0000-4000-8000-000000000010','month',date_trunc('month',current_date)::date,'category','df770000-0000-4000-8000-000000000002','amountCents','10000','version',0,'reason','Planejamento fictício de homologação'))$$,'orçamento inicial auditado');
select is(public.finance_f6(current_setting('f7.org')::uuid,array[current_setting('f7.unit')::uuid],'report',current_setting('f7.filters')::jsonb)->'budgets'->0->>'unitName','Sede Revisão','orçamento sem movimento possui nome da igreja');
reset role;
select is((select count(*)::integer from public.audit_logs where organization_id=current_setting('f7.org')::uuid and action='finance.report_export_prepared'),2,'somente exportações autorizadas deixam registro');
select ok(not exists(select 1 from public.audit_logs where organization_id=current_setting('f7.org')::uuid and action='finance.report_export_prepared' and (metadata ? 'person' or metadata ? 'rowsData' or metadata ? 'credential')),'auditoria não copia contribuições ou credenciais');
select ok(not has_function_privilege('authenticated','public.finance_receiver_manual_key(uuid,uuid,uuid,jsonb)','execute'),'navegador não pode se passar pelo servidor ao salvar token');
select ok(not has_function_privilege('anon','public.finance_f6(uuid,uuid[],text,jsonb)','execute'),'visitante não consulta relatório');
select ok(not has_table_privilege('authenticated','private.finance_receiver_secrets','select'),'token protegido não é legível diretamente pelo cliente');
select is((select count(*)::integer from private.finance_entries where organization_id=current_setting('f7.org')::uuid),2,'exportar não cria lançamentos');
select * from finish();
rollback;
