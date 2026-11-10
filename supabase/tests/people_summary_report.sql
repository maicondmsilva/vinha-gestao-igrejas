begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values('ab000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','report-owner@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('bb000000-0000-4000-8000-000000000001','Relatório A','report-a','active'),('bb000000-0000-4000-8000-000000000002','Relatório B','report-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('cb000000-0000-4000-8000-000000000001','bb000000-0000-4000-8000-000000000001','Sede relatório','sede','headquarters'),
('cb000000-0000-4000-8000-000000000002','bb000000-0000-4000-8000-000000000001','Campus relatório','campus','campus'),
('cb000000-0000-4000-8000-000000000003','bb000000-0000-4000-8000-000000000002','Sede B','sede-b','headquarters');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values('bb000000-0000-4000-8000-000000000001','ab000000-0000-4000-8000-000000000001','owner','active','cb000000-0000-4000-8000-000000000001');
insert into public.people(organization_id,unit_id,full_name,journey_status) values
('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000001','Pessoa fictícia A','Membro'),
('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000001','Pessoa fictícia B','Visitante'),
('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000002','Pessoa outro campus','Membro');
select ok(not has_function_privilege('anon','public.people_summary_report(uuid,uuid)','EXECUTE'),'visitante não executa relatório');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ab000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(public.people_summary_report('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000001')->'counts'->>'total','2','contagem não inclui outro campus');
select is(public.people_summary_report('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000001')->'counts'->>'members','1','situação correta');
select ok(not (public.people_summary_report('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000001')::text like '%Pessoa fictícia%'),'nenhum nome retornado');
select throws_ok($$select public.people_summary_report('bb000000-0000-4000-8000-000000000002','cb000000-0000-4000-8000-000000000003')$$,'42501','report_access_denied','outro ministério recusado');
select throws_ok($$select public.people_summary_report('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000003')$$,'42501','report_access_denied','unidade divergente recusada');
select throws_ok($$select public.people_summary_report('bb000000-0000-4000-8000-000000000001',null)$$,'42501','report_access_denied','unidade ausente recusada');
reset role;
update public.organizations set status='suspended' where id='bb000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.people_summary_report('bb000000-0000-4000-8000-000000000001','cb000000-0000-4000-8000-000000000001')$$,'42501','report_access_denied','ministério suspenso recusado');
reset role;
select * from finish();
rollback;
