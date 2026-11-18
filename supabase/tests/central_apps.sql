-- Central › Aplicativos: liberação e personalização do app por ministério (dados sintéticos, desfeitos no fim).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
 ('f2000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','apps-owner@fixture.example.invalid','',now(),now(),now()),
 ('f2000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','apps-reader@fixture.example.invalid','',now(),now(),now()),
 ('f2000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','apps-church@fixture.example.invalid','',now(),now(),now());
insert into public.platform_operators(user_id,role,full_name,email) values
 ('f2000000-0000-4000-8000-000000000001','admin','Operador apps','apps-owner@fixture.example.invalid'),
 ('f2000000-0000-4000-8000-000000000002','read_only','Leitura apps','apps-reader@fixture.example.invalid');
insert into public.organizations(id,name,slug,status,app_name,primary_color) values
 ('f2100000-0000-4000-8000-000000000001','Igreja Árvore da Vida','apps-arvore','active','Árvore da Vida','#3d6b8c'),
 ('f2100000-0000-4000-8000-000000000002','Igreja Sem App','apps-semapp','active',null,'#285c45');
insert into public.saas_subscriptions(id,organization_id,plan_id,status,app_addon) values
 ('f2200000-0000-4000-8000-000000000001','f2100000-0000-4000-8000-000000000001','plan-essential','active',true),
 ('f2200000-0000-4000-8000-000000000002','f2100000-0000-4000-8000-000000000002','plan-essential','active',false);
create function pg_temp.as_user(id text,aal text) returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated','aal',aal)::text,true)$$;
select ok(not has_table_privilege('authenticated','private.ministry_apps','SELECT'),'apps sem leitura direta');
select ok(not has_function_privilege('anon','public.platform_apps(text,uuid,jsonb)','EXECUTE'),'apps não anônimo');
set local role authenticated;
select pg_temp.as_user('f2000000-0000-4000-8000-000000000001','aal1');
select throws_ok($$select public.platform_apps('list')$$,'42501',null,'sem segundo fator, não lista');
select pg_temp.as_user('f2000000-0000-4000-8000-000000000003','aal2');
select throws_ok($$select public.platform_apps('list')$$,'42501',null,'conta de igreja não acessa');
select pg_temp.as_user('f2000000-0000-4000-8000-000000000001','aal2');
select ok(exists(select 1 from jsonb_array_elements(public.platform_apps('list')->'apps') x where x->>'organizationId'='f2100000-0000-4000-8000-000000000001' and x->>'status'='contracted' and not (x->>'configured')::boolean),'ministério com app contratado aparece para liberar');
select ok(not exists(select 1 from jsonb_array_elements(public.platform_apps('list')->'apps') x where x->>'organizationId'='f2100000-0000-4000-8000-000000000002'),'sem contrato de app não aparece');
select is(public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":0,"status":"configuring","theme":"light"}')->'app'->>'profile','arvoredavida','perfil gerado do nome, sem acento');
select is((select app_theme from public.organizations where id='f2100000-0000-4000-8000-000000000001'),'light','tema escolhido pela Central vale para o app');
select throws_ok($$select public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":0,"status":"testing"}')$$,'40001',null,'versão antiga recusada');
select throws_ok($$select public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":1,"status":"published"}')$$,'22023','platform_apps_store_ids','publicar exige identificador de loja');
select throws_ok($$select public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":1,"androidApplicationId":"Com Errado"}')$$,'23514',null,'identificador Android validado');
select is(public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":1,"status":"published","androidApplicationId":"br.org.arvore.app","displayName":"Árvore App","built":true}')->'app'->>'status','published','publicado com identificador');
select ok(public.platform_apps('manifest')->'apps' @> '[{"profile":"arvoredavida","name":"Árvore App","theme":"light","androidApplicationId":"br.org.arvore.app"}]'::jsonb,'lista de geração traz perfil, nome, tema e loja');
select throws_ok($$select public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":2,"secret":"x"}')$$,'22023',null,'campos desconhecidos recusados');
select pg_temp.as_user('f2000000-0000-4000-8000-000000000002','aal2');
select ok(jsonb_array_length(public.platform_apps('list')->'apps')>=1,'leitura vê a lista');
select is(public.platform_apps('list')->>'canEdit','false','leitura não edita');
select throws_ok($$select public.platform_apps('save','f2100000-0000-4000-8000-000000000001','{"version":2,"status":"paused"}')$$,'42501',null,'leitura não salva');
reset role;
select ok(exists(select 1 from public.audit_logs where entity_type='ministry_app' and entity_id='f2100000-0000-4000-8000-000000000001'),'alteração registrada na auditoria');
select * from finish();
rollback;
