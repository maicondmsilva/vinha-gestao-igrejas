begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Pessoas, Programação e Comunicação com permissões concedidas na ficha do usuário (P3).
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a7600000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-people-'||i||'@example.test',now(),now(),now() from generate_series(1,2)i;
insert into public.organizations(id,name,slug,status) values('b7600000-0000-4000-8000-000000000001','Pessoas P3','p3-people-synthetic','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c7600000-0000-4000-8000-000000000001','b7600000-0000-4000-8000-000000000001','Sede pessoas','sede','headquarters'),
 ('c7600000-0000-4000-8000-000000000002','b7600000-0000-4000-8000-000000000001','Outra pessoas','outra','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7600000-0000-4000-8000-000000000001','b7600000-0000-4000-8000-000000000001','a7600000-0000-4000-8000-000000000001','owner','active','c7600000-0000-4000-8000-000000000001'),
 ('d7600000-0000-4000-8000-000000000002','b7600000-0000-4000-8000-000000000001','a7600000-0000-4000-8000-000000000002','member','active','c7600000-0000-4000-8000-000000000001');
insert into public.people(id,organization_id,unit_id,full_name,journey_status,status) values
 ('e7600000-0000-4000-8000-000000000001','b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000001','Membro fictício','Membro','active'),
 ('e7600000-0000-4000-8000-000000000002','b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000001','Visitante fictício','Visitante','active'),
 ('e7600000-0000-4000-8000-000000000003','b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000002','Membro de outra igreja','Membro','active');
create function pg_temp.as_user(i integer) returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub','a7600000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true)$$;
create function pg_temp.grant(p text,acts jsonb) returns jsonb language sql as $$select public.permission_admin('b7600000-0000-4000-8000-000000000001','set',jsonb_build_object('membership','d7600000-0000-4000-8000-000000000002','permission',p,'unit','c7600000-0000-4000-8000-000000000001','actions',acts,'includeChildren',false))$$;
create function pg_temp.seen() returns text language sql as $$select coalesce(string_agg(full_name,', ' order by full_name),'') from public.people where organization_id='b7600000-0000-4000-8000-000000000001'$$;
create function pg_temp.scope(s text) returns boolean language sql as $$select private.staff_grant('b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000001',s)$$;

set local role authenticated;
select pg_temp.as_user(2);
select is(pg_temp.seen(),'','sem permissão não vê cadastros');
select is(public.permission_any('b7600000-0000-4000-8000-000000000001',array['people.members:view']),false,'rota de Pessoas fechada sem permissão');

-- Visitantes: só os cadastros na etapa Visitante.
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('people.visitors','["view","edit"]')$$,'concede Visitantes');
select pg_temp.as_user(2);
select is(pg_temp.seen(),'Visitante fictício','Visitantes vê só visitantes');
select is(public.permission_any('b7600000-0000-4000-8000-000000000001',array['people.members:view','people.visitors:view']),true,'rota de Pessoas abre');

-- Membros: ver e editar na sede.
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('people.members','["view","edit"]')$$,'concede Membros na sede');
select pg_temp.as_user(2);
select is(pg_temp.seen(),'Membro fictício, Visitante fictício','vê os cadastros da sede, não os da outra igreja');
update public.people set phone='11999990000' where id='e7600000-0000-4000-8000-000000000001';
select is((select phone from public.people where id='e7600000-0000-4000-8000-000000000001'),'11999990000','edita cadastro com permissão');
select throws_ok($$update public.people set unit_id='c7600000-0000-4000-8000-000000000002' where id='e7600000-0000-4000-8000-000000000001'$$,'42501',null,'não move cadastro para igreja fora da permissão');
select throws_ok($$insert into public.people(organization_id,unit_id,full_name,journey_status) values('b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000001','Novo','Membro')$$,'42501',null,'sem criar, não cadastra');
reset role;
select ok(not (select private.can_view_person('e7600000-0000-4000-8000-000000000001') from (select pg_temp.as_user(2)) x),'anotações pastorais e consentimentos continuam só com a regra antiga');

set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('people.members','["view","create","edit"]')$$,'concede criar Membros');
select pg_temp.as_user(2);
select lives_ok($$insert into public.people(organization_id,unit_id,full_name,journey_status) values('b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000001','Novo membro','Membro')$$,'com criar, cadastra');
reset role;

-- Programação e Comunicação: os acessos de equipe aceitam as permissões.
select pg_temp.as_user(2);
select ok(not pg_temp.scope('agenda'),'sem permissão não gerencia a agenda');
select ok(not pg_temp.scope('publishing'),'sem permissão não publica');
set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('events.events','["view","create","edit"]')$$,'concede Eventos');
select lives_ok($$select pg_temp.grant('events.checkin','["view","edit"]')$$,'concede check-in');
select lives_ok($$select pg_temp.grant('communication.notices','["view","create","edit"]')$$,'concede Avisos');
select lives_ok($$select pg_temp.grant('communication.chat','["view","edit"]')$$,'concede moderação do chat');
reset role;
select pg_temp.as_user(2);
select ok(pg_temp.scope('agenda'),'Eventos gerencia a programação');
select ok(pg_temp.scope('checkin'),'check-in opera inscrições');
select ok(pg_temp.scope('publishing'),'Avisos publica');
select ok(not pg_temp.scope('push'),'Avisos não envia push');
select ok(private.chat_unit_moderator('b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000001'),'modera o chat da igreja');
select ok(not private.staff_grant('b7600000-0000-4000-8000-000000000001','c7600000-0000-4000-8000-000000000002','agenda'),'fora da igreja concedida, nada');
select * from finish();
rollback;
