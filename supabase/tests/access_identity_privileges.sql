-- Local-only synthetic fixtures. No data survives this transaction.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Check every public table, not only the rows currently covered by a screen.
select ok(not has_table_privilege(r.role,c.oid,p.privilege),format('%s sem %s em public.%s',r.role,p.privilege,c.relname))
from pg_class c join pg_namespace n on n.oid=c.relnamespace
cross join (values('anon'),('authenticated')) r(role)
cross join (values('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) p(privilege)
where n.nspname='public' and c.relkind in ('r','p') order by c.relname,r.role,p.privilege;

-- Also exercise the default ACL instead of only inspecting the current grants.
create table public.test_future_access_acl(id integer);
select ok(not has_table_privilege(r.role,'public.test_future_access_acl',p.privilege),format('tabela futura: %s sem %s',r.role,p.privilege))
from (values('anon'),('authenticated')) r(role)
cross join (values('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) p(privilege);
drop table public.test_future_access_acl;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
 ('a7000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','access-owner@example.test','',now(),now(),now()),
 ('a7000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','access-member@example.test','',now(),now(),now()),
 ('a7000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','access-other@example.test','',now(),now(),now());
insert into public.organizations(id,name,slug) values
 ('b7000000-0000-4000-8000-000000000001','Identidade A','access-identity-a'),
 ('b7000000-0000-4000-8000-000000000002','Identidade B','access-identity-b');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c7000000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','Sede A','sede','headquarters'),
 ('c7000000-0000-4000-8000-000000000002','b7000000-0000-4000-8000-000000000001','Campus A','campus','campus'),
 ('c7000000-0000-4000-8000-000000000003','b7000000-0000-4000-8000-000000000002','Sede B','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7000000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','a7000000-0000-4000-8000-000000000001','owner','active','c7000000-0000-4000-8000-000000000001'),
 ('d7000000-0000-4000-8000-000000000002','b7000000-0000-4000-8000-000000000001','a7000000-0000-4000-8000-000000000002','leader','active','c7000000-0000-4000-8000-000000000001'),
 ('d7000000-0000-4000-8000-000000000003','b7000000-0000-4000-8000-000000000002','a7000000-0000-4000-8000-000000000002','leader','active','c7000000-0000-4000-8000-000000000003');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values
 ('d7000000-0000-4000-8000-000000000002','c7000000-0000-4000-8000-000000000001','read');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$truncate public.profiles$$,'42501',null,'TRUNCATE real é negado sem executar exclusão');
select throws_ok($$truncate public.organization_memberships cascade$$,'42501',null,'TRUNCATE CASCADE também é negado');
select throws_ok($$update public.organization_memberships set user_id='a7000000-0000-4000-8000-000000000003' where id='d7000000-0000-4000-8000-000000000002'$$,'42501','membership_identity_is_immutable','proprietário não transfere participação para outra conta');
select throws_ok($$update public.organization_memberships set id='d7000000-0000-4000-8000-000000000099' where id='d7000000-0000-4000-8000-000000000002'$$,'42501','membership_identity_is_immutable','id da participação é preservado');
select throws_ok($$update public.organization_memberships set organization_id='b7000000-0000-4000-8000-000000000002',default_unit_id='c7000000-0000-4000-8000-000000000003' where id='d7000000-0000-4000-8000-000000000001'$$,'42501','membership_identity_is_immutable','identidade não muda de ministério');
select throws_ok($$update public.organization_memberships set created_at='2099-01-01' where id='d7000000-0000-4000-8000-000000000002'$$,'42501','membership_identity_is_immutable','origem temporal da participação é preservada');
select throws_ok($$update public.membership_unit_access set membership_id='d7000000-0000-4000-8000-000000000001' where membership_id='d7000000-0000-4000-8000-000000000002'$$,'42501','unit_grant_identity_is_immutable','concessão não é transferida para outra participação');
select throws_ok($$update public.membership_unit_access set unit_id='c7000000-0000-4000-8000-000000000002' where membership_id='d7000000-0000-4000-8000-000000000002'$$,'42501','unit_grant_identity_is_immutable','concessão não é reaproveitada em outra unidade');
select throws_ok($$update public.membership_unit_access set created_at='2099-01-01' where membership_id='d7000000-0000-4000-8000-000000000002'$$,'42501','unit_grant_identity_is_immutable','origem temporal da concessão é preservada');
select throws_ok($$update public.membership_unit_access set organization_id='b7000000-0000-4000-8000-000000000002' where membership_id='d7000000-0000-4000-8000-000000000002'$$,'42501','unit_grant_identity_is_immutable','organização da concessão não muda');
with changed as(update public.organization_memberships set default_unit_id='c7000000-0000-4000-8000-000000000002' where id='d7000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),1::bigint,'gestor ainda altera unidade padrão autorizada');
with changed as(update public.membership_unit_access set access_level='manage',include_children=true where membership_id='d7000000-0000-4000-8000-000000000002' returning membership_id)
select is((select count(*) from changed),1::bigint,'gestor ainda altera nível e herança da mesma concessão');
with changed as(update public.organization_memberships set status='suspended' where id='d7000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),1::bigint,'revogação administrativa existente continua disponível');
select is((select user_id from public.organization_memberships where id='d7000000-0000-4000-8000-000000000002'),'a7000000-0000-4000-8000-000000000002'::uuid,'conta original foi preservada');
select ok(not has_function_privilege('authenticated','private.guard_access_identity()','EXECUTE'),'cliente não executa gatilho interno diretamente');
reset role;
set local role anon;
select throws_ok($$truncate public.profiles$$,'42501',null,'visitante não esvazia perfis');
reset role;
select * from finish();
rollback;
