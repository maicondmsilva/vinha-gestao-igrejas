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
create function pg_temp.fail_atomic_audit() returns trigger language plpgsql as $$
begin if current_setting('vinha.fail_atomic_audit',true)='yes' then raise exception 'forced_audit_failure' using errcode='23514'; end if;return new;end;$$;
create trigger test_atomic_audit before insert on public.audit_logs for each row execute function pg_temp.fail_atomic_audit();
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select set_config('vinha.atomic_person',public.save_person_record('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001',null,
 '{"name":"Pessoa atômica","email":"atomic@example.test","phone":"11999999999","address":"Rua preservada","city":"Cidade inicial","emergencyName":"Contato completo","emergencyPhone":"11888888888","privacy":true,"imageConsent":false,"tags":"música, liderança","joined":"2026-10-15"}')::text,true)$$,'cadastro completo é gravado por uma chamada');
select is((select count(*) from public.person_addresses where person_id=current_setting('vinha.atomic_person')::uuid),1::bigint,'endereço criado');
select is((select count(*) from public.emergency_contacts where person_id=current_setting('vinha.atomic_person')::uuid),1::bigint,'contato criado');
select is((select count(*) from public.person_consents where person_id=current_setting('vinha.atomic_person')::uuid),2::bigint,'somente consentimentos informados são registrados');
select is((select acceptance_snapshot->>'verified_member_acceptance' from public.person_consents where person_id=current_setting('vinha.atomic_person')::uuid and consent_type='privacy'),'false','registro administrativo não simula aceite do membro');
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001',null,
 '{"name":"Não deve existir","email":"rollback@example.test","address":"Endereço que deve reverter","emergencyName":"A","emergencyPhone":"1199","privacy":true}')$$,'23514',null,'falha no contato reverte criação inteira');
select is((select count(*) from public.people where email='rollback@example.test'),0::bigint,'nenhuma pessoa parcial permanece');
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,
 '{"name":"Nome que deve reverter","city":"Cidade que deve reverter","emergencyName":"A","privacy":false}')$$,'23514',null,'falha complementar reverte edição');
select is((select full_name from public.people where id=current_setting('vinha.atomic_person')::uuid),'Pessoa atômica','nome anterior preservado após falha');
select is((select city from public.person_addresses where person_id=current_setting('vinha.atomic_person')::uuid),'Cidade inicial','endereço anterior preservado após falha');
select lives_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"phone":"11777777777","city":"Nova cidade"}')$$,'edição parcial não exige reenviar nome');
select is((select street from public.person_addresses where person_id=current_setting('vinha.atomic_person')::uuid),'Rua preservada','campo de endereço omitido não é apagado');
select is((select full_name from public.people where id=current_setting('vinha.atomic_person')::uuid),'Pessoa atômica','nome omitido preservado');
select is((select cardinality(tags) from public.people where id=current_setting('vinha.atomic_person')::uuid),2,'tags omitidas preservadas');
select is((select count(*) from public.person_consents where person_id=current_setting('vinha.atomic_person')::uuid),2::bigint,'edição cadastral não recria consentimentos');
select lives_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"privacy":false}')$$,'revogação explícita gera novo registro');
select is((select count(*) from public.person_consents where person_id=current_setting('vinha.atomic_person')::uuid and consent_type='privacy'),2::bigint,'histórico de autorização e revogação preservado');
select lives_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"privacy":false}')$$,'repetir o mesmo estado não duplica registro');
select is((select count(*) from public.person_consents where person_id=current_setting('vinha.atomic_person')::uuid and consent_type='privacy'),2::bigint,'sem consentimento duplicado');
select lives_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"notes":"Registro pastoral preservado"}')$$,'pastor/proprietário adiciona nota');
select lives_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"notes":""}')$$,'nota vazia não apaga histórico');
select is((select count(*) from public.pastoral_notes where person_id=current_setting('vinha.atomic_person')::uuid),1::bigint,'histórico pastoral preservado');
select set_config('vinha.fail_atomic_audit','yes',true);
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"name":"Não auditar parcialmente","city":"Não persistir","privacy":true}')$$,'23514',null,'falha na auditoria reverte a operação');
select set_config('vinha.fail_atomic_audit','no',true);
select is((select full_name from public.people where id=current_setting('vinha.atomic_person')::uuid),'Pessoa atômica','falha na auditoria não deixa cadastro modificado');
select is((select city from public.person_addresses where person_id=current_setting('vinha.atomic_person')::uuid),'Nova cidade','falha na auditoria não deixa endereço modificado');
select is((select count(*) from public.person_consents where person_id=current_setting('vinha.atomic_person')::uuid and consent_type='privacy'),2::bigint,'falha na auditoria não deixa consentimento novo');
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,'e0000000-0000-4000-8000-000000000003','{"name":"Invasão"}')$$,'P0002',null,'pessoa de outra organização não é editada');
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"auth_user_id":"a0000000-0000-4000-8000-000000000001"}')$$,'22023',null,'campo sensível não pode ser injetado');
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,current_setting('vinha.atomic_person')::uuid,'{"privacy":"true"}')$$,'22023',null,'consentimento exige booleano');
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002',null,'{"name":"Líder sem escrita"}')$$,'42501',null,'concessão read não ganha escrita pelo RPC');
reset role;
update public.membership_unit_access set access_level='manage' where membership_id='d0000000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,'e0000000-0000-4000-8000-000000000002','{"name":"Nome indevido","notes":"Nota não permitida"}')$$,'42501',null,'líder não grava nota pastoral e edição reverte');
select is((select full_name from public.people where id='e0000000-0000-4000-8000-000000000002'),'Pessoa Campus A','nome não muda quando nota não é permitida');
select lives_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,'e0000000-0000-4000-8000-000000000002','{"phone":"11999990000"}')$$,'líder com manage edita a unidade autorizada');
reset role;
set local role anon;
select throws_ok($$select public.save_person_record('b0000000-0000-4000-8000-000000000001',null,null,'{"name":"Anônimo"}')$$,'42501',null,'visitante não executa gravação');
reset role;
select is((select prosecdef from pg_proc where oid='public.save_person_record(uuid,uuid,uuid,jsonb)'::regprocedure),false,'função não eleva privilégios do usuário');
select * from finish();
rollback;
