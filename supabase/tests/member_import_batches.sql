begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('a8000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','import-owner@example.test',now(),now(),now()),
 ('a8000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','import-leader@example.test',now(),now(),now()),
 ('a8000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','import-outside@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values
 ('b8000000-0000-4000-8000-000000000001','Import A','import-batch-a','active'),
 ('b8000000-0000-4000-8000-000000000002','Import B','import-batch-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','Sede Import','sede-import','headquarters'),
 ('c8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','Campus Import','campus-import','campus'),
 ('c8000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000002','Outra sede','outra-sede-import','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values
 ('d8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','owner','active'),
 ('d8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000002','c8000000-0000-4000-8000-000000000002','leader','active'),
 ('d8000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000002','a8000000-0000-4000-8000-000000000003','c8000000-0000-4000-8000-000000000003','owner','active');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values
 ('d8000000-0000-4000-8000-000000000002','c8000000-0000-4000-8000-000000000002','read');
insert into public.people(organization_id,unit_id,full_name,email,cpf) values
 ('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','Preservar existente','existing-import@example.test','529.982.247-25');
create function pg_temp.fail_import_audit() returns trigger language plpgsql as $$begin
 if new.action='people.imported' and current_setting('vinha.fail_import',true)='yes' then raise exception 'forced_import_audit_failure' using errcode='23514';end if;return new;end;$$;
create trigger test_import_audit before insert on public.audit_logs for each row execute function pg_temp.fail_import_audit();

select ok((select not prosecdef from pg_proc where oid='public.import_member_batch(uuid,uuid,jsonb,text,uuid,text)'::regprocedure),'member writes retain invoker security');
select ok((select relrowsecurity from pg_class where oid='public.member_import_receipts'::regclass),'receipts have RLS');
select ok(not has_function_privilege('anon','public.import_member_batch(uuid,uuid,jsonb,text,uuid,text)','EXECUTE'),'visitors cannot import');
select ok(not has_table_privilege('authenticated','public.member_import_receipts','INSERT'),'clients cannot forge receipts');
select ok(not has_table_privilege('authenticated','public.member_import_receipts','UPDATE'),'clients cannot rewrite receipts');
select ok(not has_table_privilege('authenticated','public.member_import_receipts','DELETE'),'clients cannot erase receipts');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Prévia sem gravação","nascimento":"1990-02-28","status":"member"}]','preview')->>'valid')::integer,1,'preview accepts valid normalized date and status');
select is((select count(*) from public.people where full_name='Prévia sem gravação'),0::bigint,'preview never inserts members');
select is((select count(*) from public.member_import_receipts),0::bigint,'preview never creates receipts');
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Existente","email":"EXISTING-IMPORT@EXAMPLE.TEST"},{"nome":"CPF existente","cpf":"52998224725"}]','preview')->>'skipped')::integer,2,'email case and normalized CPF identify existing records');
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Pessoa nova","email":"repeat-import@example.test"},{"nome":"Pessoa repetida","email":"repeat-import@example.test"}]','preview')->>'invalid')::integer,1,'duplicate email inside CSV is not duplicated');
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"CPF ruim","cpf":"11111111111"},{"nome":"Data ruim","nascimento":"2025-02-31"},{"nome":"Outra unidade","campus":"Campus Import"},{"nome":"Papel injetado","app_role":"admin"}]','preview')->>'invalid')::integer,4,'invalid CPF date unit and privileged fields are rejected');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[]','preview')$$,'22023',null,'empty input is rejected');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Pessoa"}]',null)$$,'22023',null,'null mode cannot accidentally commit');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001',(select jsonb_agg(jsonb_build_object('nome','Pessoa '||g)) from generate_series(1,101) g),'commit','f8000000-0000-4000-8000-000000000001')$$,'22023',null,'commit is bounded at 100 rows');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Pessoa"}]','commit')$$,'22023',null,'commit requires an idempotency identity');
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Importado novo","email":"imported-new@example.test"},{"nome":"Sem identidade externa"},{"nome":"Não substituir","email":"existing-import@example.test"},{"nome":"X"}]','commit','f8000000-0000-4000-8000-000000000002')->>'imported')::integer,2,'commit imports only valid unseen rows');
select is((select full_name from public.people where email='existing-import@example.test'),'Preservar existente','existing record was not overwritten');
select is((select count(*) from public.member_import_receipts),1::bigint,'one receipt written');
select is((select result->>'invalid' from public.member_import_receipts),'1','receipt includes invalid count');
select is((select result->>'skipped' from public.member_import_receipts),'1','receipt includes skipped count');
select is((select count(*) from public.people where full_name='Importado novo' and app_role='member' and auth_user_id is null),1::bigint,'import never creates or links authentication identities');
select is((select count(*) from public.person_consents c join public.people p on p.id=c.person_id where p.full_name='Importado novo'),0::bigint,'import never fabricates member consent');
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Importado novo","email":"imported-new@example.test"},{"nome":"Sem identidade externa"},{"nome":"Não substituir","email":"existing-import@example.test"},{"nome":"X"}]','commit','f8000000-0000-4000-8000-000000000002')->>'replayed')::boolean,true,'same request returns original result');
select is((select count(*) from public.people where full_name='Sem identidade externa'),1::bigint,'retry does not duplicate even a name-only person');
select is((select count(*) from public.audit_logs where action='people.imported'),1::bigint,'retry never duplicates batch audit');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Payload trocado"}]','commit','f8000000-0000-4000-8000-000000000002')$$,'22023',null,'request id cannot be reused for another payload');
select set_config('vinha.fail_import','yes',true);
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Reverter lote um"},{"nome":"Reverter lote dois"}]','commit','f8000000-0000-4000-8000-000000000003')$$,'23514',null,'audit failure aborts the complete batch');
select set_config('vinha.fail_import','no',true);
select is((select count(*) from public.people where full_name like 'Reverter lote%'),0::bigint,'no partially imported people survive failure');
select is((select count(*) from public.member_import_receipts where id='f8000000-0000-4000-8000-000000000003'),0::bigint,'no false receipt survives failure');
select ok(not (select result::text like '%imported-new@example.test%' from public.member_import_receipts limit 1),'receipt stores no raw CSV contact data');

select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','[{"nome":"Sem gestão"}]','preview')$$,'42501',null,'read-only unit access cannot import');
select is((select count(*) from public.member_import_receipts),0::bigint,'another member cannot read import history');
reset role;
update public.membership_unit_access set access_level='manage' where membership_id='d8000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','[{"nome":"CPF de outra unidade","cpf":"52998224725"}]','preview')->>'skipped')::integer,1,'scoped importer skips duplicates without returning foreign-unit member data');
select is((public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','[{"nome":"Líder autorizado"}]','commit','f8000000-0000-4000-8000-000000000004')->>'imported')::integer,1,'manage grant allows import only into granted unit');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Sede proibida"}]','preview')$$,'42501',null,'leader cannot select another unit');
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000002','c8000000-0000-4000-8000-000000000003','[{"nome":"Outra organização"}]','preview')$$,'42501',null,'leader cannot import to another organization');
reset role;
update public.organizations set status='suspended' where id='b8000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.import_member_batch('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','[{"nome":"Suspensa"}]','preview')$$,'42501',null,'suspended organization cannot even prepare import');
reset role;
select * from finish();
rollback;
