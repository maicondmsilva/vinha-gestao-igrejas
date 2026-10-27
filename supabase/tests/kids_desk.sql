begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.ki(t text) returns uuid language sql immutable as $$select md5('kids-k2-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ki(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.ki(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-k2@example.invalid',now(),now(),now() from unnest(array['owner','teacher','reception','other','teacher2']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.ki('org'),'Kids K2 fictício','kids-k2-test','active'),(pg_temp.ki('foreign'),'Outro fictício','kids-k2-other','active');
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
insert into private.kids_care(profile_id,organization_id,unit_id,instructions,source) values(pg_temp.ki('child-profile'),pg_temp.ki('org'),pg_temp.ki('unit'),'Orientação K2 restrita fictícia','Responsável fictício');
create function pg_temp.op(a text,i text,v integer,d jsonb) returns jsonb language sql as $$select public.kids_operations_save(pg_temp.ki('org'),pg_temp.ki('unit'),extensions.gen_random_uuid(),a,pg_temp.ki(i),v,d)$$;
create function pg_temp.page(s text default 'session') returns jsonb language sql as $$select public.kids_operations_page(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki(s),null,'','all')$$;
create function pg_temp.entry(child text default 'child',grp text default 'group') returns jsonb language sql as $$select jsonb_build_object('sessionId',pg_temp.ki('session'),'groupId',pg_temp.ki(grp),'profileId',pg_temp.ki(child||'-profile'),'guardianId',pg_temp.ki('adult'),'identityConfirmed',true,'receiptSecret',repeat('a',64))$$;
create function pg_temp.exit_data(code text default repeat('a',64)) returns jsonb language sql as $$select jsonb_build_object('guardianId',pg_temp.ki('adult'),'identityConfirmed',true,'receiptSecret',code)$$;
select ok(not has_function_privilege('anon','public.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb)','execute'),'visitante não opera');
select ok(not has_function_privilege('service_role','private.kids_operations_save(uuid,uuid,uuid,text,uuid,integer,jsonb)','execute'),'serviço não pula operação');
select ok(not has_table_privilege('authenticated','private.kids_attendance','insert') and not has_table_privilege('authenticated','private.kids_custody_events','delete'),'presença e histórico sem acesso direto');
select ok((select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r' and c.relname like 'kids_%'),'RLS em todo Kids');
set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.op('room','room',0,'{"name":"Sala A","location":"Térreo","capacity":1,"active":true}')$$,'cria sala');
select lives_ok($$select pg_temp.op('room','room2',0,'{"name":"Sala B","location":"Térreo","capacity":2,"active":true}')$$,'cria segunda sala');
select lives_ok($$select pg_temp.op('class','class',0,'{"name":"Crianças","minMonths":60,"maxMonths":143,"active":true}')$$,'cria turma');
select throws_ok($$select pg_temp.op('room','room',0,'{"name":"Sobrescrever","location":"","capacity":4,"active":true}')$$,'40001','kids_version_conflict','versão protege edição');
select lives_ok($$select pg_temp.op('session','session',0,jsonb_build_object('name','Encontro K2','startsAt',now()-interval '5 minutes','endsAt',now()+interval '2 hours'))$$,'cria sessão');
select throws_ok($$select pg_temp.op('sessionState','session',1,'{"status":"open"}')$$,'22023','kids_session_not_ready','sem salas não abre');
select lives_ok($$select pg_temp.op('group','group',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'roomId',pg_temp.ki('room'),'classId',pg_temp.ki('class'),'capacity',1,'minStaff',1))$$,'vincula sala');
select lives_ok($$select pg_temp.op('group','group2',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'roomId',pg_temp.ki('room2'),'classId',pg_temp.ki('class'),'capacity',2,'minStaff',1))$$,'vincula destino');
select throws_ok($$select pg_temp.op('sessionState','session',1,'{"status":"open"}')$$,'22023','kids_staff_insufficient','sem equipe não abre');
select throws_ok($$select pg_temp.op('assignment','bad-assignment',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'personId',pg_temp.ki('adult'),'groupId',pg_temp.ki('group'),'role','teacher','canCare',true,'active',true))$$,'22023','kids_staff_identity_required','não escala adulto sem conta vinculada');
select lives_ok($$select pg_temp.op('assignment','teacher-assignment',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'personId',pg_temp.ki('teacher-person'),'groupId',pg_temp.ki('group'),'role','teacher','canCare',false,'active',true))$$,'escala professor');
select throws_ok($$select pg_temp.op('assignment','duplicate-assignment',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'personId',pg_temp.ki('teacher-person'),'groupId',pg_temp.ki('group2'),'role','teacher','canCare',false,'active',true))$$,'40001','kids_staff_overlap','não conta pessoa em duas salas');
select lives_ok($$select pg_temp.op('assignment','teacher2-assignment',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'personId',pg_temp.ki('teacher2-person'),'groupId',pg_temp.ki('group2'),'role','teacher','canCare',true,'active',true))$$,'escala destino');
select lives_ok($$select pg_temp.op('assignment','reception-assignment',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'personId',pg_temp.ki('reception-person'),'groupId',null,'role','reception','canCare',false,'active',true))$$,'escala recepção');
select lives_ok($$select pg_temp.op('sessionState','session',1,'{"status":"open"}')$$,'abre sessão equipada');
select is(pg_temp.page()->'groups'->0->>'occupied','0','sala começa vazia');
select throws_ok($$select pg_temp.op('room','room',1,'{"name":"Alterar aberta","location":"","capacity":2,"active":true}')$$,'40001','kids_room_in_use','não muda sala em uso');
select throws_ok($$select pg_temp.op('checkin','attendance',0,pg_temp.entry()||'{"identityConfirmed":false}')$$,'42501','kids_guardian_required','exige conferência presencial');
select pg_temp.op('checkin','attendance',0,pg_temp.entry());
select is(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'reports')->'summary'->>'entries','1','relatório conta entrada');
select is(jsonb_array_length(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'reports')->'items'),2,'supervisão vê duas salas');
select ok(not(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),null,'reports')::text like '%pessoa fictícia%'),'relatório não contém dados pessoais');
select public.kids_notes(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('attendance'),'create',pg_temp.ki('note'),0,'{"kind":"occurrence","body":"Ocorrência fictícia para conferência local"}');
select pg_temp.actor('teacher');
select is(jsonb_array_length(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'reports')->'items'),1,'professor só recebe própria sala');
select is(jsonb_array_length(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'notes')->'items'),1,'professor recebe ocorrência de sua sala');
select is(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'notes')->'items'->0->>'can_resolve','false','professor não conclui atendimento de supervisão');
select pg_temp.actor('teacher2');
select is(jsonb_array_length(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'notes')->'items'),0,'outra sala não recebe ocorrência');
select pg_temp.actor('reception');
select throws_ok($$select public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'notes')$$,'42501','kids_desk_denied','recepção não consulta textos');
select pg_temp.actor('other');
select throws_ok($$select public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),null,'reports')$$,'42501',null,'conta sem escala não recebe relatório');
select pg_temp.actor('owner');
select throws_ok($$select public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('foreignunit'),'reports')$$,'42501',null,'sessão fora da igreja recusada');
select is(public.kids_desk(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('session'),'notes')->'items'->0->>'can_resolve','true','supervisão pode concluir');
select finish();
rollback;
