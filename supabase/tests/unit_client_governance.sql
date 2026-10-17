begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select ('ac000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','unit-governance-'||i||'@example.test','',now(),now(),now() from generate_series(1,6)i;
insert into public.organizations(id,name,slug,status) values
 ('bc000000-0000-4000-8000-000000000001','Unidades A','unit-governance-a','active'),
 ('bc000000-0000-4000-8000-000000000002','Unidades B','unit-governance-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('cc000000-0000-4000-8000-000000000001','bc000000-0000-4000-8000-000000000001','Sede A','sede-a','headquarters'),
 ('cc000000-0000-4000-8000-000000000002','bc000000-0000-4000-8000-000000000001','Campus A','campus-a','campus'),
 ('cc000000-0000-4000-8000-000000000003','bc000000-0000-4000-8000-000000000002','Sede B','sede-b','headquarters');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
select 'bc000000-0000-4000-8000-000000000001',('ac000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 (case i when 1 then 'owner' when 2 then 'admin' when 3 then 'pastor' else 'viewer' end)::public.membership_role,'active','cc000000-0000-4000-8000-000000000001' from generate_series(1,4)i;
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
values('bc000000-0000-4000-8000-000000000002','ac000000-0000-4000-8000-000000000005','owner','active','cc000000-0000-4000-8000-000000000003');
select ok(not prosecdef,'proteção das unidades é invoker') from pg_proc where oid='private.guard_unit_client_fields()'::regprocedure;
select ok(not has_function_privilege('authenticated','private.guard_unit_client_fields()','EXECUTE'),'gatilho não é chamado diretamente pelo cliente');
select ok(not has_table_privilege('authenticated','public.organization_units','DELETE'),'cliente não recebe exclusão física de unidade');
select ok(not has_table_privilege('anon','public.organization_units','DELETE'),'visitante não recebe exclusão física de unidade');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$update public.organization_units set name='Nome permitido',legal_name='Razão permitida',tax_id='DOCUMENTO-SINTETICO',pastor_name='Pastor sintético',email='unit@example.test',phone='11999999999',address='{"city":"Cidade sintética"}',financial_autonomy=true,communication_autonomy=true,branding_autonomy=true where id='cc000000-0000-4000-8000-000000000002'$$,'proprietário mantém dados cadastrais e autonomias operacionais');
select is((select name from public.organization_units where id='cc000000-0000-4000-8000-000000000002'),'Nome permitido','alteração cadastral persiste');
select throws_ok($$update public.organization_units set id='cc000000-0000-4000-8000-000000000099' where id='cc000000-0000-4000-8000-000000000002'$$,'42501','unit_identity_fields_immutable','identidade da unidade não é transferida');
select throws_ok($$update public.organization_units set slug='slug-trocado' where id='cc000000-0000-4000-8000-000000000002'$$,'42501','unit_identity_fields_immutable','endereço digital da unidade não é trocado diretamente');
select throws_ok($$update public.organization_units set created_at=now()-interval '1 year' where id='cc000000-0000-4000-8000-000000000002'$$,'42501','unit_identity_fields_immutable','data original da unidade não é reescrita');
select throws_ok($$update public.organization_units set organization_id='bc000000-0000-4000-8000-000000000002' where id='cc000000-0000-4000-8000-000000000002'$$,'23514','unit_organization_is_immutable','isolamento anterior entre ministérios é preservado');
select throws_ok($$update public.organization_units set unit_type='headquarters' where id='cc000000-0000-4000-8000-000000000002'$$,'42501','unit_headquarters_classification_immutable','campus não vira sede para alterar tratamento contratual');
select throws_ok($$update public.organization_units set unit_type='campus' where id='cc000000-0000-4000-8000-000000000001'$$,'42501','unit_headquarters_classification_immutable','sede não perde classificação por edição comum');
select throws_ok($$update public.organization_units set parent_unit_id='cc000000-0000-4000-8000-000000000002' where id='cc000000-0000-4000-8000-000000000001'$$,'42501','unit_headquarters_parent_denied','sede não fica subordinada a outra unidade');
select throws_ok($$insert into public.organization_units(organization_id,name,slug,unit_type) values('bc000000-0000-4000-8000-000000000001','Outra sede','outra-sede','headquarters')$$,'42501','unit_headquarters_exists','cliente não cria segunda sede');
select throws_ok($$insert into public.organization_units(organization_id,name,slug,created_at) values('bc000000-0000-4000-8000-000000000001','Data antiga','data-antiga',now()-interval '1 year')$$,'42501','unit_original_date_denied','INSERT não fabrica data antiga');
select lives_ok($$insert into public.organization_units(id,organization_id,name,slug,unit_type) values('cc000000-0000-4000-8000-000000000004','bc000000-0000-4000-8000-000000000001','Regional permitida','regional-permitida','regional')$$,'nova unidade não sede continua permitida');
select lives_ok($$update public.organization_units set unit_type='congregation',parent_unit_id='cc000000-0000-4000-8000-000000000004' where id='cc000000-0000-4000-8000-000000000002'$$,'tipos não sede e organização hierárquica continuam editáveis');
select lives_ok($$update public.organization_units set status='suspended' where id='cc000000-0000-4000-8000-000000000002'$$,'gestor mantém inativação operacional da unidade');
select lives_ok($$update public.organization_units set status='active' where id='cc000000-0000-4000-8000-000000000002'$$,'reativação operacional não muda contrato');
select lives_ok($$update public.organization_units set updated_at=now()-interval '1 year' where id='cc000000-0000-4000-8000-000000000002'$$,'horário enviado pelo cliente é substituído');
select is((select updated_at from public.organization_units where id='cc000000-0000-4000-8000-000000000002'),transaction_timestamp(),'horário efetivo vem do banco');
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$update public.organization_units set name='Administrador atualizou' where id='cc000000-0000-4000-8000-000000000002'$$,'administrador mantém edição comum');
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$update public.organization_units set name='Pastor atualizou' where id='cc000000-0000-4000-8000-000000000002'$$,'pastor mantém edição comum');
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
with changed as(update public.organization_units set name='Indevido' where id='cc000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'leitor não ganha escrita');
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
with changed as(update public.organization_units set name='Outra igreja' where id='cc000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'proprietário de outro ministério não ganha escrita');
reset role;
update public.organizations set status='suspended' where id='bc000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$insert into public.organization_units(organization_id,name,slug) values('bc000000-0000-4000-8000-000000000001','Suspenso','suspenso')$$,'42501','unit_organization_unavailable','INSERT direto não contorna suspensão do ministério');
select lives_ok($cmd$do $$declare changed int;begin update public.organization_units set name='Indevido suspenso';get diagnostics changed=row_count;if changed<>0 then raise exception 'unexpected_write';end if;exception when insufficient_privilege then null;end$$;$cmd$,'UPDATE direto não altera unidades de ministério suspenso');
reset role;
select is((select name from public.organization_units where id='cc000000-0000-4000-8000-000000000002'),'Pastor atualizou','tentativa suspensa não modifica cadastro');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
select lives_ok($$select public.bootstrap_organization('Bootstrap unidades','unit-governance-bootstrap','Sede sintética')$$,'primeira sede legítima continua criada pelo bootstrap confirmado');
reset role;
select is((select count(*) from public.organization_units u join public.organizations o on o.id=u.organization_id where o.slug='unit-governance-bootstrap' and u.unit_type='headquarters'),1::bigint,'bootstrap cria uma única sede');
select * from finish();
rollback;
