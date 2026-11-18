-- Kids: desativar sala/turma e arquivar sessão quando há registros (dados sintéticos, desfeitos no fim).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.kd(t text) returns uuid language sql immutable as $$select md5('kids-desativar-test-'||t)::uuid$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 (pg_temp.kd('owner'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','kd-owner@example.invalid',now(),now(),now()),
 (pg_temp.kd('member'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','kd-member@example.invalid',now(),now(),now());
insert into public.organizations(id,name,slug,status) values(pg_temp.kd('org'),'Kids Desativar fictício','kids-desativar-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.kd('unit'),pg_temp.kd('org'),'Sede KD','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.kd('m1'),pg_temp.kd('org'),pg_temp.kd('owner'),'owner','active',pg_temp.kd('unit')),
 (pg_temp.kd('m2'),pg_temp.kd('org'),pg_temp.kd('member'),'member','active',pg_temp.kd('unit'));
insert into private.kids_rooms(id,organization_id,unit_id,name,location,capacity) values
 (pg_temp.kd('room'),pg_temp.kd('org'),pg_temp.kd('unit'),'Sala A','',20),(pg_temp.kd('room2'),pg_temp.kd('org'),pg_temp.kd('unit'),'Sala B','',20);
insert into private.kids_classes(id,organization_id,unit_id,name,min_months,max_months) values(pg_temp.kd('class'),pg_temp.kd('org'),pg_temp.kd('unit'),'Turma A',0,71);
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,status,created_by) values
 (pg_temp.kd('draft'),pg_temp.kd('org'),pg_temp.kd('unit'),'Próximo culto',now()+interval '1 day',now()+interval '1 day 2 hours','draft',pg_temp.kd('owner')),
 (pg_temp.kd('open'),pg_temp.kd('org'),pg_temp.kd('unit'),'Culto agora',now()-interval '10 minutes',now()+interval '2 hours','open',pg_temp.kd('owner')),
 (pg_temp.kd('closed'),pg_temp.kd('org'),pg_temp.kd('unit'),'Culto passado',now()-interval '7 days',now()-interval '7 days'+interval '2 hours','closed',pg_temp.kd('owner'));
insert into private.kids_session_rooms(id,organization_id,unit_id,session_id,room_id,class_id,capacity,min_staff) values
 (pg_temp.kd('g1'),pg_temp.kd('org'),pg_temp.kd('unit'),pg_temp.kd('draft'),pg_temp.kd('room'),pg_temp.kd('class'),20,1),
 (pg_temp.kd('g2'),pg_temp.kd('org'),pg_temp.kd('unit'),pg_temp.kd('open'),pg_temp.kd('room2'),pg_temp.kd('class'),20,1);
create function pg_temp.setup(a text,id text) returns jsonb language sql as $$select public.kids_setup(pg_temp.kd('org'),pg_temp.kd('unit'),a,jsonb_build_object('id',pg_temp.kd(id)))$$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.kd('member'),'role','authenticated')::text,true);
select throws_ok($$select pg_temp.setup('room_deactivate','room')$$,'42501',null,'quem não configura não desativa');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.kd('owner'),'role','authenticated')::text,true);
select is(pg_temp.setup('room_deactivate','room')->>'deactivated','true','sala desativada');
reset role;
select ok(not (select active from private.kids_rooms where id=pg_temp.kd('room')),'sala fica inativa');
select ok(not exists(select 1 from private.kids_session_rooms where id=pg_temp.kd('g1')),'sai da próxima data em preparação');
set local role authenticated;
select throws_ok($$select pg_temp.setup('room_deactivate','room2')$$,'40001','kids_in_open_session','sala em sessão aberta: encerre antes');
select throws_ok($$select pg_temp.setup('class_deactivate','class')$$,'40001','kids_in_open_session','turma em sessão aberta: encerre antes');
select throws_ok($$select pg_temp.setup('session_archive','open')$$,'40001','kids_session_open','sessão aberta não é arquivada');
select is(pg_temp.setup('session_archive','draft')->>'ok','true','sessão em preparação arquivada');
select is(pg_temp.setup('session_archive','closed')->>'ok','true','sessão encerrada arquivada');
reset role;
select is((select status from private.kids_sessions where id=pg_temp.kd('draft')),'cancelled','em preparação vira cancelada');
select is((select status from private.kids_sessions where id=pg_temp.kd('closed')),'closed','encerrada mantém a situação (histórico)');
set local role authenticated;
select ok(not exists(select 1 from jsonb_array_elements(public.kids_operations_page(pg_temp.kd('org'),pg_temp.kd('unit'),null,null,'','all')->'sessions') x
 where x->>'id' in(pg_temp.kd('draft')::text,pg_temp.kd('closed')::text)),'arquivadas saem da lista da página Hoje');
reset role;
select ok(exists(select 1 from public.audit_logs where organization_id=pg_temp.kd('org') and action='kids.session_archive'),'auditado');
select * from finish();
rollback;
