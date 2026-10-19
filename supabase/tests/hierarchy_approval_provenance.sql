-- Isolated pgTAP fixture. No production identities, network calls or retained data.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
 select ('ae000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','hierarchy-provenance-'||i||'@example.test','',now(),now(),now() from generate_series(1,8)i;
insert into public.organizations(id,name,slug,status)
 select ('be000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Hierarquia sintética '||i,'hierarchy-provenance-'||i,'active' from generate_series(1,6)i;
insert into public.organization_memberships(id,organization_id,user_id,role,status) values
 ('ce000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000001','owner','active'),
 ('ce000000-0000-4000-8000-000000000003','be000000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000003','admin','active'),
 ('ce000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000004','owner','active'),
 ('ce000000-0000-4000-8000-000000000008','be000000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000008','viewer','active');
insert into public.organization_memberships(organization_id,user_id,role,status)
 select ('be000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'ae000000-0000-4000-8000-000000000002','owner','active' from generate_series(2,5)i;
insert into public.organization_memberships(organization_id,user_id,role,status)
 values('be000000-0000-4000-8000-000000000006','ae000000-0000-4000-8000-000000000007','owner','active');
insert into public.platform_operators(user_id,role,full_name,email) values
 ('ae000000-0000-4000-8000-000000000005','owner','Operador sintético','hierarchy-provenance-5@example.test'),
 ('ae000000-0000-4000-8000-000000000006','read_only','Leitor sintético','hierarchy-provenance-6@example.test');
insert into public.saas_hierarchy_requests(id,parent_church_id,child_church_id,billing_mode,parent_approved_at,created_at) values
 ('de000000-0000-4000-8000-000000000003','be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000003','individual',1,1),
 ('de000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000004','individual',null,1);
select ok(not has_table_privilege('authenticated','public.saas_hierarchy_requests','INSERT'),'nem operador autenticado forja solicitação diretamente');
select ok(not has_table_privilege('authenticated','public.saas_hierarchy_requests','UPDATE'),'nem operador reescreve aprovadores, destinatários ou cobrança diretamente');
select ok(not has_table_privilege('authenticated','public.saas_hierarchy_requests','DELETE'),'histórico de solicitação não é removido por clientes');
select ok(not has_table_privilege('authenticated','public.saas_organization_links','INSERT,UPDATE,DELETE'),'vínculo não contorna aceite duplo por escrita direta');
select ok(not has_table_privilege('authenticated','public.saas_billing_responsibilities','INSERT,UPDATE,DELETE'),'pagador exige operação validada');
select ok(not has_table_privilege('authenticated','public.organization_hierarchy_events','INSERT,UPDATE,DELETE'),'auditoria de hierarquia não aceita reescrita por clientes');
select ok(not has_table_privilege('service_role','public.organization_hierarchy_events','UPDATE,DELETE'),'histórico protegido também da integração comum');
select ok(not has_function_privilege('anon','public.change_platform_hierarchy(text,jsonb)','EXECUTE'),'visitante não inicia alteração');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000005","role":"authenticated","aal":"aal2"}',true);
select throws_ok($$insert into public.saas_hierarchy_requests(parent_church_id,child_church_id,billing_mode,created_at,status) values('be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000005','centralized',1,'approved')$$,'42501',null,'operador não fabrica pedido já aprovado');
select throws_ok($$update public.saas_hierarchy_requests set billing_mode='centralized' where id='de000000-0000-4000-8000-000000000003'$$,'42501',null,'operador não troca termos após aceite');
select throws_ok($$select public.change_platform_hierarchy('link','{"parentChurchId":"be000000-0000-4000-8000-000000000001","childChurchId":"be000000-0000-4000-8000-000000000002"}')$$,'42501','use_hierarchy_request','RPC não liga igrejas sem dois aceites');
select is(public.change_platform_hierarchy('request','{"parentChurchId":"be000000-0000-4000-8000-000000000001","childChurchId":"be000000-0000-4000-8000-000000000002","billingMode":"centralized","status":"approved","requested_by":"ae000000-0000-4000-8000-000000000001","parent_approved_by":"ae000000-0000-4000-8000-000000000001"}')->>'status','pending','somente termos permitidos são considerados; não nasce aceito');
select ok((select requested_by='ae000000-0000-4000-8000-000000000005'::uuid and parent_approved_by is null and parent_approved_at is null from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'),'autoria vem do operador verificado, não do payload');
select throws_ok($$select public.change_platform_hierarchy('request','{"parentChurchId":"be000000-0000-4000-8000-000000000001","childChurchId":"be000000-0000-4000-8000-000000000002"}')$$,'23505','hierarchy_pending_request','pedido pendente duplicado é recusado');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is((select public.approve_organization_hierarchy(id,'be000000-0000-4000-8000-000000000001','approve')->>'status' from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'),'pending','primeiro aceite ainda espera outra parte');
reset role;
select ok((select parent_approved_by='ae000000-0000-4000-8000-000000000003'::uuid and parent_approved_membership_id='ce000000-0000-4000-8000-000000000003'::uuid from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'),'conta e participação originais são registradas');
update public.organization_memberships set status='suspended' where id='ce000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy(id,'be000000-0000-4000-8000-000000000002','approve') from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'$$,'42501','hierarchy_previous_approval_unavailable','primeiro aprovador suspenso não é aproveitado no aceite final');
reset role;
select is((select count(*) from public.saas_organization_links where child_church_id='be000000-0000-4000-8000-000000000002'),0::bigint,'falha não liga igrejas');
select is((select count(*) from public.saas_billing_responsibilities where church_id='be000000-0000-4000-8000-000000000002'),0::bigint,'falha não troca pagador');
update public.organization_memberships set status='active',role='viewer' where id='ce000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select public.approve_organization_hierarchy(id,'be000000-0000-4000-8000-000000000002','approve') from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'$$,'42501','hierarchy_previous_approval_unavailable','primeiro aprovador rebaixado também é recusado');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select ok((select (item->>'parent_approval_requires_renewal')::boolean from jsonb_array_elements(public.organization_hierarchy_requests('be000000-0000-4000-8000-000000000001')) item where item->>'child_church_id'='be000000-0000-4000-8000-000000000002'),'tela informa necessidade de renovação');
select is((select public.approve_organization_hierarchy(id,'be000000-0000-4000-8000-000000000001','approve')->>'status' from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'),'pending','gestor atual pode renovar o aceite da sua própria parte');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((select public.approve_organization_hierarchy(id,'be000000-0000-4000-8000-000000000002','approve')->>'status' from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'),'approved','dois aceites atribuídos a gestores atuais ativam vínculo');
reset role;
select ok(exists(select 1 from public.saas_billing_responsibilities where church_id='be000000-0000-4000-8000-000000000002' and payer_church_id='be000000-0000-4000-8000-000000000001' and billing_mode='centralized'),'pagador final respeita exatamente termos aprovados');
select is((select count(*) from public.organization_hierarchy_events where child_organization_id='be000000-0000-4000-8000-000000000002' and action='activated'),1::bigint,'ativação tem histórico único');
set local role authenticated;
select is((select public.approve_organization_hierarchy(id,'be000000-0000-4000-8000-000000000002','approve')->>'status' from public.saas_hierarchy_requests where child_church_id='be000000-0000-4000-8000-000000000002'),'approved','repetição final é idempotente');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000005","role":"authenticated","aal":"aal2"}',true);
select lives_ok($$select public.change_platform_hierarchy('billing','{"childChurchId":"be000000-0000-4000-8000-000000000002","billingMode":"individual","parentChurchId":"be000000-0000-4000-8000-000000000006"}')$$,'Central mantém alteração legítima de pagador e ignora sede forjada');
select ok(exists(select 1 from public.saas_billing_responsibilities where church_id='be000000-0000-4000-8000-000000000002' and payer_church_id=church_id and billing_mode='individual'),'pagador individual é a própria filha');
select lives_ok($$select public.change_platform_hierarchy('billing','{"childChurchId":"be000000-0000-4000-8000-000000000002","billingMode":"centralized","payerChurchId":"be000000-0000-4000-8000-000000000006"}')$$,'Central preserva troca centralizada dentro do vínculo real');
select ok(exists(select 1 from public.saas_billing_responsibilities where church_id='be000000-0000-4000-8000-000000000002' and payer_church_id='be000000-0000-4000-8000-000000000001'),'payload não injeta terceiro pagador');
select lives_ok($$select public.change_platform_hierarchy('unlink','{"childChurchId":"be000000-0000-4000-8000-000000000002"}')$$,'Central mantém desvinculação autorizada');
select ok(exists(select 1 from public.saas_billing_responsibilities where church_id='be000000-0000-4000-8000-000000000002' and payer_church_id=church_id and billing_mode='individual'),'desvinculação retorna a cobrança individual');
select throws_ok($$select public.change_platform_hierarchy('unlink','{"childChurchId":"be000000-0000-4000-8000-000000000002"}')$$,'P0002','link_not_found','desvinculação inexistente não informa sucesso');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000006","role":"authenticated","aal":"aal2"}',true);
select throws_ok($$select public.change_platform_hierarchy('request','{"parentChurchId":"be000000-0000-4000-8000-000000000001","childChurchId":"be000000-0000-4000-8000-000000000005"}')$$,'42501','platform_manager_required','operador leitor não cria pedido');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000005","role":"authenticated","aal":"aal1"}',true);
select throws_ok($$select public.change_platform_hierarchy('request','{"parentChurchId":"be000000-0000-4000-8000-000000000001","childChurchId":"be000000-0000-4000-8000-000000000005"}')$$,'42501','platform_manager_required','operador sem segundo fator não cria pedido');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000003','be000000-0000-4000-8000-000000000003','approve')->>'status','pending','timestamp legado sem autor não ativa vínculo');
reset role;
select ok((select parent_approved_at=1 and parent_approved_by is null and child_approved_by='ae000000-0000-4000-8000-000000000002'::uuid from public.saas_hierarchy_requests where id='de000000-0000-4000-8000-000000000003'),'não apaga nem inventa autoria para timestamp legado');
select is((select count(*) from public.saas_organization_links where child_church_id='be000000-0000-4000-8000-000000000003'),0::bigint,'consentimento legado incompleto não é aproveitado');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000003','be000000-0000-4000-8000-000000000001','approve')->>'status','approved','renovação explícita do lado legado conclui após aceite da outra parte');
reset role;
update public.organization_memberships set role='admin' where id='ce000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is(public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000001','approve')->>'status','pending','participação original pode aprovar outro pedido');
reset role;
update auth.users set banned_until=now()+interval '1 day' where id='ae000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000004','approve')$$,'42501','hierarchy_previous_approval_unavailable','conta do primeiro aprovador banida não mantém consentimento vigente');
reset role;
update auth.users set banned_until=null where id='ae000000-0000-4000-8000-000000000003';
delete from public.organization_memberships where id='ce000000-0000-4000-8000-000000000003';
insert into public.organization_memberships(id,organization_id,user_id,role,status) values('ce000000-0000-4000-8000-000000000099','be000000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000003','admin','active');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000004','approve')$$,'42501','hierarchy_previous_approval_unavailable','recriar participação da mesma conta não ressuscita aceite');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is(public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000001','approve')->>'status','pending','nova participação pode manifestar novo aceite explícito');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(public.approve_organization_hierarchy('de000000-0000-4000-8000-000000000004','be000000-0000-4000-8000-000000000004','approve')->>'status','approved','vínculo conclui apenas depois da nova manifestação');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(public.organization_hierarchy_overview('be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000003')->'church'->>'id','be000000-0000-4000-8000-000000000003','gestor da sede vê metadados de vínculo ativo');
select ok(not (public.organization_hierarchy_overview('be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000003') ?| array['people','finance','kids','events','cells','dashboard']),'resumo não concede dados operacionais cruzados sem permissão específica');
select throws_ok($$select public.organization_hierarchy_overview('be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000002')$$,'42501','hierarchy_link_unavailable','metadados de vínculo encerrado não permanecem acessíveis');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000007","role":"authenticated"}',true);
select throws_ok($$select public.organization_hierarchy_overview('be000000-0000-4000-8000-000000000001','be000000-0000-4000-8000-000000000003')$$,'42501','organization_access_denied','terceiro ministério não consulta metadados do vínculo');
select is((select count(*) from public.organization_hierarchy_events),0::bigint,'terceiro ministério não lê históricos de outros');
select set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000008","role":"authenticated"}',true);
select is((select count(*) from public.organization_hierarchy_events),0::bigint,'leitor comum do ministério não lê auditoria gerencial');
reset role;
select * from finish();
rollback;
