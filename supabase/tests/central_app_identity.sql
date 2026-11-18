-- Identidade do app (nome, cores, logo, abertura, ícone) só pela Central da Vinha (dados sintéticos, desfeitos no fim).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
 ('f3000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','id-admin@fixture.example.invalid','',now(),now(),now()),
 ('f3000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','id-reader@fixture.example.invalid','',now(),now(),now()),
 ('f3000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','id-church@fixture.example.invalid','',now(),now(),now());
insert into public.platform_operators(user_id,role,full_name,email) values
 ('f3000000-0000-4000-8000-000000000001','admin','Operador identidade','id-admin@fixture.example.invalid'),
 ('f3000000-0000-4000-8000-000000000002','read_only','Leitura identidade','id-reader@fixture.example.invalid');
insert into public.organizations(id,name,slug,status,app_name,primary_color) values
 ('f3100000-0000-4000-8000-000000000001','Igreja Identidade','id-igreja','active','Igreja App','#285c45');
insert into public.organization_memberships(organization_id,user_id,role,status) values
 ('f3100000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000003','owner','active');
create function pg_temp.as_user(id text,aal text) returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated','aal',aal)::text,true)$$;
-- PNG 1x1 válido.
create function pg_temp.png() returns text language sql as $$select 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='$$;

select ok(not has_function_privilege('anon','public.platform_app_identity(text,uuid,jsonb)','EXECUTE'),'identidade não anônima');
select ok((select public from storage.buckets where id='vinha-app-assets'),'arquivos do app públicos para leitura');
select ok(not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and qual ilike '%vinha-app-assets%'),'sem política de gravação para contas: só o servidor envia');

set local role authenticated;
select pg_temp.as_user('f3000000-0000-4000-8000-000000000001','aal1');
select throws_ok($$select public.platform_app_identity('get','f3100000-0000-4000-8000-000000000001')$$,'42501',null,'sem segundo fator, não lê');
select pg_temp.as_user('f3000000-0000-4000-8000-000000000003','aal2');
select throws_ok($$select public.platform_app_identity('get','f3100000-0000-4000-8000-000000000001')$$,'42501',null,'conta da igreja não usa a Central');

select pg_temp.as_user('f3000000-0000-4000-8000-000000000001','aal2');
select is(public.platform_app_identity('get','f3100000-0000-4000-8000-000000000001')->>'appName','Igreja App','Central lê a identidade');
select is(public.platform_app_identity('identity','f3100000-0000-4000-8000-000000000001',
 jsonb_build_object('appName','Igreja Viva','primaryColor','#3D6B8C','accentColor','#d8b769','updatedAt',(select updated_at from public.organizations where id='f3100000-0000-4000-8000-000000000001')))->>'primaryColor','#3d6b8c','Central salva nome e cores');
select is((select app_name from public.organizations where id='f3100000-0000-4000-8000-000000000001'),'Igreja Viva','nome do app gravado');
select throws_ok($$select public.platform_app_identity('identity','f3100000-0000-4000-8000-000000000001','{"appName":"X App","primaryColor":"#000000","accentColor":"#ffffff","updatedAt":"2000-01-01T00:00:00Z"}')$$,'40001',null,'versão antiga recusada');
select throws_ok($$select public.platform_app_identity('identity','f3100000-0000-4000-8000-000000000001','{"appName":"X App","primaryColor":"red","accentColor":"#ffffff","updatedAt":"2000-01-01T00:00:00Z"}')$$,'22023',null,'cor inválida recusada');
select ok(public.platform_app_identity('logo','f3100000-0000-4000-8000-000000000001',jsonb_build_object('logo',pg_temp.png()))->>'logo' like 'data:image/png;base64,%','Central envia a logo do ministério');
select throws_ok($$select public.platform_app_identity('logo','f3100000-0000-4000-8000-000000000001','{"logo":"data:image/png;base64,AAAA"}')$$,'22023',null,'logo inválida recusada');
select is(public.platform_app_identity('opening','f3100000-0000-4000-8000-000000000001','{"kind":"image","url":"https://exemplo.supabase.co/storage/v1/object/public/vinha-app-assets/a.jpg","title":"Bem-vindo","seconds":5,"version":0}')->'opening'->>'kind','image','Central define a foto de abertura');
select is(public.member_app_opening('f3100000-0000-4000-8000-000000000001')->>'title','Bem-vindo','o app recebe a abertura');
select throws_ok($$select public.platform_app_identity('opening','f3100000-0000-4000-8000-000000000001','{"kind":"video","url":"https://exemplo.com/v.mov","title":"","seconds":5,"version":1}')$$,'22023',null,'vídeo de abertura só MP4');
select throws_ok($$select public.platform_app_identity('opening','f3100000-0000-4000-8000-000000000001','{"kind":"none","url":"","title":"","seconds":5,"version":0}')$$,'40001',null,'abertura com versão antiga recusada');
select throws_ok($$select public.platform_app_identity('icon','f3100000-0000-4000-8000-000000000001','{"url":null}')$$,'22023','app_not_released','ícone só depois de liberar o app');
select is(public.platform_apps('save','f3100000-0000-4000-8000-000000000001','{"version":0,"status":"configuring"}')->'app'->>'status','configuring','app liberado');
select throws_ok($$select public.platform_app_identity('icon','f3100000-0000-4000-8000-000000000001','{"url":"https://outro.site/icone.png"}')$$,'23514',null,'ícone só dos arquivos do app');
select is(public.platform_app_identity('icon','f3100000-0000-4000-8000-000000000001',
 '{"url":"https://abcdefgh.supabase.co/storage/v1/object/public/vinha-app-assets/f3100000-0000-4000-8000-000000000001/icon-0b9f4c3a-1d2e-4f5a-8b6c-7d8e9f0a1b2c.png"}')->>'iconUrl' like '%/icon-0b9f4c3a%',true,'Central define o ícone');
select ok(public.platform_apps('manifest')->'apps' @> '[{"iconUrl":"https://abcdefgh.supabase.co/storage/v1/object/public/vinha-app-assets/f3100000-0000-4000-8000-000000000001/icon-0b9f4c3a-1d2e-4f5a-8b6c-7d8e9f0a1b2c.png"}]'::jsonb,'robô recebe o ícone');
select pg_temp.as_user('f3000000-0000-4000-8000-000000000002','aal2');
select is(public.platform_app_identity('get','f3100000-0000-4000-8000-000000000001')->>'canEdit','false','leitura não edita');
select throws_ok($$select public.platform_app_identity('logo','f3100000-0000-4000-8000-000000000001','{"logo":""}')$$,'42501',null,'leitura não salva');

-- Painel e cadastro inicial não alteram mais a identidade do app.
select pg_temp.as_user('f3000000-0000-4000-8000-000000000003','aal1');
select throws_ok($$select public.organization_settings_save('f3100000-0000-4000-8000-000000000001',null,jsonb_build_object('updatedAt',(select updated_at from public.organizations where id='f3100000-0000-4000-8000-000000000001'),'name','Igreja Identidade','seniorPastorName','Pr. Teste','appName','Outro','primaryColor','#000000','accentColor','#ffffff'))$$,'22023',null,'painel não troca nome do app nem cores');
reset role;
select throws_ok($$select private.save_church_brand('f3100000-0000-4000-8000-000000000001',null,'')$$,'42501','identity_managed_by_vinha','painel não troca a logo do ministério');
select ok(position('opening_managed_by_vinha' in pg_get_functiondef('private.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure))>0,'painel não troca a abertura');
select ok(position('appName' in pg_get_functiondef('public.save_organization_onboarding(uuid,jsonb)'::regprocedure))=0 and position('save_church_brand' in pg_get_functiondef('public.save_organization_onboarding(uuid,jsonb)'::regprocedure))=0,'cadastro inicial sem nome do app, cores e logo');
select ok(exists(select 1 from public.audit_logs where organization_id='f3100000-0000-4000-8000-000000000001' and action='platform.app_identity.logo'),'alterações auditadas');
select * from finish();
rollback;
