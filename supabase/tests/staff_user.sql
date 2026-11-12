begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Usuários: ficha que edita o mesmo cadastro do membro, exclusão (tirar o acesso), busca e troca de senha obrigatória.
create function pg_temp.su(t text) returns uuid language sql immutable as $$select md5('staff-user-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.su(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.su(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-su@example.invalid',now(),now(),now()
from unnest(array['owner','admin','pastor','member','app','other','secretary']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.su('org'),'Usuários fictício','staff-user-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 (pg_temp.su('unit'),pg_temp.su('org'),'Sede usuários','sede','headquarters'),
 (pg_temp.su('unit2'),pg_temp.su('org'),'Bairro usuários','bairro','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.su('owner-m'),pg_temp.su('org'),pg_temp.su('owner'),'owner','active',pg_temp.su('unit')),
 (pg_temp.su('admin-m'),pg_temp.su('org'),pg_temp.su('admin'),'admin','active',pg_temp.su('unit')),
 (pg_temp.su('pastor-m'),pg_temp.su('org'),pg_temp.su('pastor'),'pastor','active',pg_temp.su('unit')),
 (pg_temp.su('member-m'),pg_temp.su('org'),pg_temp.su('member'),'member','active',pg_temp.su('unit')),
 (pg_temp.su('secretary-m'),pg_temp.su('org'),pg_temp.su('secretary'),'secretary','active',pg_temp.su('unit'));
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,email,phone,cpf,status) values
 (pg_temp.su('member-p'),pg_temp.su('org'),pg_temp.su('unit'),pg_temp.su('member'),'Maria Teste','member-su@example.invalid','11911112222','123.456.789-09','active'),
 (pg_temp.su('app-p'),pg_temp.su('org'),pg_temp.su('unit'),pg_temp.su('app'),'João do App','app-su@example.invalid','11933334444',null,'active'),
 (pg_temp.su('plain-p'),pg_temp.su('org'),pg_temp.su('unit'),null,'Pedro Sem Login','pedro-su@example.invalid',null,'98765432100','active');
insert into public.person_addresses(organization_id,person_id,postal_code,street,number,city,state) values
 (pg_temp.su('org'),pg_temp.su('member-p'),'01001000','Praça da Sé','10','São Paulo','SP');
insert into private.permission_grants(organization_id,membership_id,permission,actions,granted_by)
 values(pg_temp.su('org'),pg_temp.su('member-m'),'people.members',array['view'],pg_temp.su('owner'));

select has_column('public','people','marriage_date','pessoa guarda a data de casamento');
select has_column('public','people','is_pastor','pessoa marca se é pastor');
select has_column('public','organization_memberships','password_change_required','vínculo marca a troca de senha');

set local role authenticated;
select pg_temp.actor('owner');

select throws_ok($$select public.create_staff_invitation(pg_temp.su('org'),pg_temp.su('unit'),'novo-su@example.invalid','Novo Convite','member')$$,'0A000',null,'convites desativados');

-- Ficha
select is((public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{person,full_name}'),'Maria Teste','dono abre a ficha completa');
select is((public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{person,phone}'),'11911112222','ficha traz o celular do membro');
select is((public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{person,address,street}'),'Praça da Sé','ficha traz o endereço do membro');
select is((public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))->>'hasLogin'),'true','ficha diz que há login');
select is((public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))->>'email'),'member-su@example.invalid','ficha traz o e-mail do login');

-- Salvar
create temp table v(k text primary key, val text) on commit drop;
grant all on v to authenticated;
insert into v select 'member',public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{membership,version}';
select lives_ok($$select public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('membership',pg_temp.su('member-m'),'version',(select val from v where k='member'),'role','leader','unit',pg_temp.su('unit2'),
 'account',jsonb_build_object('name','Maria Teste Silva','phone','11955556666','email','member-su@example.invalid'),
 'address',jsonb_build_object('postal_code','01310100','street','Av. Paulista','number','1000','city','São Paulo','state','SP'),
 'extra',jsonb_build_object('gender','female','birth_date','1990-05-01','marriage_date','2015-02-14','is_pastor',false)))$$,'salvar a ficha');
select is((select phone from public.people where id=pg_temp.su('member-p')),'11955556666','salvar grava no membro');
select is((select full_name from public.people where id=pg_temp.su('member-p')),'Maria Teste Silva','salvar grava o nome no membro');
select is((select marriage_date::text from public.people where id=pg_temp.su('member-p')),'2015-02-14','salvar grava a data de casamento');
select is((select street from public.person_addresses where person_id=pg_temp.su('member-p')),'Av. Paulista','salvar grava o endereço');
select is((select role::text from public.organization_memberships where id=pg_temp.su('member-m')),'leader','salvar grava no vínculo');
select is((select default_unit_id from public.organization_memberships where id=pg_temp.su('member-m')),pg_temp.su('unit2'),'salvar grava a igreja do vínculo');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('membership',pg_temp.su('member-m'),'version',(select val from v where k='member'),'role','leader','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Outra Maria','phone','11955556666','email','member-su@example.invalid')))$$,'40001',null,'versão antiga recusada');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('membership',pg_temp.su('member-m'),'version',public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{membership,version}','role','leader','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Maria Teste Silva','email','app-su@example.invalid')))$$,'23505','email_in_use','e-mail de outra conta recusado');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('membership',pg_temp.su('member-m'),'version',public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{membership,version}','role','owner','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Maria Teste Silva','email','member-su@example.invalid')))$$,'42501',null,'ficha não transfere a propriedade');

-- Pessoa nova e pessoa existente
insert into v select 'new',public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('role','member','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Ana Nova','phone','11977778888','email','ana-su@example.invalid')))::text;
select is((select (val::jsonb->>'needsLogin') from v where k='new'),'true','pessoa nova cria membro e pede login');
select is((select count(*)::int from public.people where organization_id=pg_temp.su('org') and email='ana-su@example.invalid'),1,'pessoa nova vira cadastro de membro');
select is((select (val::jsonb->>'membership') from v where k='new'),null,'sem login ainda não há vínculo');
insert into v select 'plain',public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('person',pg_temp.su('plain-p'),'version',
 (public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','Pedro'))#>>'{items,0,version}'),'role','secretary','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Pedro Sem Login','email','pedro-su@example.invalid')))::text;
select is((select (val::jsonb->>'needsLogin') from v where k='plain'),'true','pessoa existente sem login pede login');
select is((select (val::jsonb->>'person')::uuid from v where k='plain'),pg_temp.su('plain-p'),'pessoa existente não é duplicada');
insert into v select 'app',public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('person',pg_temp.su('app-p'),'version',
 (public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','João'))#>>'{items,0,version}'),'role','leader','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','João do App','email','app-su@example.invalid')))::text;
select is((select (val::jsonb->>'needsLogin') from v where k='app'),'false','pessoa com login do app não pede outro');
select is((select role::text from public.organization_memberships where organization_id=pg_temp.su('org') and user_id=pg_temp.su('app')),'leader','pessoa com login do app ganha o vínculo');

-- Ligar o login criado pela rota
select throws_ok($$select public.staff_user(pg_temp.su('org'),'link_login',jsonb_build_object('person',pg_temp.su('plain-p'),'user',pg_temp.su('other'),'role','secretary','unit',pg_temp.su('unit'),'passwordSet',true))$$,'42501',null,'login com outro e-mail não é ligado');
reset role;
update auth.users set email='pedro-su@example.invalid' where id=pg_temp.su('other');
set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select public.staff_user(pg_temp.su('org'),'link_login',jsonb_build_object('person',pg_temp.su('plain-p'),'user',pg_temp.su('other'),'role','secretary','unit',pg_temp.su('unit'),'passwordSet',true))$$,'login criado pela rota é ligado');
select is((select auth_user_id from public.people where id=pg_temp.su('plain-p')),pg_temp.su('other'),'membro fica ligado ao login');
select is((select password_change_required from public.organization_memberships where organization_id=pg_temp.su('org') and user_id=pg_temp.su('other')),true,'senha do painel exige troca');

select lives_ok($$select public.staff_user(pg_temp.su('org'),'mark_password',jsonb_build_object('membership',(select id from public.organization_memberships where organization_id=pg_temp.su('org') and user_id=pg_temp.su('app'))))$$,'senha nova pelo painel registrada');
select is((select password_change_required from public.organization_memberships where organization_id=pg_temp.su('org') and user_id=pg_temp.su('app')),true,'senha nova pelo painel exige troca');

-- Busca
select is((public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','maria'))#>>'{items,0,name}'),'Maria Teste Silva','busca encontra por nome');
select is((public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','member-su@'))#>>'{items,0,name}'),'Maria Teste Silva','busca encontra por e-mail');
select is((public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','123456789'))#>>'{items,0,cpf_masked}'),'***.456.789-**','busca encontra por CPF e mascara');

-- Regras de papel
select pg_temp.actor('pastor');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('membership',pg_temp.su('member-m'),'version',public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('member-m')))#>>'{membership,version}','role','admin','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Maria Teste Silva','email','member-su@example.invalid')))$$,'42501',null,'pastor não promove a administrador');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'remove',jsonb_build_object('membership',pg_temp.su('admin-m')))$$,'42501',null,'admin só pelo dono');
select pg_temp.actor('member');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('owner-m')))$$,'42501',null,'membro comum não abre fichas');
select pg_temp.actor('admin');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'remove',jsonb_build_object('membership',pg_temp.su('owner-m')))$$,'42501',null,'não exclui o dono');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'remove',jsonb_build_object('membership',pg_temp.su('admin-m')))$$,'42501',null,'não exclui a si mesmo');
select lives_ok($$select public.staff_user(pg_temp.su('org'),'remove',jsonb_build_object('membership',pg_temp.su('member-m')))$$,'admin exclui um líder');
select is((select status::text from public.organization_memberships where id=pg_temp.su('member-m')),'revoked','excluir remove o acesso');
reset role;
select is((select count(*)::int from private.permission_grants where membership_id=pg_temp.su('member-m')),0,'excluir remove as permissões avulsas');
set local role authenticated;
select pg_temp.actor('admin');
select is((select count(*)::int from public.people where id=pg_temp.su('member-p')),1,'excluir mantém o membro');
select is((select count(*)::int from jsonb_array_elements(public.staff_directory(pg_temp.su('org'))->'users') u where u->>'id'=pg_temp.su('member-m')::text),0,'lista de usuários não mostra quem perdeu o acesso');
select pg_temp.actor('owner');
select lives_ok($$select public.staff_user(pg_temp.su('org'),'remove',jsonb_build_object('membership',pg_temp.su('admin-m')))$$,'dono exclui administrador');

-- Permissão concedida em Configurações › Usuários
select pg_temp.actor('secretary');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','a'))$$,'42501',null,'sem permissão não busca');
reset role;
insert into private.permission_grants(organization_id,membership_id,permission,actions,granted_by) values(pg_temp.su('org'),pg_temp.su('secretary-m'),'settings.users',array['view','edit'],pg_temp.su('owner'));
set local role authenticated;
select pg_temp.actor('secretary');
select lives_ok($$select public.staff_user(pg_temp.su('org'),'search',jsonb_build_object('q','a'))$$,'permissão de usuários libera a busca');
select throws_ok($$select public.staff_user(pg_temp.su('org'),'save',jsonb_build_object('membership',pg_temp.su('pastor-m'),'version',public.staff_user(pg_temp.su('org'),'get',jsonb_build_object('membership',pg_temp.su('pastor-m')))#>>'{membership,version}','role','member','unit',pg_temp.su('unit'),
 'account',jsonb_build_object('name','Pastor','email','pastor-su@example.invalid')))$$,'42501',null,'ninguém mexe em papel acima do próprio');

-- Troca de senha
select pg_temp.actor('other');
select lives_ok($$select public.password_change_done()$$,'troca de senha concluída');
select is((select password_change_required from public.organization_memberships where organization_id=pg_temp.su('org') and user_id=pg_temp.su('other')),false,'password_change_done apaga a marca');
reset role;
select is((select count(*)::int from public.audit_logs where organization_id=pg_temp.su('org') and action in ('staff.user.saved','staff.user.removed')) >= 5,true,'ficha gera auditoria');
select * from finish();
rollback;
