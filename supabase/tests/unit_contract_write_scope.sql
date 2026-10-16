-- Synthetic data, isolated database only. Every change is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
 ('a6000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-contract@example.test','',now(),now(),now()),
 ('a6000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','leader-contract@example.test','',now(),now(),now());
insert into public.organizations(id,name,slug,status) values
 ('b6000000-0000-4000-8000-000000000001','Contrato A','contract-scope-a','active'),
 ('b6000000-0000-4000-8000-000000000002','Contrato B','contract-scope-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c6000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001','Sede liberada','sede','headquarters'),
 ('c6000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000001','Filha bloqueada','filha','campus'),
 ('c6000000-0000-4000-8000-000000000003','b6000000-0000-4000-8000-000000000001','Sem contrato','sem-contrato','campus'),
 ('c6000000-0000-4000-8000-000000000004','b6000000-0000-4000-8000-000000000002','Outra sede','outra','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d6000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001','a6000000-0000-4000-8000-000000000001','owner','active','c6000000-0000-4000-8000-000000000001'),
 ('d6000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000001','a6000000-0000-4000-8000-000000000002','leader','active','c6000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values
 ('d6000000-0000-4000-8000-000000000002','c6000000-0000-4000-8000-000000000001','manage');
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions) values
 ('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001','plan-essential','active','{"people":true}'),
 ('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','c6000000-0000-4000-8000-000000000001','plan-essential','active','{"people":false}');
insert into public.people(id,organization_id,unit_id,full_name) values
 ('e6000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001','Pessoa liberada'),
 ('e6000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','Pessoa bloqueada');
insert into public.person_addresses(organization_id,person_id,street) values
 ('b6000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000002','Original');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(public.unit_module_enabled('b6000000-0000-4000-8000-000000000001','people'),true,'unidade padrão liberada');
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','people'),false,'contrato da filha prevalece sobre a sede');
select throws_ok($$select public.save_person_record('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002',null,'{"name":"Bloqueado"}')$$,'42501',null,'RPC não usa sede liberada para criar na filha bloqueada');
select throws_ok($$insert into public.people(organization_id,unit_id,full_name) values('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','Bloqueado direto')$$,'42501',null,'inserção direta também respeita contrato');
select throws_ok($$update public.people set unit_id='c6000000-0000-4000-8000-000000000002' where id='e6000000-0000-4000-8000-000000000001'$$,'42501',null,'mudança para destino bloqueado é rejeitada');
with changed as(update public.people set unit_id='c6000000-0000-4000-8000-000000000001' where id='e6000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'origem bloqueada não escapa por transferência');
with changed as(update public.person_addresses set street='Indevido' where person_id='e6000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'endereço respeita bloqueio da unidade real');
select throws_ok($$insert into public.person_consents(organization_id,person_id,consent_type,granted) values('b6000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000002','privacy',true)$$,'42501',null,'consentimento administrativo não contorna contrato');
select lives_ok($$select public.save_person_record('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001',null,'{"name":"Permitido"}')$$,'unidade liberada continua gravando');
select is((select unit_id from public.people where id='e6000000-0000-4000-8000-000000000001'),'c6000000-0000-4000-8000-000000000001'::uuid,'transferência recusada preserva origem');
select is((select street from public.person_addresses where person_id='e6000000-0000-4000-8000-000000000002'),'Original','histórico existente preservado e leitura autorizada mantida');
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000003','people'),true,'sem contrato preserva compatibilidade de implantação');
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000004','people'),false,'unidade estrangeira não pertence ao ministério');
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001',null,'people'),false,'alvo ausente não libera gravação');
select is(public.unit_module_enabled('b6000000-0000-4000-8000-000000000001','modulo-inventado'),false,'módulo desconhecido não é habilitado');
select lives_ok($$select public.request_unit_modules('c6000000-0000-4000-8000-000000000002',array['people'],12,false)$$,'proprietário pode solicitar desbloqueio, sem concedê-lo');
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','people'),false,'pedido não ativa módulo');
reset role;
update public.saas_unit_contracts set module_decisions='{}' where unit_id='c6000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','people'),true,'herança do plano continua válida');
reset role;
update public.saas_unit_contracts set module_decisions='{"people":"true"}' where unit_id='c6000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','people'),false,'texto não é decisão booleana válida');
reset role;
update public.saas_unit_contracts set status='draft' where unit_id='c6000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','people'),true,'rascunho mantém regra legada, explicitamente documentada');
reset role;
update public.saas_unit_contracts set status='suspended',module_decisions='{"people":true}' where unit_id='c6000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000002','people'),false,'contrato suspenso prevalece sobre liberação explícita');
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(private.target_unit_module_enabled('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000003','people'),false,'sem contrato não contorna falta de acesso à unidade');
reset role;
delete from public.membership_unit_access where membership_id='d6000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.unit_module_enabled('b6000000-0000-4000-8000-000000000001','people'),false,'padrão sem concessão não libera acesso');
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.set_access_context('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001','light')$$,'preferência autorizada selecionada');
reset role;
update public.organization_units set status='suspended' where id='c6000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.unit_module_enabled('b6000000-0000-4000-8000-000000000001','people'),false,'preferência inativada não recai em outra unidade');
select throws_ok($$select public.request_unit_modules('c6000000-0000-4000-8000-000000000001',array['people'],12,false)$$,'42501',null,'unidade inativa não solicita mudança de contrato');
reset role;
update public.organization_units set status='active' where id='c6000000-0000-4000-8000-000000000001';
update public.organizations set status='suspended' where id='b6000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.unit_module_enabled('b6000000-0000-4000-8000-000000000001','people'),false,'ministério suspenso não recebe módulo');
select throws_ok($$select public.request_unit_modules('c6000000-0000-4000-8000-000000000001',array['people'],12,false)$$,'42501',null,'suspensão bloqueia solicitação de contrato');
select throws_ok($$select public.save_person_record('b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001',null,'{"name":"Suspenso"}')$$,'42501',null,'suspensão bloqueia cadastro atômico');
select ok(not has_function_privilege('anon','private.target_unit_module_enabled(uuid,uuid,text)','EXECUTE'),'consulta interna não está liberada ao anônimo');
select ok(not has_function_privilege('authenticated','private.guard_member_unit_contract()','EXECUTE'),'trigger não é chamada de aplicação');
select * from finish();
rollback;
