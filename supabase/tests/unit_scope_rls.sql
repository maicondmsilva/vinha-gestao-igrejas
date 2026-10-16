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


set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.organization_units),1::bigint,'líder lista somente unidade concedida');
select is(jsonb_array_length(public.access_context()->'memberships'->0->'units'),1,'contexto não lista unidades sem concessão');
select throws_ok($$select public.set_access_context('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001')$$,'42501',null,'seleção da sede sem concessão é negada');
select lives_ok($$select public.set_access_context('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002')$$,'seleção de unidade concedida funciona');
select is(private.can_access_unit('b0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000003'),false,'concessão não cruza organizações');

select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$insert into public.membership_unit_access(membership_id,unit_id) values('d0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000003')$$,'23503',null,'chave composta rejeita concessão em outra organização');
select is(private.can_access_unit('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000003'),false,'administrador não valida unidade de outra organização');
update public.organization_units set parent_unit_id='c0000000-0000-4000-8000-000000000001' where id='c0000000-0000-4000-8000-000000000002';
select throws_ok($$update public.organization_units set parent_unit_id='c0000000-0000-4000-8000-000000000002' where id='c0000000-0000-4000-8000-000000000001'$$,'23514',null,'banco rejeita ciclo de duas unidades');
select throws_ok($$update public.organization_units set parent_unit_id=id where id='c0000000-0000-4000-8000-000000000002'$$,'23514',null,'banco rejeita autoparentesco');
select is((select count(*) from public.organization_units),2::bigint,'administrador mantém leitura de todas as unidades próprias');

reset role;
insert into public.organization_units(id,organization_id,parent_unit_id,name,slug,unit_type)
values('c0000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','Filha do Campus','filha','congregation');
insert into public.people(id,organization_id,unit_id,full_name)
values('e0000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000004','Pessoa da Filha');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values('a0000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','secretary@example.test','',now(),now(),now());
insert into public.organization_memberships(id,organization_id,user_id,role,status)
values('d0000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','secretary','active');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.people),1::bigint,'sem herança o líder não vê membros das filhas');
reset role;
update public.membership_unit_access set include_children=true where membership_id='d0000000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.people),2::bigint,'herança libera somente campus e descendentes');
select is((select count(*) from public.organization_units),2::bigint,'herança também limita a lista de unidades');
select is(jsonb_array_length(public.access_context()->'memberships'->0->'units'),2,'contexto reflete a herança concedida');

select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select is((select count(*) from public.people),0::bigint,'secretaria sem concessão não ganha acesso organizacional');
reset role;
insert into public.membership_unit_access(membership_id,unit_id,access_level)
values('d0000000-0000-4000-8000-000000000004','c0000000-0000-4000-8000-000000000002','read');
set local role authenticated;
select is((select count(*) from public.people),1::bigint,'secretaria vê somente unidade concedida');
with changed as(update public.people set full_name='Indevido' where id='e0000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),0::bigint,'secretaria read não edita');
reset role;
update public.membership_unit_access set access_level='manage' where membership_id='d0000000-0000-4000-8000-000000000004';
set local role authenticated;
with changed as(update public.people set full_name='Atualizado' where id='e0000000-0000-4000-8000-000000000002' returning id)
select is((select count(*) from changed),1::bigint,'secretaria manage edita unidade concedida');
select throws_ok($$update public.people set unit_id='c0000000-0000-4000-8000-000000000001' where id='e0000000-0000-4000-8000-000000000002'$$,'42501',null,'edição não transfere membro para sede não concedida');
reset role;
delete from public.membership_unit_access where membership_id='d0000000-0000-4000-8000-000000000004';
set local role authenticated;
select is((select count(*) from public.people),0::bigint,'revogar concessão remove leitura imediatamente');

reset role;
update public.organization_memberships set status='revoked' where id='d0000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is((select count(*) from public.people),0::bigint,'participação revogada perde leitura do próprio cadastro');
select is(private.is_person_self('e0000000-0000-4000-8000-000000000003'),false,'consentimentos não recuperam privilégio por identidade revogada');

reset role;
update public.organizations set status='suspended' where id='b0000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.people),0::bigint,'suspensão do ministério bloqueia leitura dos membros');
select is((select count(*) from public.organization_units),0::bigint,'suspensão bloqueia leitura das unidades');
select is(jsonb_array_length(public.access_context()->'memberships'),0,'contexto não oferece ministério suspenso');
reset role;
set local role anon;
select throws_ok($$select count(*) from public.organization_units$$,'42501',null,'visitante não tem leitura direta das unidades');
select throws_ok($$select count(*) from public.membership_unit_access$$,'42501',null,'visitante não tem leitura direta das concessões');
select throws_ok($$select public.access_context()$$,'42501',null,'visitante não executa contexto autenticado');
reset role;
select * from finish();
rollback;
