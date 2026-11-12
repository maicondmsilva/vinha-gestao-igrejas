begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Kids com permissões concedidas na ficha do usuário (P3/P4), limitadas a turmas.
create function pg_temp.ki(t text) returns uuid language sql immutable as $$select md5('kids-perm-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.ki(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-kperm@example.invalid',now(),now(),now() from unnest(array['owner','helper']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.ki('org'),'Kids permissões fictício','kids-perm-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ki('unit'),pg_temp.ki('org'),'Sede Kids perm','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.ki('owner-m'),pg_temp.ki('org'),pg_temp.ki('owner'),'owner','active',pg_temp.ki('unit')),
 (pg_temp.ki('helper-m'),pg_temp.ki('org'),pg_temp.ki('helper'),'member','active',pg_temp.ki('unit'));
create function pg_temp.op(a text,i text,d jsonb) returns jsonb language sql as $$select public.kids_operations_save(pg_temp.ki('org'),pg_temp.ki('unit'),extensions.gen_random_uuid(),a,pg_temp.ki(i),0,d)$$;
create function pg_temp.grant(p text,acts jsonb,extra jsonb default '{}') returns jsonb language sql as $$select public.permission_admin(pg_temp.ki('org'),'set',jsonb_build_object('membership',pg_temp.ki('helper-m'),'permission',p,'unit',pg_temp.ki('unit'),'actions',acts,'includeChildren',false)||extra)$$;
create function pg_temp.op_ok(mode text,grp text default null) returns boolean language sql as $$select private.kids_op_allowed(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),mode,case when grp is null then null else pg_temp.ki(grp) end)$$;
create function pg_temp.kids_ok(mode text) returns boolean language sql as $$select private.kids_allowed(pg_temp.ki('org'),pg_temp.ki('unit'),mode)$$;

select ok(exists(select 1 from private.permission_catalog where code='kids.children' and 'approve'=any(actions)),'catálogo tem Crianças e responsáveis');

set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.op('room','room-a','{"name":"Sala A","location":"Térreo","capacity":5,"active":true}')$$,'cria sala A');
select lives_ok($$select pg_temp.op('room','room-b','{"name":"Sala B","location":"Térreo","capacity":5,"active":true}')$$,'cria sala B');
select lives_ok($$select pg_temp.op('class','class-a','{"name":"Pequenos","minMonths":24,"maxMonths":59,"active":true}')$$,'cria turma A');
select lives_ok($$select pg_temp.op('class','class-b','{"name":"Grandes","minMonths":60,"maxMonths":143,"active":true}')$$,'cria turma B');
select lives_ok($$select pg_temp.op('session','session',jsonb_build_object('name','Culto','startsAt',now()-interval '5 minutes','endsAt',now()+interval '2 hours'))$$,'cria sessão');
select lives_ok($$select pg_temp.op('group','group-a',jsonb_build_object('sessionId',pg_temp.ki('session'),'roomId',pg_temp.ki('room-a'),'classId',pg_temp.ki('class-a'),'capacity',5,'minStaff',1))$$,'sala da turma A');
select lives_ok($$select pg_temp.op('group','group-b',jsonb_build_object('sessionId',pg_temp.ki('session'),'roomId',pg_temp.ki('room-b'),'classId',pg_temp.ki('class-b'),'capacity',5,'minStaff',1))$$,'sala da turma B');
reset role;

-- Sem permissão: nada.
select pg_temp.actor('helper');
select ok(not pg_temp.op_ok('receive','group-a'),'sem permissão não recebe crianças');
select ok(not pg_temp.kids_ok('read'),'sem permissão não vê crianças');

-- Check-in limitado à turma A.
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.grant('kids.checkin','["view","edit"]',jsonb_build_object('groupKind','kids_class','groups',jsonb_build_array(pg_temp.ki('class-a'))))$$,'concede check-in só da turma A');
select pg_temp.actor('helper');
select ok(pg_temp.op_ok('receive','group-a'),'recebe na sala da turma A');
select ok(pg_temp.op_ok('accept','group-a'),'aceita na sala da turma A');
select ok(not pg_temp.op_ok('accept','group-b'),'não aceita na sala da turma B');
select ok(pg_temp.op_ok('read','group-a'),'vê a sala da turma A');
select ok(not pg_temp.op_ok('read','group-b'),'não vê a sala da turma B');
select ok(not pg_temp.op_ok('configure'),'check-in não configura sessões');
select ok(not pg_temp.op_ok('supervise','group-a'),'check-in não coordena a sala');
select ok(not pg_temp.kids_ok('read'),'check-in não abre o cadastro de crianças');

-- Crianças e responsáveis: ver.
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.grant('kids.children','["view"]')$$,'concede ver crianças');
select pg_temp.actor('helper');
select ok(pg_temp.kids_ok('read'),'vê crianças e responsáveis');
select ok(not pg_temp.kids_ok('write'),'só ver não cadastra');
select ok(not pg_temp.kids_ok('approve'),'só ver não aprova responsáveis');
select ok(not pg_temp.kids_ok('care'),'informações de cuidado continuam fechadas');
set local role authenticated;
select lives_ok($$select public.kids_directory(pg_temp.ki('org'),pg_temp.ki('unit'),null,null,'')$$,'abre o cadastro pela tela');
reset role;

-- Turmas e salas: criar (sem limite) configura; ocorrências aprovar libera cuidado.
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.grant('kids.classes','["view","create","edit"]')$$,'concede turmas e salas');
select lives_ok($$select pg_temp.grant('kids.incidents','["view","approve"]')$$,'concede cuidados');
select pg_temp.actor('helper');
select ok(pg_temp.op_ok('configure'),'configura sessões e salas');
select ok(pg_temp.op_ok('supervise','group-b'),'coordena qualquer sala');
select ok(pg_temp.kids_ok('care'),'vê informações de cuidado');
select * from finish();
rollback;
