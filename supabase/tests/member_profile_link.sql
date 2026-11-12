begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- P5: perfis pendentes em Pessoas, vínculo app ↔ membro por e-mail/CPF e tipo de perfil.
create function pg_temp.mi(t text) returns uuid language sql immutable as $$select md5('member-link-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.mi(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.mi(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-link@example.invalid',now(),now(),now() from unnest(array['owner','reviewer','ana','bia']) t;
insert into public.organizations(id,name,slug,status) values(pg_temp.mi('org'),'Ministério vínculo','member-link-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.mi('unit'),pg_temp.mi('org'),'Sede vínculo','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values
 (pg_temp.mi('owner-m'),pg_temp.mi('org'),pg_temp.mi('owner'),pg_temp.mi('unit'),'owner','active'),
 (pg_temp.mi('reviewer-m'),pg_temp.mi('org'),pg_temp.mi('reviewer'),pg_temp.mi('unit'),'member','active');
-- Ana tem dois cadastros antigos: um com o CPF dela (sem e-mail) e outro com o e-mail dela.
insert into public.people(id,organization_id,unit_id,full_name,email,cpf,journey_status,status) values
 (pg_temp.mi('ana-1'),pg_temp.mi('org'),pg_temp.mi('unit'),'Ana antiga',null,'12345678901','Em integração','active'),
 (pg_temp.mi('ana-2'),pg_temp.mi('org'),pg_temp.mi('unit'),'Ana duplicada','ana-link@example.invalid',null,'Visitante','active'),
 (pg_temp.mi('other'),pg_temp.mi('org'),pg_temp.mi('unit'),'Outra pessoa','outra@example.invalid','99999999999','Membro','active');
create function pg_temp.submit(d jsonb) returns jsonb language sql as $$select public.member_self_service(pg_temp.mi('org'),'submit',pg_temp.mi('unit'),d)$$;
create function pg_temp.req(u text) returns uuid language sql as $$select nullif(current_setting('t.req_'||u,true),'')::uuid$$;
create function pg_temp.keep(u text) returns text language sql as $$select set_config('t.req_'||u,(select id::text from private.member_profile_requests where organization_id=pg_temp.mi('org') and user_id=pg_temp.mi(u) and status='pending'),true)$$;
create function pg_temp.item(u text) returns jsonb language sql as $$select i from jsonb_array_elements(public.member_profile_review2(pg_temp.mi('org'),'list')->'items') i where (i->>'id')::uuid=pg_temp.req(u)$$;

set local role authenticated;
select pg_temp.actor('ana');
select lives_ok($$select pg_temp.submit('{"full_name":"Ana Souza","cpf":"12345678901","phone":"11988887777"}')$$,'com dois candidatos, o cadastro não é mais recusado');
reset role;
select pg_temp.keep('ana');
select is((select count(*)::integer from public.people where organization_id=pg_temp.mi('org') and auth_user_id=pg_temp.mi('ana')),1,'fica um cadastro provisório da própria conta');
select is((select auth_user_id from public.people where id=pg_temp.mi('ana-1')),null,'nenhum membro é ligado sem análise');
set local role authenticated;

-- Quem não tem permissão não vê a fila; com Perfis pendentes passa a ver e analisar.
select pg_temp.actor('reviewer');
select is(jsonb_array_length(public.member_profile_review2(pg_temp.mi('org'),'list')->'items'),0,'sem permissão, fila vazia');
select pg_temp.actor('owner');
select lives_ok($$select public.permission_admin(pg_temp.mi('org'),'set',jsonb_build_object('membership',pg_temp.mi('reviewer-m'),'permission','people.pending_profiles','unit',pg_temp.mi('unit'),'actions',jsonb_build_array('view','approve'),'includeChildren',false))$$,'concede Perfis pendentes');
select pg_temp.actor('reviewer');
select is(jsonb_array_length(pg_temp.item('ana')->'candidates'),3,'candidatos lado a lado: o provisório, o do CPF e o do e-mail');
select is((select c->>'cpf' from jsonb_array_elements(pg_temp.item('ana')->'candidates') c where (c->>'id')::uuid=pg_temp.mi('ana-1')),'true','indica o candidato com CPF igual');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.item('ana')->'candidates') c where (c->>'id')::uuid=pg_temp.mi('other')),'pessoa sem e-mail ou CPF igual não é candidata');
select throws_ok($$select public.member_profile_review2(pg_temp.mi('org'),'review',pg_temp.req('ana'),jsonb_build_object('fields',jsonb_build_array('full_name'),'reason','Conferido na recepção','person',pg_temp.mi('other')))$$,'40001','member_identity_conflict','não liga a quem não confere');
select throws_ok($$select public.member_profile_review2(pg_temp.mi('org'),'review',pg_temp.req('ana'),jsonb_build_object('fields',jsonb_build_array('full_name'),'reason','Conferido','journey','Líder'))$$,'22023',null,'tipo de perfil inválido recusado');
select lives_ok($$select public.member_profile_review2(pg_temp.mi('org'),'review',pg_temp.req('ana'),jsonb_build_object('fields',jsonb_build_array('full_name','phone'),'reason','CPF conferido com documento','person',pg_temp.mi('ana-1'),'journey','Membro'))$$,'liga ao membro existente, aprova campos e define o tipo');
reset role;
select is((select auth_user_id from public.people where id=pg_temp.mi('ana-1')),pg_temp.mi('ana'),'conta ligada ao membro escolhido');
select is((select full_name||'|'||phone||'|'||journey_status from public.people where id=pg_temp.mi('ana-1')),'Ana Souza|11988887777|Membro','campos aprovados e tipo de perfil aplicados');
select is((select count(*)::integer from public.people where organization_id=pg_temp.mi('org') and auth_user_id=pg_temp.mi('ana') and status<>'rejected'),1,'cadastro provisório retirado; um só vínculo');
select is((select status from public.organization_memberships where organization_id=pg_temp.mi('org') and user_id=pg_temp.mi('ana')),'active','acesso do membro liberado');
select ok(exists(select 1 from public.audit_logs where organization_id=pg_temp.mi('org') and action='member.profile.reviewed' and (metadata->>'linkedToExisting')::boolean),'decisão registrada na auditoria');

-- Novo cadastro sem candidato: aprovar cria o membro com o tipo escolhido.
set local role authenticated;
select pg_temp.actor('bia');
select lives_ok($$select pg_temp.submit('{"full_name":"Bia Nova"}')$$,'cadastro sem candidato');
reset role;
select pg_temp.keep('bia');
set local role authenticated;
select pg_temp.actor('owner');
select is(jsonb_array_length(pg_temp.item('bia')->'candidates'),1,'só o próprio cadastro provisório');
select lives_ok($$select public.member_profile_review2(pg_temp.mi('org'),'review',pg_temp.req('bia'),jsonb_build_object('fields',jsonb_build_array('full_name'),'reason','Primeira visita','journey','Visitante'))$$,'aprova como visitante');
reset role;
select is((select journey_status||'|'||status from public.people where auth_user_id=pg_temp.mi('bia')),'Visitante|active','membro criado como visitante');
select * from finish();
rollback;
