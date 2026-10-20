begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a1100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','integrated-'||n||'@example.test',now(),now(),now() from generate_series(1,3)n;
insert into public.organizations(id,name,slug,status) values('b1100000-0000-4000-8000-000000000001','Células integradas fictícias','cells-integrated-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values('c1100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','Sede fictícia','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
select ('e1100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b1100000-0000-4000-8000-000000000001',('a1100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,case when n=1 then 'owner'::public.membership_role else 'viewer'::public.membership_role end,'active','c1100000-0000-4000-8000-000000000001' from generate_series(1,3)n;
insert into public.membership_unit_access(membership_id,unit_id,access_level) select id,'c1100000-0000-4000-8000-000000000001','read' from public.organization_memberships where organization_id='b1100000-0000-4000-8000-000000000001' and role='viewer';
insert into public.people(id,organization_id,unit_id,full_name,status,auth_user_id)
select ('d1100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','Pessoa integrada '||n,'active',case when n<3 then ('a1100000-0000-4000-8000-'||lpad((n+1)::text,12,'0'))::uuid else null end from generate_series(1,3)n;
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by)
select ('f1100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','Grupo integrado '||n,1,'19:30','online','a1100000-0000-4000-8000-000000000001' from generate_series(1,2)n;
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by)
select ('fa110000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','Rede integrada '||n,'active','a1100000-0000-4000-8000-000000000001' from generate_series(1,3)n;
insert into public.church_cell_network_parents(network_id,organization_id,unit_id,parent_id,updated_by) values('fa110000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','fa110000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000001');
insert into public.church_cell_network_links(cell_id,organization_id,unit_id,network_id,updated_by)
select ('f1100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001',('fa110000-0000-4000-8000-'||lpad((n+1)::text,12,'0'))::uuid,'a1100000-0000-4000-8000-000000000001' from generate_series(1,2)n;

insert into private.cell_study_materials(id,organization_id,unit_id,title,body,status,created_by) values('fd110000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','Arquivo fictício','Estudo','draft','a1100000-0000-4000-8000-000000000001');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values('c1100000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000001','Campus fictício','campus','campus');
create function pg_temp.file_allowed(w boolean default false) returns boolean language sql as $$select private.cell_study_file_allowed('b1100000-0000-4000-8000-000000000001/c1100000-0000-4000-8000-000000000001/fd110000-0000-4000-8000-000000000001/ff110000-0000-4000-8000-000000000001.pdf',w)$$;
select is((select public from storage.buckets where id='cell-studies-private'),false,'bucket privado');
select is((select file_size_limit::integer from storage.buckets where id='cell-studies-private'),4194304,'limite 4MB');
select ok(not has_function_privilege('anon','public.cell_consolidated(uuid,uuid[],date,date)','execute'),'consolidação não anônima');
select ok(not has_function_privilege('authenticated','private.run_cell_reminders()','execute'),'agendador não executável por cliente');
select ok(not has_function_privilege('authenticated','public.cell_delivery_claim(text[])','execute'),'fila somente serviço');
select ok(not has_table_privilege('authenticated','private.cell_external_deliveries','select,insert,update,delete,truncate'),'fila privada');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select ok(pg_temp.file_allowed(),'gestor lê rascunho');
select ok(pg_temp.file_allowed(true),'gestor pode anexar');
select ok(not private.cell_study_file_allowed('../x',false),'sem traversal');
select ok(not private.cell_study_file_allowed('b1100000-0000-4000-8000-000000000001/c1100000-0000-4000-8000-000000000002/fd110000-0000-4000-8000-000000000001/ff110000-0000-4000-8000-000000000001.pdf',false),'unidade divergente recusada');
select is(public.cell_consolidated('b1100000-0000-4000-8000-000000000001',array['c1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000002']::uuid[],current_date-30,current_date)->'summary'->>'groups','2','consolida duas unidades sem duplicar grupos');
select is(jsonb_array_length(public.cell_consolidated('b1100000-0000-4000-8000-000000000001',array['c1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000002']::uuid[],current_date-30,current_date)->'units'),2,'duas linhas de unidade');
select throws_ok($$select public.cell_consolidated('b1100000-0000-4000-8000-000000000001',array['c1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001']::uuid[],current_date-30,current_date)$$,'22023','invalid_cell_scope','sem duplicatas');
select throws_ok($$select public.cell_consolidated('b1100000-0000-4000-8000-000000000001',array['c1100000-0000-4000-8000-000000000099']::uuid[],current_date-30,current_date)$$,'42501','cell_access_denied','sem outra unidade');
select is(public.cell_delivery_preferences('b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001')->>'emailEnabled','false','opt-in inicialmente desligado');
select is(public.cell_delivery_preferences('b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001',true,false,0)->>'version','1','opt-in próprio auditado');
select throws_ok($$select public.cell_delivery_preferences('b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001',true,false,0)$$,'40001','cell_version_conflict','versão obsoleta recusada');
select throws_ok($$select public.cell_delivery_preferences('b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001',true,true,1)$$,'22023','verified_phone_required','não envia WhatsApp sem telefone confirmado');
select is(public.cell_delivery_preferences('b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001',true,false,1)->>'version','2','atualização de preferências com versão atual');
select set_config('request.jwt.claims','{"sub":"a1100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select ok(not pg_temp.file_allowed(),'viewer sem concessão não lê');
select ok(not pg_temp.file_allowed(true),'viewer não envia');
select throws_ok($$select public.cell_consolidated('b1100000-0000-4000-8000-000000000001',array['c1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000002']::uuid[],current_date-30,current_date)$$,'42501','cell_access_denied','consulta inteira recusada se faltar acesso');
reset role;
insert into private.cell_supervisor_grants(id,organization_id,unit_id,network_id,person_id,user_id,capability,status,created_by) values('fe110000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','fa110000-0000-4000-8000-000000000001','d1100000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000002','read','active','a1100000-0000-4000-8000-000000000001');
update private.cell_study_materials set status='published' where id='fd110000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select ok(pg_temp.file_allowed(),'supervisor lê publicado geral');
select ok(not pg_temp.file_allowed(true),'supervisor não anexa');
reset role;
update private.cell_supervisor_grants set status='revoked';
set local role authenticated;
select ok(not pg_temp.file_allowed(),'revogação bloqueia download imediatamente');
reset role;
insert into public.church_cell_meetings(id,organization_id,unit_id,cell_id,topic,meeting_date,meeting_time,status,created_by) values('fc110000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','f1100000-0000-4000-8000-000000000001','Encontro fictício',current_date-1,'19:30','scheduled','a1100000-0000-4000-8000-000000000001');
insert into private.cell_report_notifications(id,organization_id,unit_id,cell_id,meeting_id,recipient_id,created_by,created_at) values('ff110000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-000000000001','f1100000-0000-4000-8000-000000000001','fc110000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 second');
create temp table claimed(d jsonb);grant all on claimed to service_role;
set local role service_role;
insert into claimed select public.cell_delivery_claim(array['email']);
select is(jsonb_array_length((select d from claimed)),1,'uma mensagem consentida');
select is(jsonb_array_length(public.cell_delivery_claim(array['email'])),0,'claim concorrente não duplica');
select is(public.cell_delivery_finish(((select d from claimed)->0->>'id')::uuid,'00000000-0000-4000-8000-000000000099','test-provider'),false,'token errado não finaliza');
select is(public.cell_delivery_finish(((select d from claimed)->0->>'id')::uuid,((select d from claimed)->0->>'token')::uuid,'test-provider'),true,'aceitação do provedor registrada');
select is(public.cell_delivery_finish(((select d from claimed)->0->>'id')::uuid,((select d from claimed)->0->>'token')::uuid,'test-provider'),false,'resultado não reescrito');
reset role;
select is((select status from private.cell_external_deliveries limit 1),'submitted','submitted não afirma entrega final');
select lives_ok($$select private.run_cell_reminders()$$,'scanner independente executa');
select is((select count(*)::integer from private.cell_reminder_runs),1,'execução registrada sem dados pessoais');
select is((select active from cron.job where jobname='vinha-cell-report-reminders'),false,'migração não ativa antes da homologação');
select * from finish();rollback;
