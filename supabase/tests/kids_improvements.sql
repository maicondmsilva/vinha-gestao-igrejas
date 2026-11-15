begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.ki(t text) returns uuid language sql immutable as $$select md5('kids-impr-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.ki(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-ki@example.invalid',now(),now(),now() from unnest(array['owner','teacher','reception','other','teacher2']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.ki('org'),'Kids K2 fictício','kids-ki-test','active'),(pg_temp.ki('foreign'),'Outro fictício','kids-ki-other','active');
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
create function pg_temp.first_session() returns uuid language sql security definer as $$select id from private.kids_sessions where series_id=md5('kids-impr-test-serie')::uuid order by starts_at limit 1$$;
create function pg_temp.sess() returns int language sql security definer as $$select count(*)::int from private.kids_sessions where series_id=md5('kids-impr-test-serie')::uuid$$;
select ok(not has_function_privilege('anon','public.kids_setup(uuid,uuid,text,jsonb)','execute'),'visitante não configura');
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
-- Professor marca indisponível amanhã e hoje recebe revezamento B.
select pg_temp.actor('teacher');
select is(jsonb_array_length(public.kids_volunteer(pg_temp.ki('org'),'mine')->'team'),1,'voluntário vê a própria equipe');
select lives_ok($$select public.kids_volunteer(pg_temp.ki('org'),'unavailable',jsonb_build_object('team',pg_temp.ki('t1'),'date',current_date+1,'reason','Viagem'))$$,'marca dia indisponível');
select throws_ok($$select public.kids_volunteer(pg_temp.ki('org'),'unavailable',jsonb_build_object('team',pg_temp.ki('t2'),'date',current_date+1))$$,'42501','kids_access_denied','não marca pelo colega');
select pg_temp.actor('owner');
select ok(pg_temp.setup('overview')->'team'->0->'unavailable' is not null,'coordenação vê indisponibilidade');
-- Repetição diária que começa amanhã (dentro de 48 h): o professor indisponível não é escalado.
select lives_ok($$select pg_temp.setup('series_save',jsonb_build_object('id',md5('kids-impr-test-serie')::uuid,'name','Kids diário','rule','daily','weekdays','[]'::jsonb,'startsTime','10:00','durationMinutes',60,'validFrom',current_date+1,'openBeforeHours',48,'rooms',jsonb_build_array(jsonb_build_object('roomId',pg_temp.ki('room'),'classId',pg_temp.ki('class'),'capacity',8,'minStaff',1)),'autoTeam',true,'active',true))$$,'repetição criada');
reset role;
select is((select count(*)::int from private.kids_assignments a join private.kids_sessions s on s.id=a.session_id where s.series_id=md5('kids-impr-test-serie')::uuid and a.person_id=pg_temp.ki('teacher-person')
  and (s.starts_at at time zone private.unit_timezone(pg_temp.ki('unit')))::date=current_date+1),0,'indisponível não entra na escala');
select ok((select count(*) from private.kids_assignments a join private.kids_sessions s on s.id=a.session_id where s.series_id=md5('kids-impr-test-serie')::uuid and a.person_id=pg_temp.ki('reception-person'))>0,'recepção escalada');
-- Revezamento: duas equipes, recepção na equipe 2.
select ok(private.kids_series_index((select x from private.kids_session_series x where id=md5('kids-impr-test-serie')::uuid),current_date+3)=2,'conta as vezes anteriores');
set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.setup('series_options',jsonb_build_object('id',md5('kids-impr-test-serie')::uuid,'rotationGroups',2,'autoOpen',true))$$,'liga revezamento e abertura automática');
select lives_ok($$select pg_temp.setup('team_save',jsonb_build_object('id',pg_temp.ki('t2'),'version',1,'role','reception','classId','','canCare',false,'active',true,'rotation',2))$$,'recepção na equipe B');
select is((pg_temp.setup('overview')->'series'->0->>'rotationGroups'),'2','revezamento salvo');
-- Voluntário confirma a escala.
select pg_temp.actor('reception');
select ok(jsonb_array_length(public.kids_volunteer(pg_temp.ki('org'),'mine')->'upcoming')>=1,'vê as próximas escalas');
select lives_ok($$select public.kids_volunteer(pg_temp.ki('org'),'confirm',jsonb_build_object('id',public.kids_volunteer(pg_temp.ki('org'),'mine')->'upcoming'->0->>'id'))$$,'confirma presença');
select is((public.kids_volunteer(pg_temp.ki('org'),'mine')->'upcoming'->0->>'confirmed'),'true','presença confirmada');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki('reception'),'role','authenticated')::text,true);
select ok((select count(*) from private.member_inbox_rows(pg_temp.ki('org'),pg_temp.ki('unit')) where message_key like 'kids-serve:%')>=1,'aviso de escala na caixa do voluntário');
-- Relatório e abertura automática (sem equipe mínima não abre).
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki('owner'),'role','authenticated')::text,true);
select ok(jsonb_array_length(public.kids_setup(pg_temp.ki('org'),pg_temp.ki('unit'),'report','{}')->'items')>=1,'relatório por sessão');
update private.kids_sessions set starts_at=now()+interval '10 minutes',ends_at=now()+interval '70 minutes' where id=(select id from private.kids_sessions where series_id=md5('kids-impr-test-serie')::uuid order by starts_at limit 1);
update private.kids_session_rooms set min_staff=5 where session_id=(select id from private.kids_sessions where series_id=md5('kids-impr-test-serie')::uuid order by starts_at limit 1);
select is(private.kids_series_autoopen(),0,'sem equipe mínima não abre');
update private.kids_session_rooms set min_staff=1 where session_id=(select id from private.kids_sessions where series_id=md5('kids-impr-test-serie')::uuid order by starts_at limit 1);
insert into private.kids_assignments(id,organization_id,unit_id,session_id,group_id,person_id,member_id,role,can_care,active)
 select gen_random_uuid(),pg_temp.ki('org'),pg_temp.ki('unit'),g.session_id,g.id,pg_temp.ki('teacher2-person'),pg_temp.ki('teacher2-membership'),'teacher',false,true
 from private.kids_session_rooms g where g.session_id=(select id from private.kids_sessions where series_id=md5('kids-impr-test-serie')::uuid order by starts_at limit 1);
select is(private.kids_series_autoopen(),1,'abre sozinha com a equipe mínima');
select * from finish();
rollback;
