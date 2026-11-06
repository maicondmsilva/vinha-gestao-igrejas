begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.ac(t text) returns uuid language sql immutable as $$select md5('account-closure-test-'||t)::uuid$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.ac(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-close@example.invalid',now(),now(),now()
 from unnest(array['owner','member','pastor']) t;
insert into public.organizations(id,name,slug,status) values(pg_temp.ac('org'),'Ministério fictício exclusão','account-closure-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ac('unit'),pg_temp.ac('org'),'Sede fictícia','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values
 (pg_temp.ac('m-owner'),pg_temp.ac('org'),pg_temp.ac('owner'),pg_temp.ac('unit'),'owner','active'),
 (pg_temp.ac('m-member'),pg_temp.ac('org'),pg_temp.ac('member'),pg_temp.ac('unit'),'member','active'),
 (pg_temp.ac('m-pastor'),pg_temp.ac('org'),pg_temp.ac('pastor'),pg_temp.ac('unit'),'pastor','active');

-- Only the server (service role) can close an account; the app never calls the function directly.
select ok(not has_function_privilege('authenticated','public.account_close(uuid,text)','execute'),'app autenticado não executa diretamente');
select ok(not has_function_privilege('anon','public.account_close(uuid,text)','execute'),'visitante não executa');
select ok(has_function_privilege('service_role','public.account_close(uuid,text)','execute'),'servidor executa');

-- Governance: privileged roles must hand over before closing.
select is(public.account_close(pg_temp.ac('owner'),'app')->>'reason','privileged_role','dono não exclui a conta sem transferir');
select is(public.account_close(pg_temp.ac('pastor'),'app')->>'reason','privileged_role','pastor não exclui a conta sem transferir');
select is((select status::text from public.organization_memberships where id=pg_temp.ac('m-owner')),'active','vínculo do dono preservado');

-- A member closes the account: access revoked, closure recorded, repeat is harmless.
select is(public.account_close(pg_temp.ac('member'),'app')->>'ok','true','membro exclui a própria conta');
select is((select status::text from public.organization_memberships where id=pg_temp.ac('m-member')),'revoked','acesso do membro revogado');
select is((select organizations from private.account_closures where user_id=pg_temp.ac('member')),array[pg_temp.ac('org')],'registro da exclusão guarda os ministérios');
select is(public.account_close(pg_temp.ac('member'),'app')->>'ok','true','repetição é segura');
select is((select count(*)::int from private.account_closures where user_id=pg_temp.ac('member')),1,'um registro por conta');
update auth.users set deleted_at=now() where id=pg_temp.ac('member');
select is(public.account_close(pg_temp.ac('member'),'app')->>'repeated','true','conta já anonimizada responde como repetição');
select throws_ok($$select public.account_close(md5('account-closure-test-unknown')::uuid,'app')$$,'42501',null,'conta inexistente é recusada');
select throws_ok($$select public.account_close(md5('account-closure-test-owner')::uuid,'other')$$,'22023',null,'origem inválida é recusada');
select * from finish();
rollback;
