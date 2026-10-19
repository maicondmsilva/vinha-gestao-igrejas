-- Synthetic identities in an isolated DB only. All fixture changes roll back.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select ('ad000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','hierarchy-state-'||i||'@example.test','',now(),now(),now() from generate_series(1,7)i;
insert into public.organizations(id,name,slug,status) values
 ('bd000000-0000-4000-8000-000000000001','Vínculo A','hierarchy-state-a','active'),
 ('bd000000-0000-4000-8000-000000000002','Vínculo B','hierarchy-state-b','active'),
 ('bd000000-0000-4000-8000-000000000003','Vínculo C','hierarchy-state-c','trial');
insert into public.organization_memberships(organization_id,user_id,role,status) values
 ('bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000001','owner','active'),
 ('bd000000-0000-4000-8000-000000000002','ad000000-0000-4000-8000-000000000002','owner','active'),
 ('bd000000-0000-4000-8000-000000000003','ad000000-0000-4000-8000-000000000003','owner','active'),
 ('bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000004','viewer','active'),
 ('bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000005','admin','suspended'),
 ('bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000006','pastor','active'),
 ('bd000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000007','admin','active');
insert into public.saas_hierarchy_requests(id,parent_church_id,child_church_id,billing_mode,created_at) values
 ('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','centralized',1),
 ('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000003','individual',1);
select ok(not has_function_privilege('anon','public.approve_organization_hierarchy(uuid,uuid,text)','EXECUTE'),'visitante não executa aprovação');
select ok(has_function_privilege('authenticated','public.approve_organization_hierarchy(uuid,uuid,text)','EXECUTE'),'RPC mantém entrada autenticada autorizada');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001',null)$$,'22023','invalid_decision','decisão nula não equivale a aprovação');
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','')$$,'22023','invalid_decision','decisão vazia não equivale a aprovação');
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','APPROVE')$$,'22023','invalid_decision','decisão desconhecida é recusada');
select throws_ok($$select public.approve_organization_hierarchy(null,'bd000000-0000-4000-8000-000000000001','approve')$$,'22023','invalid_request','solicitação ausente não é aceita');
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001',null,'approve')$$,'42501','organization_access_denied','ministério ausente não contorna autorização');
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000099','bd000000-0000-4000-8000-000000000001','approve')$$,'42501','request_not_found','solicitação inexistente é recusada');
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','approve')->>'status'),'pending','primeiro aceite aguarda a outra igreja');
reset role;
select is((select count(*) from public.saas_organization_links where child_church_id='bd000000-0000-4000-8000-000000000002'),0::bigint,'primeiro aceite não cria vínculo');
select is((select count(*) from public.saas_billing_responsibilities where church_id='bd000000-0000-4000-8000-000000000002'),0::bigint,'primeiro aceite não troca pagador');
update public.organizations set status='suspended' where id='bd000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','approve')$$,'42501','hierarchy_organization_unavailable','sede suspensa impede finalizar');
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','reject')$$,'42501','hierarchy_organization_unavailable','estado indisponível impede também mudar a decisão');
reset role;
select ok((select parent_approved_at is not null and child_approved_at is null and status='pending' from public.saas_hierarchy_requests where id='dd000000-0000-4000-8000-000000000001'),'recusa preserva solicitação sem gravar segundo aceite');
select is((select count(*) from public.saas_organization_links where child_church_id='bd000000-0000-4000-8000-000000000002'),0::bigint,'recusa não vincula igrejas');
select is((select count(*) from public.saas_billing_responsibilities where church_id='bd000000-0000-4000-8000-000000000002'),0::bigint,'recusa não altera pagador');
update public.organizations set status='active' where id='bd000000-0000-4000-8000-000000000001';
update public.organizations set status='cancelled' where id='bd000000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','approve')$$,'42501','hierarchy_organization_unavailable','filha cancelada também impede finalizar');
reset role;
update public.organizations set status='trial' where id='bd000000-0000-4000-8000-000000000002';
set local role authenticated;
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','approve')->>'status'),'approved','ministérios ativo e em demonstração mantêm aceite duplo');
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','approve')->>'status'),'approved','repetição de aceite final é idempotente');
reset role;
select is((select count(*) from public.saas_organization_links where child_church_id='bd000000-0000-4000-8000-000000000002' and status='active'),1::bigint,'somente um vínculo é criado');
select ok(exists(select 1 from public.saas_billing_responsibilities where church_id='bd000000-0000-4000-8000-000000000002' and payer_church_id='bd000000-0000-4000-8000-000000000001' and billing_mode='centralized'),'pagador centralizado continua correto');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','approve')$$,'42501','organization_access_denied','leitor não aprova');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','approve')$$,'42501','organization_access_denied','participação suspensa não aprova');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000003','approve')$$,'42501','request_not_found','gestor de outro ministério não responde por participante');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000007","role":"authenticated"}',true);
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','approve')->>'status'),'pending','administrador mantém papel atual de resposta');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','reject')->>'status'),'rejected','pastor mantém rejeição conforme matriz existente');
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','approve')->>'status'),'rejected','rejeição final não é reaberta por repetição');
reset role;
select is((select count(*) from public.saas_billing_responsibilities where church_id='bd000000-0000-4000-8000-000000000003'),0::bigint,'rejeição não altera cobrança');
insert into public.saas_hierarchy_requests(id,parent_church_id,child_church_id,billing_mode,created_at) values
 ('dd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000002','bd000000-0000-4000-8000-000000000001','individual',1),
 ('dd000000-0000-4000-8000-000000000004','bd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000002','individual',1),
 ('dd000000-0000-4000-8000-000000000005','bd000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000003','individual',1);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000002','approve')->>'status'),'pending','primeiro aceite de ciclo ainda aguarda segunda parte');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000001','approve')$$,'P0001','hierarchy_cycle','proteção anterior contra ciclo é preservada');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000004','bd000000-0000-4000-8000-000000000003','approve')->>'status'),'pending','pedido de filha já vinculada não ganha vínculo no primeiro aceite');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000004','bd000000-0000-4000-8000-000000000002','approve')$$,'P0001','child_already_linked','segunda sede de uma filha é recusada');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000007","role":"authenticated"}',true);
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000005','bd000000-0000-4000-8000-000000000001','approve')->>'status'),'pending','administrador pode iniciar aceite individual');
select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is((public.approve_organization_hierarchy('dd000000-0000-4000-8000-000000000005','bd000000-0000-4000-8000-000000000003','approve')->>'status'),'approved','aceite individual continua funcional');
reset role;
select ok(exists(select 1 from public.saas_billing_responsibilities where church_id='bd000000-0000-4000-8000-000000000003' and payer_church_id=church_id and billing_mode='individual'),'pagador individual permanece a própria igreja');
select * from finish();
rollback;
