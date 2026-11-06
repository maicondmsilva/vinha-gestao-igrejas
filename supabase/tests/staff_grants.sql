begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.pa(t text) returns uuid language sql immutable as $$select md5('staff-grants-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.pa(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-grants@example.invalid',now(),now(),now()
 from unnest(array['owner','secretary','leader','member'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pa('org'),'Ministério fictício permissões','staff-grants-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.pa('a'),pg_temp.pa('org'),'Sede fictícia','a','headquarters');
insert into public.organization_units(id,organization_id,parent_unit_id,name,slug,unit_type) values(pg_temp.pa('b'),pg_temp.pa('org'),pg_temp.pa('a'),'Congregação fictícia','b','campus');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status)
 select pg_temp.pa(t||'-m'),pg_temp.pa('org'),pg_temp.pa(t),pg_temp.pa('a'),t::public.membership_role,'active' from unnest(array['owner','secretary','leader','member'])t;
-- Secretaria lê só a sede; liderança lê a sede e as filhas.
insert into public.membership_unit_access(membership_id,unit_id,access_level,include_children,organization_id) values
 (pg_temp.pa('secretary-m'),pg_temp.pa('a'),'read',false,pg_temp.pa('org')),(pg_temp.pa('leader-m'),pg_temp.pa('a'),'read',true,pg_temp.pa('org'));
create function pg_temp.fields() returns jsonb language sql as $$select jsonb_build_object('title','Culto fictício','description','Somente teste','kind','service',
 'startsLocal',to_char(make_timestamp(extract(year from now())::integer+1,3,10,19,0,0),'YYYY-MM-DD"T"HH24:MI'),'endsLocal',to_char(make_timestamp(extract(year from now())::integer+1,3,10,21,0,0),'YYYY-MM-DD"T"HH24:MI'),
 'location','Local fictício','address','','capacity',10,'category','','cover','','repeat','none','count',1)$$;
create function pg_temp.grant_set(u text,unit text,scopes text[]) returns jsonb language sql as $$select public.staff_access(pg_temp.pa('org'),'grant',jsonb_build_object('user',pg_temp.pa(u),'unit',pg_temp.pa(unit),'scopes',to_jsonb(scopes)))$$;

select ok(not has_function_privilege('anon','public.staff_access(uuid,text,jsonb)','execute'),'visitante não chama o controle de acesso');
select ok(has_function_privilege('anon','public.unit_timezone(uuid)','execute'),'fuso é público');

-- Sem concessão: secretaria e liderança seguem como antes.
set local role authenticated;select pg_temp.actor('secretary');
select throws_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-a')::uuid,'list')$$,'42501',null,'secretaria sem concessão não vê a agenda');
select is((public.staff_access(pg_temp.pa('org'),'mine')->'units'->0->>'agenda'),'false','meu acesso: sem agenda');
select throws_ok($$select public.staff_access(md5('staff-grants-test-org')::uuid,'list')$$,'42501',null,'secretaria não gerencia concessões');
select pg_temp.actor('member');
select is(jsonb_array_length(public.staff_access(pg_temp.pa('org'),'mine')->'units'),0,'membro não tem unidades de equipe');
reset role;

-- Concessões só pela administração, só para secretaria/liderança e só em unidade acessível.
set local role authenticated;select pg_temp.actor('owner');
select throws_ok($$select pg_temp.grant_set('member','a',array['agenda'])$$,'22023','staff_access_role','membro não recebe concessão');
select throws_ok($$select pg_temp.grant_set('secretary','b',array['agenda'])$$,'22023','staff_access_unit','unidade sem acesso recusada');
select throws_ok($$select pg_temp.grant_set('secretary','a',array['finance'])$$,'22023','invalid_staff_access','escopo desconhecido');
select lives_ok($$select pg_temp.grant_set('secretary','a',array['agenda','push','push'])$$,'secretaria recebe agenda e push');
select is((select x->'grants'->pg_temp.pa('a')::text from jsonb_array_elements(public.staff_access(pg_temp.pa('org'),'list')->'team') x where x->>'role'='secretary'),'["agenda", "push"]'::jsonb,'concessões salvas sem repetição');
select is((select jsonb_array_length(x->'units') from jsonb_array_elements(public.staff_access(pg_temp.pa('org'),'list')->'team') x where x->>'role'='leader'),2,'liderança alcança a filha pelo acesso com filhas');
select lives_ok($$select pg_temp.grant_set('leader','b',array['checkin'])$$,'liderança recebe entrada na filha');
reset role;
select is((select count(*)::int from public.audit_logs where organization_id=pg_temp.pa('org') and action='staff.grants.set'),2,'auditoria das concessões');

-- Agenda concedida: secretaria cria e lista; entrada concedida: liderança lê, mas não cria.
set local role authenticated;select pg_temp.actor('secretary');
select lives_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-a')::uuid,'create',md5('staff-grants-test-req')::uuid,null,pg_temp.fields())$$,'secretaria com agenda cria evento');
select is(public.programming_admin(pg_temp.pa('org'),pg_temp.pa('a'),'list')->>'total','1','secretaria lista a agenda');
select is((select x->>'push' from jsonb_array_elements(public.staff_access(pg_temp.pa('org'),'mine')->'units') x where x->>'id'=pg_temp.pa('a')::text),'true','meu acesso: push');
select is((select x->>'publishing' from jsonb_array_elements(public.staff_access(pg_temp.pa('org'),'mine')->'units') x where x->>'id'=pg_temp.pa('a')::text),'false','push não dá publicação');
select pg_temp.actor('leader');
select throws_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-a')::uuid,'list')$$,'42501',null,'entrada vale só na unidade concedida');
select lives_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-b')::uuid,'list')$$,'entrada lê a agenda da filha');
select throws_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-b')::uuid,'create',md5('staff-grants-test-req2')::uuid,null,pg_temp.fields())$$,'42501','member_agenda_denied','entrada não cria evento');
reset role;

-- Revogar: lista vazia remove; perder o papel também remove o efeito.
set local role authenticated;select pg_temp.actor('owner');
select lives_ok($$select pg_temp.grant_set('secretary','a',array[]::text[])$$,'concessões removidas');
reset role;
set local role authenticated;select pg_temp.actor('secretary');
select throws_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-a')::uuid,'list')$$,'42501',null,'sem concessão de novo');
reset role;
update public.organization_memberships set role='member' where id=pg_temp.pa('leader-m');
set local role authenticated;select pg_temp.actor('leader');
select throws_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-b')::uuid,'list')$$,'42501',null,'papel de membro anula a concessão');
reset role;

-- Fuso: padrão Brasília, ministério e unidade; inválido recusado.
select is(public.unit_timezone(pg_temp.pa('b')),'America/Sao_Paulo','padrão Brasília');
set local role authenticated;select pg_temp.actor('owner');
select throws_ok($$select public.staff_access(md5('staff-grants-test-org')::uuid,'timezone','{"timezone":"Mars/Olympus"}')$$,'22023','invalid_timezone','fuso inexistente');
select is(public.staff_access(pg_temp.pa('org'),'timezone','{"timezone":"America/Manaus"}')->>'timezone','America/Manaus','fuso do ministério');
select is(public.unit_timezone(pg_temp.pa('b')),'America/Manaus','unidade herda o ministério');
select lives_ok($$select public.staff_access(md5('staff-grants-test-org')::uuid,'timezone',jsonb_build_object('unit',md5('staff-grants-test-a')::uuid,'timezone','America/Sao_Paulo'))$$,'fuso próprio da sede');
select is(public.unit_timezone(pg_temp.pa('a')),'America/Sao_Paulo','sede usa o próprio');
-- Evento criado na filha (fuso de Manaus): 19h local = 23h UTC.
select lives_ok($$select public.programming_admin(md5('staff-grants-test-org')::uuid,md5('staff-grants-test-b')::uuid,'create',md5('staff-grants-test-req3')::uuid,null,pg_temp.fields())$$,'administração cria na filha');
reset role;
select is((select extract(hour from starts_at at time zone 'UTC')::int from private.church_app_events where organization_id=pg_temp.pa('org') and unit_id=pg_temp.pa('b')),23,'horário local interpretado no fuso da unidade');
select is((select extract(hour from starts_at at time zone 'UTC')::int from private.church_app_events where organization_id=pg_temp.pa('org') and unit_id=pg_temp.pa('a')),22,'sede continua em Brasília');
select * from finish();
rollback;
