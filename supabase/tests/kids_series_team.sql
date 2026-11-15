begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.ki(t text) returns uuid language sql immutable as $$select md5('kids-series-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.ki(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-ks@example.invalid',now(),now(),now() from unnest(array['owner','teacher','reception','other','teacher2']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.ki('org'),'Kids K2 fictício','kids-ks-test','active'),(pg_temp.ki('foreign'),'Outro fictício','kids-ks-other','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ki('unit'),pg_temp.ki('org'),'Sede fictícia K2','sede','headquarters'),(pg_temp.ki('otherunit'),pg_temp.ki('org'),'Filial fictícia','filial','campus'),(pg_temp.ki('foreignunit'),pg_temp.ki('foreign'),'Outra','outra','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
select pg_temp.ki(x||'-membership'),pg_temp.ki('org'),pg_temp.ki(x),case when x='owner' then 'owner'::public.membership_role else 'member'::public.membership_role end,'active',pg_temp.ki('unit') from unnest(array['owner','teacher','reception','other','teacher2']) x;
insert into public.membership_unit_access(membership_id,unit_id,access_level) select pg_temp.ki(x||'-membership'),pg_temp.ki('unit'),'read' from unnest(array['teacher','reception','teacher2']) x;
insert into public.people(id,organization_id,unit_id,full_name,birth_date,status,auth_user_id)
select pg_temp.ki(x||'-person'),pg_temp.ki('org'),pg_temp.ki('unit'),x||' pessoa fictícia',current_date-interval '35 years','active',pg_temp.ki(x) from unnest(array['owner','teacher','reception','teacher2']) x;
insert into public.people(id,organization_id,unit_id,full_name,birth_date,status) values
(pg_temp.ki('child'),pg_temp.ki('org'),pg_temp.ki('unit'),'Criança K2 fictícia',current_date-interval '7 years','active'),
(pg_temp.ki('child2'),pg_temp.ki('org'),pg_temp.ki('unit'),'Criança K2 segunda',current_date-interval '8 years','active'),
(pg_temp.ki('adult'),pg_temp.ki('org'),pg_temp.ki('unit'),'Adulto autorizado fictício',current_date-interval '38 years','active');
insert into private.kids_profiles(id,organization_id,unit_id,person_id,review_status,created_by) select pg_temp.ki(x||'-profile'),pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki(x),'approved',pg_temp.ki('owner') from unnest(array['child','child2']) x;
insert into private.kids_guardians(id,organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,status,approved_by,approved_at,created_by) select pg_temp.ki(x||'-guardian'),pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki(x||'-profile'),pg_temp.ki('adult'),'Responsável','Conferido em teste fictício',true,'approved',pg_temp.ki('owner'),now(),pg_temp.ki('owner') from unnest(array['child','child2']) x;
create function pg_temp.op(a text,i text,v integer,d jsonb) returns jsonb language sql as $$select public.kids_operations_save(pg_temp.ki('org'),pg_temp.ki('unit'),extensions.gen_random_uuid(),a,pg_temp.ki(i),v,d)$$;
create function pg_temp.setup(a text,d jsonb default '{}') returns jsonb language sql as $$select public.kids_setup(pg_temp.ki('org'),pg_temp.ki('unit'),a,d)$$;
create function pg_temp.in3h() returns text language sql security definer as $$select to_char((now() at time zone private.unit_timezone(pg_temp.ki('unit')))+interval '3 hours','HH24:MI')$$;
create function pg_temp.first_session() returns uuid language sql security definer as $$select id from private.kids_sessions where series_id=md5('kids-series-test-serie')::uuid order by starts_at limit 1$$;
create function pg_temp.sess() returns int language sql security definer as $$select count(*)::int from private.kids_sessions where series_id=md5('kids-series-test-serie')::uuid$$;
select ok(not has_function_privilege('anon','public.kids_setup(uuid,uuid,text,jsonb)','execute'),'visitante não configura');
-- Regras de repetição (sem login).
select ok(private.kids_series_matches(row(gen_random_uuid(),pg_temp.ki('org'),pg_temp.ki('unit'),'Culto','weekly','{0}',null,null,'09:00',90,'2026-01-01',null,24,'[]',true,'{}',true,1,null,now(),1,false)::private.kids_session_series,'2026-11-15'),'domingo cai na repetição de domingo');
select ok(not private.kids_series_matches(row(gen_random_uuid(),pg_temp.ki('org'),pg_temp.ki('unit'),'Culto','weekly','{0}',null,null,'09:00',90,'2026-01-01',null,24,'[]',true,'{}',true,1,null,now(),1,false)::private.kids_session_series,'2026-11-16'),'segunda não cai');
select ok(private.kids_series_matches(row(gen_random_uuid(),pg_temp.ki('org'),pg_temp.ki('unit'),'Culto','monthly_week','{6}',null,1,'09:00',90,'2026-01-01',null,24,'[]',true,'{}',true,1,null,now(),1,false)::private.kids_session_series,'2026-11-07'),'1º sábado do mês');
select ok(not private.kids_series_matches(row(gen_random_uuid(),pg_temp.ki('org'),pg_temp.ki('unit'),'Culto','monthly_week','{6}',null,1,'09:00',90,'2026-01-01',null,24,'[]',true,'{}',true,1,null,now(),1,false)::private.kids_session_series,'2026-11-14'),'2º sábado não');
select ok(private.kids_series_matches(row(gen_random_uuid(),pg_temp.ki('org'),pg_temp.ki('unit'),'Culto','monthly_day','{}',31,null,'09:00',90,'2026-01-01',null,24,'[]',true,'{}',true,1,null,now(),1,false)::private.kids_session_series,'2026-11-30'),'dia 31 vira o último dia em meses curtos');
set local role authenticated;
select pg_temp.actor('teacher');
select throws_ok($$select pg_temp.setup('overview')$$,'42501','kids_access_denied','professor não configura');
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.op('room','room',0,'{"name":"Sala Azul","location":"Térreo","capacity":10,"active":true}')$$,'cria sala sem sessão');
select lives_ok($$select pg_temp.op('class','class',0,'{"name":"Crianças","minMonths":36,"maxMonths":143,"active":true}')$$,'cria turma sem sessão');
select lives_ok($$select pg_temp.setup('team_save',jsonb_build_object('id',pg_temp.ki('t1'),'personId',pg_temp.ki('teacher-person'),'role','teacher','classId',pg_temp.ki('class'),'canCare',true,'active',true))$$,'monta equipe sem sessão ativa');
select lives_ok($$select pg_temp.setup('team_save',jsonb_build_object('id',pg_temp.ki('t2'),'personId',pg_temp.ki('reception-person'),'role','reception','classId','','canCare',false,'active',true))$$,'recepção na equipe fixa');
select throws_ok($$select pg_temp.setup('team_save',jsonb_build_object('id',pg_temp.ki('t3'),'personId',pg_temp.ki('adult'),'role','teacher','classId','','canCare',false,'active',true))$$,'22023','kids_staff_identity_required','sem conta não entra na equipe');
select is(jsonb_array_length(pg_temp.setup('overview')->'team'),2,'equipe fixa listada');
select ok(jsonb_array_length(pg_temp.setup('people','{"q":"teacher"}')->'items')>=1,'busca pessoas para a equipe');
select lives_ok($$select pg_temp.setup('series_save',jsonb_build_object('id',md5('kids-series-test-serie')::uuid,'name','Kids diário','rule','daily','weekdays','[]'::jsonb,'startsTime',pg_temp.in3h(),'durationMinutes',60,'validFrom',current_date-1,'openBeforeHours',24,'rooms',jsonb_build_array(jsonb_build_object('roomId',pg_temp.ki('room'),'classId',pg_temp.ki('class'),'capacity',8,'minStaff',1)),'autoTeam',true,'active',true))$$,'cria repetição todo dia');
select ok(jsonb_array_length(pg_temp.setup('overview')->'series'->0->'next')>=1,'prévia das próximas datas');
select throws_ok($$select pg_temp.setup('series_save',jsonb_build_object('id',pg_temp.ki('bad'),'name','Semanal sem dia','rule','weekly','weekdays','[]'::jsonb,'startsTime','09:00','durationMinutes',60,'validFrom',current_date,'rooms','[]'::jsonb,'autoTeam',true,'active',true))$$,'22023','kids_invalid','semanal exige dia da semana');
reset role;
select ok(pg_temp.sess()>=1,'sessão criada sozinha dentro da janela de 24 h');
select is((select capacity from private.kids_session_rooms where session_id=pg_temp.first_session()),8,'sala da repetição na sessão');
select is((select count(*)::int from private.kids_assignments where session_id=pg_temp.first_session()),2,'equipe distribuída automaticamente');
select ok((select bookable_from<=now() from private.kids_sessions where series_id=md5('kids-series-test-serie')::uuid order by starts_at limit 1),'famílias já podem reservar');
select ok(pg_get_functiondef('private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure) like '%bookable_from<=clock_timestamp()%','app da família vê sessões abertas para reserva');
select is((select pg_temp.sess()),(select private.kids_series_run()*0+pg_temp.sess()),'rodar de novo não duplica');
select ok(exists(select 1 from cron.job where jobname='kids-series-run'),'rotina a cada 15 minutos');
-- Sessão com responsáveis por sala.
set local role authenticated;select pg_temp.actor('owner');
select lives_ok($$select pg_temp.setup('series_save',jsonb_build_object('id',pg_temp.ki('serie2'),'name','Kids com sala','rule','daily','weekdays','[]'::jsonb,'startsTime',pg_temp.in3h(),'durationMinutes',60,'validFrom',current_date-1,'openBeforeHours',24,'rooms',jsonb_build_array(jsonb_build_object('roomId',pg_temp.ki('room'),'classId',pg_temp.ki('class'),'capacity',8,'minStaff',1,'staff',jsonb_build_array(pg_temp.ki('t1')))),'autoTeam',false,'active',true))$$,'sessão com responsáveis da sala');
reset role;
create function pg_temp.s2() returns uuid language sql security definer as $$select id from private.kids_sessions where series_id=md5('kids-series-test-serie2')::uuid order by starts_at limit 1$$;
select is((select count(*)::int from private.kids_assignments where session_id=pg_temp.s2() and group_id is not null),1,'responsável escalado na sala');
set local role authenticated;select pg_temp.actor('owner');
select lives_ok($$select pg_temp.setup('series_save',jsonb_build_object('id',pg_temp.ki('serie2'),'version',1,'name','Kids com sala','rule','daily','weekdays','[]'::jsonb,'startsTime',pg_temp.in3h(),'durationMinutes',60,'validFrom',current_date-1,'openBeforeHours',24,'rooms',jsonb_build_array(jsonb_build_object('roomId',pg_temp.ki('room'),'classId',pg_temp.ki('class'),'capacity',8,'minStaff',1,'staff',jsonb_build_array(pg_temp.ki('t2')))),'autoTeam',false,'active',true))$$,'troca o responsável da sala');
reset role;
select is((select string_agg(role,',') from private.kids_assignments where session_id=pg_temp.s2()),'reception','próxima sessão sem lançamentos é refeita com a equipe nova');
select * from finish();
rollback;
