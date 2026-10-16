begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('a0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin-a@example.test', '', now(), now(), now()),
  ('a0000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'leader-a@example.test', '', now(), now(), now()),
  ('a0000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member-b@example.test', '', now(), now(), now());

insert into public.organizations (id, name, slug, status)
values
  ('b0000000-0000-4000-8000-000000000001', 'Organização Teste A', 'organizacao-teste-a', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'Organização Teste B', 'organizacao-teste-b', 'active');

insert into public.organization_units (id, organization_id, name, slug, unit_type)
values
  ('c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'Sede A', 'sede-a', 'headquarters'),
  ('c0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'Campus A', 'campus-a', 'campus'),
  ('c0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 'Sede B', 'sede-b', 'headquarters');

insert into public.organization_memberships (id, organization_id, user_id, default_unit_id, role, status)
values
  ('d0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('d0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000002', 'leader', 'active'),
  ('d0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000003', 'member', 'active');

insert into public.membership_unit_access (membership_id, unit_id, access_level)
values ('d0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000002', 'read');

insert into public.people (id, organization_id, unit_id, auth_user_id, full_name, email)
values
  ('e0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', null, 'Pessoa Sede A', 'sede-a@example.test'),
  ('e0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000002', null, 'Pessoa Campus A', 'campus-a@example.test'),
  ('e0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Pessoa Sede B', 'sede-b@example.test');

insert into public.person_addresses (organization_id,person_id,street)
values ('b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','Endereço privado');

insert into public.pastoral_notes (organization_id,person_id,author_user_id,content)
values ('b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Nota privada');


update public.organization_memberships set role='owner' where id='d0000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select throws_ok($$update public.people set auth_user_id='a0000000-0000-4000-8000-000000000002' where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'nem proprietário vincula outra conta por escrita direta');
select throws_ok($$update public.people set app_role='admin' where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'papel do aplicativo não é promovido diretamente');
select throws_ok($$update public.people set organization_id='b0000000-0000-4000-8000-000000000002',unit_id=null where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'organização da pessoa não é reatribuída diretamente');
select throws_ok($$update public.people set id='e0000000-0000-4000-8000-000000000099' where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'identificador não pode ser reescrito');
select throws_ok($$update public.people set created_at='2099-01-01' where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'data original não pode ser reescrita');
select throws_ok($$insert into public.people(organization_id,unit_id,full_name,auth_user_id) values('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','Conta falsa','a0000000-0000-4000-8000-000000000002')$$,'42501',null,'inserção direta não atribui identidade autenticada');
select throws_ok($$insert into public.people(organization_id,unit_id,full_name,app_role) values('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','Papel falso','admin')$$,'42501',null,'inserção direta não atribui papel privilegiado');
with updated as (update public.people set phone='11999990000' where id='e0000000-0000-4000-8000-000000000002' returning id) select is((select count(*) from updated),1::bigint,'edição comum continua permitida');

select lives_ok($$insert into public.person_consents(id,organization_id,person_id,consent_type,granted,source,acceptance_snapshot,created_at,granted_at,accepted_by_person_id)
values('f0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','privacy',true,'app','{"verified_member_acceptance":true,"recorded_by_user_id":"outro"}','2099-01-01','2099-01-01','e0000000-0000-4000-8000-000000000003')$$,'preferência administrativa pode ser acrescentada');
select is((select source from public.person_consents where id='f0000000-0000-4000-8000-000000000001'),'admin','origem não é falsificada como aceite no aplicativo');
select is((select acceptance_snapshot->>'verified_member_acceptance' from public.person_consents where id='f0000000-0000-4000-8000-000000000001'),'false','administrador não fabrica aceite verificado');
select is((select acceptance_snapshot->>'recorded_by_user_id' from public.person_consents where id='f0000000-0000-4000-8000-000000000001'),'a0000000-0000-4000-8000-000000000001','ator é obtido da identidade autenticada');
select ok((select accepted_by_person_id is null and term_id is null and created_at<now()+interval '1 minute' and granted_at=created_at from public.person_consents where id='f0000000-0000-4000-8000-000000000001'),'não inventa titular, termo ou horário futuro');
select throws_ok($$update public.person_consents set granted=false where id='f0000000-0000-4000-8000-000000000001'$$,'42501',null,'histórico não pode ser sobrescrito');
select throws_ok($$delete from public.person_consents where id='f0000000-0000-4000-8000-000000000001'$$,'42501',null,'histórico não pode ser excluído diretamente');
select throws_ok($$insert into public.person_consents(organization_id,person_id,consent_type,granted) values('b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','minors',true)$$,'42501',null,'termo de menor exige fluxo específico, não checkbox administrativo');
select throws_ok($$update public.pastoral_notes set content='Reescrita' where person_id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'nota pastoral não pode ser reescrita');
select throws_ok($$delete from public.pastoral_notes where person_id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'nota pastoral não pode ser apagada diretamente');
select throws_ok($$delete from public.people where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'cadastro não pode apagar histórico por cascata');
select throws_ok($$insert into public.pastoral_notes(organization_id,person_id,author_user_id,content) values('b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000002','Falso autor')$$,'42501',null,'autor da nota não pode ser falsificado');
select lives_ok($$insert into public.pastoral_notes(id,organization_id,person_id,author_user_id,content,created_at) values('f0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Complemento','2099-01-01')$$,'proprietário acrescenta nota');
select ok((select created_at<now()+interval '1 minute' from public.pastoral_notes where id='f0000000-0000-4000-8000-000000000002'),'timestamp da nota é atribuído pelo banco');

select throws_ok($$insert into public.user_access_preferences(user_id,selected_organization_id) values('a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000002')$$,'42501',null,'preferência direta não seleciona outra organização');
select throws_ok($$insert into public.user_access_preferences(user_id,selected_organization_id,selected_unit_id) values('a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000003')$$,'42501',null,'preferência direta rejeita unidade de outra organização');
select lives_ok($$select public.set_access_context('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','dark')$$,'seletor autorizado continua funcionando');

reset role;
update public.organization_memberships set role='finance' where id='d0000000-0000-4000-8000-000000000002';
update public.membership_unit_access set access_level='manage' where membership_id='d0000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.people),0::bigint,'financeiro não lê diretório de membros por concessão genérica');
select is((select count(*) from public.person_addresses),0::bigint,'financeiro não lê endereços por concessão genérica');
select is((select count(*) from public.person_consents),0::bigint,'financeiro não lê preferências de terceiros');
with changed as (update public.people set phone='Indevido' where id='e0000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'concessão de unidade não transforma financeiro em gestor de membros');
select throws_ok($$insert into public.people(organization_id,unit_id,full_name) values('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','Indevido')$$,'42501',null,'financeiro não insere pessoas diretamente');
with changed as (update public.person_addresses set street='Indevido' where person_id='e0000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'financeiro não edita endereço diretamente');
select throws_ok($$insert into public.person_consents(organization_id,person_id,consent_type,granted) values('b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','privacy',true)$$,'42501',null,'financeiro não registra consentimento de terceiro');
select throws_ok($$insert into public.user_access_preferences(user_id,selected_organization_id,selected_unit_id) values('a0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001')$$,'42501',null,'concessão em campus não permite preferência na sede');

reset role;
update public.organization_memberships set role='viewer' where id='d0000000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.people),0::bigint,'viewer com concessão não lê dados pessoais');
reset role;
update public.organization_memberships set role='member' where id='d0000000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.people),0::bigint,'membro sem vínculo pessoal não lê terceiros');

select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$insert into public.person_consents(id,organization_id,person_id,consent_type,granted,source) values('f0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000003','messages',false,'app')$$,'membro mantém caminho de preferência própria');
select is((select source from public.person_consents where id='f0000000-0000-4000-8000-000000000003'),'self','preferência própria não se apresenta como aceite verificado');

reset role;
update public.organizations set status='suspended' where id='b0000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.pastoral_notes),0::bigint,'suspensão do ministério bloqueia notas pastorais');
select throws_ok($$insert into public.pastoral_notes(organization_id,person_id,author_user_id,content) values('b0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Indevido')$$,'42501',null,'suspensão bloqueia nova nota');
select throws_ok($$update public.user_access_preferences set theme='light' where user_id='a0000000-0000-4000-8000-000000000001'$$,'42501',null,'preferência não confirma organização suspensa');
select lives_ok($$update public.user_access_preferences set selected_organization_id=null,selected_unit_id=null where user_id='a0000000-0000-4000-8000-000000000001'$$,'usuário pode limpar preferência revogada');

select ok(not has_table_privilege('authenticated','public.people','TRUNCATE'),'sem TRUNCATE que contornaria RLS');
select ok(not has_table_privilege('authenticated','public.person_consents','TRIGGER'),'cliente não cria trigger sobre histórico');
select ok(not has_function_privilege('authenticated','private.stamp_member_history()','EXECUTE'),'trigger interno não é RPC executável');
select * from finish();
rollback;

