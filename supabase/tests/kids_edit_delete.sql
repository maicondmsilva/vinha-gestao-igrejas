begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.ki(t text) returns uuid language sql immutable as $$select md5('kids-edit-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.ki(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-ed@example.invalid',now(),now(),now() from unnest(array['owner','teacher','reception','other','teacher2']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.ki('org'),'Kids K2 fictício','kids-ed-test','active'),(pg_temp.ki('foreign'),'Outro fictício','kids-ed-other','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ki('unit'),pg_temp.ki('org'),'Sede fictícia K2','sede','headquarters'),(pg_temp.ki('otherunit'),pg_temp.ki('org'),'Filial fictícia','filial','campus'),(pg_temp.ki('foreignunit'),pg_temp.ki('foreign'),'Outra','outra','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
select pg_temp.ki(x||'-membership'),pg_temp.ki('org'),pg_temp.ki(x),case when x='owner' then 'owner'::public.membership_role else 'member'::public.membership_role end,'active',pg_temp.ki('unit') from unnest(array['owner','teacher','reception','other','teacher2']) x;
insert into public.membership_unit_access(membership_id,unit_id,access_level) select pg_temp.ki(x||'-membership'),pg_temp.ki('unit'),'read' from unnest(array['teacher','reception','teacher2']) x;
insert into public.people(id,organization_id,unit_id,full_name,birth_date,status,auth_user_id)
select pg_temp.ki(x||'-person'),pg_temp.ki('org'),pg_temp.ki('unit'),x||' pessoa fictícia',current_date-interval '35 years','active',pg_temp.ki(x) from unnest(array['owner','teacher','reception','teacher2']) x;
create function pg_temp.op(a text,i text,v integer,d jsonb) returns jsonb language sql as $$select public.kids_operations_save(pg_temp.ki('org'),pg_temp.ki('unit'),extensions.gen_random_uuid(),a,pg_temp.ki(i),v,d)$$;
create function pg_temp.setup(a text,d jsonb default '{}') returns jsonb language sql as $$select public.kids_setup(pg_temp.ki('org'),pg_temp.ki('unit'),a,d)$$;
create function pg_temp.has(t text,i text) returns boolean language plpgsql security definer as $$declare r boolean;begin execute format('select exists(select 1 from private.%I where id=$1)',t) into r using pg_temp.ki(i);return r;end$$;
-- Sessões de teste com uma sala montada.
insert into private.kids_rooms(id,organization_id,unit_id,name,location,capacity,active) values(pg_temp.ki('room'),pg_temp.ki('org'),pg_temp.ki('unit'),'Sala Azul','',10,true),(pg_temp.ki('spare'),pg_temp.ki('org'),pg_temp.ki('unit'),'Sala Extra','',10,true);
insert into private.kids_classes(id,organization_id,unit_id,name,min_months,max_months,active) values(pg_temp.ki('class'),pg_temp.ki('org'),pg_temp.ki('unit'),'Crianças',36,143,true),(pg_temp.ki('class2'),pg_temp.ki('org'),pg_temp.ki('unit'),'Bebês',0,35,true);
insert into private.kids_session_series(id,organization_id,unit_id,name,rule,weekdays,starts_time,duration_minutes,valid_from,open_before_hours,rooms,created_by)
 values(pg_temp.ki('serie'),pg_temp.ki('org'),pg_temp.ki('unit'),'Domingo','weekly','{0}','09:00',90,current_date,24,jsonb_build_array(jsonb_build_object('roomId',pg_temp.ki('spare')::text,'classId',pg_temp.ki('class2')::text)),pg_temp.ki('owner'));
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,created_by,series_id) values
 (pg_temp.ki('used'),pg_temp.ki('org'),pg_temp.ki('unit'),'Sessão com entrada',now()+interval '1 day',now()+interval '26 hours',pg_temp.ki('owner'),null),
 (pg_temp.ki('empty'),pg_temp.ki('org'),pg_temp.ki('unit'),'Sessão vazia',now()+interval '2 days',now()+interval '50 hours',pg_temp.ki('owner'),pg_temp.ki('serie'));
insert into private.kids_session_rooms(id,organization_id,unit_id,session_id,room_id,class_id,capacity) values
 (pg_temp.ki('g1'),pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('used'),pg_temp.ki('room'),pg_temp.ki('class'),10),
 (pg_temp.ki('g2'),pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('empty'),pg_temp.ki('spare'),pg_temp.ki('class2'),10);
insert into private.kids_custody_events(organization_id,unit_id,session_id,actor_id,action,entity_id) values(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('used'),pg_temp.ki('owner'),'checkin',pg_temp.ki('g1'));
set local role authenticated;
select pg_temp.actor('teacher');
select throws_ok($$select pg_temp.setup('room_delete',jsonb_build_object('id',pg_temp.ki('spare')))$$,'42501','kids_access_denied','sem permissão não exclui');
select pg_temp.actor('owner');
select is((select x->>'locked' from jsonb_array_elements(pg_temp.setup('overview')->'rooms') x where x->>'id'=pg_temp.ki('room')::text),'true','sala com lançamento aparece travada');
select is((select x->>'locked' from jsonb_array_elements(pg_temp.setup('overview')->'rooms') x where x->>'id'=pg_temp.ki('spare')::text),'false','sala sem lançamento pode excluir');
select is((select x->>'locked' from jsonb_array_elements(pg_temp.setup('overview')->'sessions') x where x->>'id'=pg_temp.ki('used')::text),'true','sessão com lançamento aparece travada');
select throws_ok($$select pg_temp.setup('room_delete',jsonb_build_object('id',pg_temp.ki('room')))$$,'40001','kids_has_records','sala com histórico não é excluída');
select throws_ok($$select pg_temp.setup('class_delete',jsonb_build_object('id',pg_temp.ki('class')))$$,'40001','kids_has_records','turma com histórico não é excluída');
select throws_ok($$select pg_temp.setup('session_delete',jsonb_build_object('id',pg_temp.ki('used')))$$,'40001','kids_has_records','sessão com histórico não é excluída');
select lives_ok($$select pg_temp.op('room','room',1,'{"name":"Sala Azul Clara","location":"Térreo","capacity":12,"active":false}')$$,'sala com histórico pode ser editada e desativada');
select lives_ok($$select pg_temp.setup('session_delete',jsonb_build_object('id',pg_temp.ki('empty')))$$,'sessão sem lançamentos é excluída');
reset role;
select ok(not pg_temp.has('kids_sessions','empty') and not pg_temp.has('kids_session_rooms','g2'),'sessão e salas montadas saem juntas');
select ok((select array_length(skip_dates,1)=1 from private.kids_session_series where id=pg_temp.ki('serie')),'data pulada na repetição para não recriar');
select pg_temp.actor('owner');set local role authenticated;
select lives_ok($$select pg_temp.setup('room_delete',jsonb_build_object('id',pg_temp.ki('spare')))$$,'sala sem lançamentos é excluída');
select lives_ok($$select pg_temp.setup('class_delete',jsonb_build_object('id',pg_temp.ki('class2')))$$,'turma sem lançamentos é excluída');
reset role;
select ok(not pg_temp.has('kids_rooms','spare') and not pg_temp.has('kids_classes','class2'),'sala e turma removidas');
select is((select jsonb_array_length(rooms) from private.kids_session_series where id=pg_temp.ki('serie')),0,'repetição deixa de usar a sala excluída');
select ok(pg_temp.has('kids_sessions','used') and pg_temp.has('kids_rooms','room') and exists(select 1 from private.kids_custody_events where session_id=pg_temp.ki('used')),'histórico preservado');
select * from finish();
rollback;
