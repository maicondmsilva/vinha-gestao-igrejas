begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Escalas com permissões concedidas na ficha do usuário (P3/P4).
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a7400000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-scale-'||i||'@example.test',now(),now(),now() from generate_series(1,2)i;
insert into public.organizations(id,name,slug,status) values('b7400000-0000-4000-8000-000000000001','Escalas P3','p3-scale-synthetic','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c7400000-0000-4000-8000-000000000001','b7400000-0000-4000-8000-000000000001','Sede escalas','sede','headquarters'),
 ('c7400000-0000-4000-8000-000000000002','b7400000-0000-4000-8000-000000000001','Outra escalas','outra','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7400000-0000-4000-8000-000000000001','b7400000-0000-4000-8000-000000000001','a7400000-0000-4000-8000-000000000001','owner','active','c7400000-0000-4000-8000-000000000001'),
 ('d7400000-0000-4000-8000-000000000002','b7400000-0000-4000-8000-000000000001','a7400000-0000-4000-8000-000000000002','member','active','c7400000-0000-4000-8000-000000000001');
create function pg_temp.sc(a text,d jsonb default '{}',u uuid default 'c7400000-0000-4000-8000-000000000001') returns jsonb language sql as $$select public.scale_foundation('b7400000-0000-4000-8000-000000000001',u,a,case when a in('team','role','member','grant') then jsonb_build_object('request',extensions.gen_random_uuid(),'version',0,'active',true)||d else d end)$$;
create function pg_temp.grant(p text,acts jsonb,extra jsonb default '{}') returns jsonb language sql as $$select public.permission_admin('b7400000-0000-4000-8000-000000000001','set',jsonb_build_object('membership','d7400000-0000-4000-8000-000000000002','permission',p,'unit','c7400000-0000-4000-8000-000000000001','actions',acts,'includeChildren',false)||extra)$$;
create function pg_temp.as_user(i integer) returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub','a7400000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true)$$;

select ok(not has_function_privilege('authenticated','private.scale_foundation_before_permissions(uuid,uuid,text,jsonb)','execute'),'entrada antiga de equipes não é chamada direto');
select ok(not has_function_privilege('authenticated','private.can_in(uuid,uuid,text,text,uuid[])','execute'),'regra com grupos não é exposta');

set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.sc('team','{"id":"f7400000-0000-4000-8000-000000000001","name":"Recepção"}')$$,'dono cria equipe Recepção');
select lives_ok($$select pg_temp.sc('team','{"id":"f7400000-0000-4000-8000-000000000002","name":"Louvor"}')$$,'dono cria equipe Louvor');

select pg_temp.as_user(2);
select throws_ok($$select pg_temp.sc('list')$$,'42501',null,'membro sem permissão não vê Escalas');

-- Equipes: ver e editar, limitado à Recepção.
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('scales.teams','["view","edit"]','{"groupKind":"scale_team","groups":["f7400000-0000-4000-8000-000000000001"]}')$$,'concede Equipes limitado à Recepção');
select pg_temp.as_user(2);
select is(pg_temp.sc('list')->>'total','1','vê só a equipe concedida');
select lives_ok($$select pg_temp.sc('detail','{"team":"f7400000-0000-4000-8000-000000000001"}')$$,'abre a equipe concedida');
select throws_ok($$select pg_temp.sc('detail','{"team":"f7400000-0000-4000-8000-000000000002"}')$$,'42501',null,'outra equipe continua fechada');
select lives_ok($$select pg_temp.sc('role','{"id":"f7410000-0000-4000-8000-000000000001","team":"f7400000-0000-4000-8000-000000000001","name":"Acolhimento"}')$$,'edita funções da equipe concedida');
select throws_ok($$select pg_temp.sc('role','{"id":"f7410000-0000-4000-8000-000000000002","team":"f7400000-0000-4000-8000-000000000002","name":"Vocal"}')$$,'42501',null,'não edita a equipe não concedida');
select throws_ok($$select pg_temp.sc('team','{"id":"f7400000-0000-4000-8000-000000000003","name":"Mídia"}')$$,'42501',null,'sem criar, não cria equipe');
select is(pg_temp.sc('list')->>'canCreate','false','tela não oferece Nova equipe sem criar');
select throws_ok($$select pg_temp.sc('list','{}','c7400000-0000-4000-8000-000000000002')$$,'42501',null,'fora da igreja concedida');
select throws_ok($$select public.scale_planning('b7400000-0000-4000-8000-000000000001','c7400000-0000-4000-8000-000000000001','choices','{}')$$,'42501',null,'Equipes não abre Escalas e substituições');

-- Criar sem limite de grupo.
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('scales.teams','["view","create","edit"]')$$,'concede Equipes completo');
select pg_temp.as_user(2);
select lives_ok($$select pg_temp.sc('team','{"id":"f7400000-0000-4000-8000-000000000003","name":"Mídia"}')$$,'com criar, cria equipe');
select is(pg_temp.sc('list')->>'total','3','sem limite, vê todas as equipes');
select is(pg_temp.sc('list')->>'canCreate','true','tela oferece Nova equipe');
select is(pg_temp.sc('detail','{"team":"f7400000-0000-4000-8000-000000000001"}')->'grants','[]'::jsonb,'acessos antigos por equipe continuam só com o administrador');

-- Escalas e substituições: ver.
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('scales.schedules','["view"]')$$,'concede ver escalas');
select pg_temp.as_user(2);
select lives_ok($$select public.scale_planning('b7400000-0000-4000-8000-000000000001','c7400000-0000-4000-8000-000000000001','choices','{}')$$,'vê as escalas');
select is(current_setting('vinha.scale_ctx',true),'','contexto não vaza para a próxima chamada');
reset role;
select * from finish();
rollback;
