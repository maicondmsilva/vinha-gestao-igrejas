begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a5100000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','scale-'||i||'@example.test',now(),now(),now() from generate_series(1,4)i;
insert into public.organizations(id,name,slug,status) values('b5100000-0000-4000-8000-000000000001','Escalas fictício','scale-synthetic','active'),('b5100000-0000-4000-8000-000000000002','Outro ministério fictício','scale-other','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values('c5100000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','Igreja A fictícia','scale-a','headquarters'),('c5100000-0000-4000-8000-000000000002','b5100000-0000-4000-8000-000000000001','Igreja B fictícia','scale-b','campus'),('c5100000-0000-4000-8000-000000000003','b5100000-0000-4000-8000-000000000002','Outra igreja fictícia','scale-c','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
select ('d5100000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'b5100000-0000-4000-8000-000000000001',('a5100000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,(case i when 1 then 'owner' else 'member' end)::public.membership_role,'active','c5100000-0000-4000-8000-000000000001' from generate_series(1,3)i;
insert into public.membership_unit_access(membership_id,unit_id,access_level) values('d5100000-0000-4000-8000-000000000002','c5100000-0000-4000-8000-000000000001','read'),('d5100000-0000-4000-8000-000000000003','c5100000-0000-4000-8000-000000000001','read');
insert into public.people(id,organization_id,unit_id,full_name,auth_user_id) values
 ('e5100000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','Líder fictício','a5100000-0000-4000-8000-000000000002'),
 ('e5100000-0000-4000-8000-000000000002','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','Integrante sem conta fictício',null),
 ('e5100000-0000-4000-8000-000000000003','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000002','Pessoa de outra igreja',null);
insert into private.scale_teams(id,organization_id,unit_id,name) values
 ('f5100000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','Recepção'),
 ('f5100000-0000-4000-8000-000000000002','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','Mídia');
insert into private.scale_roles(id,organization_id,unit_id,team_id,name,required_count) values
 ('f5200000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','Acolher',2),
 ('f5200000-0000-4000-8000-000000000002','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000002','Transmitir',1);
insert into private.scale_members(id,organization_id,unit_id,team_id,person_id) values('f5300000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','e5100000-0000-4000-8000-000000000001');
insert into private.scale_grants(id,organization_id,unit_id,team_id,member_id,membership_id,capabilities) values('f5400000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','f5300000-0000-4000-8000-000000000001','d5100000-0000-4000-8000-000000000002',array['read','manage','assign']);
create function pg_temp.sp(a text,d jsonb default '{}') returns jsonb language sql as $$select public.scale_planning('b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001',a,d)$$;
select ok(not has_table_privilege('authenticated','private.scale_services','select'),'direct client tables are private');
select ok(not has_function_privilege('anon','public.scale_planning(uuid,uuid,text,jsonb)','execute'),'anonymous cannot plan');
select ok(not has_function_privilege('authenticated','private.scale_service_allowed(uuid,uuid,uuid,text)','execute'),'permission helper not exposed');
insert into private.church_app_events(id,organization_id,unit_id,title,kind,starts_at,ends_at,capacity,status) values('f5600000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','Evento existente fictício','event',now()+interval '30 days',now()+interval '30 days 2 hours',100,'draft');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('sp.data',jsonb_build_object('title','Encontro fictício','location','Prédio local','notes','Receber a comunidade','arrivalLocal',to_char(current_date+30,'YYYY-MM-DD')||'T18:30','startsLocal',to_char(current_date+30,'YYYY-MM-DD')||'T19:00','endsLocal',to_char(current_date+30,'YYYY-MM-DD')||'T21:00','repeat','weekly','count',3,'positions',jsonb_build_array(jsonb_build_object('team','f5100000-0000-4000-8000-000000000001','role','f5200000-0000-4000-8000-000000000001','ordinal',1,'member','f5300000-0000-4000-8000-000000000001'),jsonb_build_object('team','f5100000-0000-4000-8000-000000000001','role','f5200000-0000-4000-8000-000000000001','ordinal',2)))::text,true);
select is(jsonb_array_length(pg_temp.sp('preview',current_setting('sp.data')::jsonb)->'dates'),3,'preview contains all recurrence dates');
select is((pg_temp.sp('preview',current_setting('sp.data')::jsonb)->'dates'->0->>'startsLocal')::timestamp::time,'19:00'::time,'preview preserves church wall time');
select set_config('sp.command',(current_setting('sp.data')::jsonb||jsonb_build_object('request','f5500000-0000-4000-8000-000000000001','token',pg_temp.sp('preview',current_setting('sp.data')::jsonb)->>'token'))::text,true);
select set_config('sp.result',pg_temp.sp('save',current_setting('sp.command')::jsonb)::text,true);
select is(pg_temp.sp('save',current_setting('sp.command')::jsonb),current_setting('sp.result')::jsonb,'retries never create additional occurrences');
select is(current_setting('sp.result')::jsonb->>'count','3','series persisted atomically');
select is(pg_temp.sp('list',jsonb_build_object('from',current_date,'to',current_date+100,'search','Encontro fictício'))->>'total','3','title filter searches persisted services');
select is(jsonb_array_length(pg_temp.sp('choices','{"search":"Evento existente"}')->'events'),1,'existing events can be searched without creating an event');
select lives_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||'{"event":"f5600000-0000-4000-8000-000000000001","coordinator":"e5100000-0000-4000-8000-000000000001"}')$$,'existing local event and canonical coordinator accepted');
select set_config('sp.id',current_setting('sp.result')::jsonb->>'id',true);
select is(jsonb_array_length(pg_temp.sp('detail',jsonb_build_object('id',current_setting('sp.id')))->'positions'),2,'assigned and empty position persisted');
select is(pg_temp.sp('detail',jsonb_build_object('id',current_setting('sp.id')))->'service'->>'status','draft','saving never publishes');
select set_config('sp.month',(current_setting('sp.data')::jsonb||jsonb_build_object('repeat','monthly','arrivalLocal',to_char(date_trunc('year',current_date)+interval '1 year 30 days','YYYY-MM-DD')||'T18:30','startsLocal',to_char(date_trunc('year',current_date)+interval '1 year 30 days','YYYY-MM-DD')||'T19:00','endsLocal',to_char(date_trunc('year',current_date)+interval '1 year 30 days','YYYY-MM-DD')||'T21:00'))::text,true);
select is(extract(day from (pg_temp.sp('preview',current_setting('sp.month')::jsonb)->'dates'->1->>'startsLocal')::timestamp)::integer,extract(day from (date_trunc('year',current_date)+interval '1 year 2 months'-interval '1 day'))::integer,'SQL monthly recurrence clamps February');
select is(extract(day from (pg_temp.sp('preview',current_setting('sp.month')::jsonb)->'dates'->2->>'startsLocal')::timestamp)::integer,31,'SQL monthly recurrence returns to original day in March');
select is((pg_temp.sp('detail',jsonb_build_object('id',current_setting('sp.id')))->'service'->>'starts_at')::timestamptz at time zone 'America/Sao_Paulo',(current_setting('sp.data')::jsonb->>'startsLocal')::timestamp,'database converts church time to correct instant');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||'{"arrivalLocal":"2027-01-01T23:00","endsLocal":"2027-01-01T18:00"}')$$,'22023',null,'invalid chronology rejected');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||'{"count":121}')$$,'22023',null,'recurrence bounded');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||'{"coordinator":"e5100000-0000-4000-8000-000000000003"}')$$,'22023',null,'coordinator from other unit rejected');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||'{"event":"f5600000-0000-4000-8000-000000000099"}')$$,'22023',null,'invalid event rejected');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||jsonb_build_object('positions',jsonb_build_array((current_setting('sp.data')::jsonb->'positions'->0),(current_setting('sp.data')::jsonb->'positions'->0)||'{"ordinal":2}')))$$,'22023',null,'same person cannot occupy two positions');
select set_config('sp.edit',(current_setting('sp.data')::jsonb||jsonb_build_object('id',current_setting('sp.id'),'scope','all','title','Encontro alterado'))::text,true);
select set_config('sp.preview',pg_temp.sp('preview',current_setting('sp.edit')::jsonb)::text,true);
select is(current_setting('sp.preview')::jsonb->>'affected','3','all-series impact preview includes three versions');
select set_config('sp.once',(current_setting('sp.edit')::jsonb||'{"scope":"current","title":"Alteração concorrente"}')::text,true);
select lives_ok($$select pg_temp.sp('save',current_setting('sp.once')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.sp('preview',current_setting('sp.once')::jsonb)->>'token'))$$,'single occurrence editable');
select throws_ok($$select pg_temp.sp('save',current_setting('sp.edit')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',current_setting('sp.preview')::jsonb->>'token'))$$,'40001',null,'stale version of ANY occurrence rejects whole series');
select lives_ok($$select pg_temp.sp('save',current_setting('sp.edit')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.sp('preview',current_setting('sp.edit')::jsonb)->>'token'))$$,'fresh preview allows series edit');
select set_config('sp.duplicate',(current_setting('sp.data')::jsonb||jsonb_build_object('id',current_setting('sp.id'),'operation','duplicate','repeat','none','count',1))::text,true);
select is(pg_temp.sp('preview',current_setting('sp.duplicate')::jsonb)->'dates'->0->>'id',null,'duplicate preview has new identity');
select set_config('sp.duplicated',pg_temp.sp('duplicate',current_setting('sp.duplicate')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.sp('preview',current_setting('sp.duplicate')::jsonb)->>'token'))::text,true);
select isnt(current_setting('sp.duplicated')::jsonb->>'id',current_setting('sp.id'),'duplicate creates different service');
select set_config('sp.cancel',jsonb_build_object('id',current_setting('sp.id'),'scope','following','operation','cancel')::text,true);
select is(pg_temp.sp('preview',current_setting('sp.cancel')::jsonb)->>'affected','3','following scope includes selected and later occurrences');
select lives_ok($$select pg_temp.sp('cancel',current_setting('sp.cancel')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.sp('preview',current_setting('sp.cancel')::jsonb)->>'token'))$$,'cancellation preserves series rows');
select throws_ok($$select pg_temp.sp('save',current_setting('sp.edit')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.sp('preview',current_setting('sp.edit')::jsonb)->>'token'))$$,'22023',null,'cancelled occurrence cannot silently reopen');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$select pg_temp.sp('detail',jsonb_build_object('id',current_setting('sp.id')))$$,'leader sees authorized team occurrence');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.data')::jsonb||jsonb_build_object('positions',jsonb_build_array(jsonb_build_object('team','f5100000-0000-4000-8000-000000000002','role','f5200000-0000-4000-8000-000000000002','ordinal',1))))$$,'42501',null,'leader cannot plan another team');
select throws_ok($$select public.scale_planning('b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000002','choices','{}')$$,'42501',null,'another church denied');
reset role;
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal) values((current_setting('sp.duplicated')::jsonb->>'id')::uuid,'b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000002','f5200000-0000-4000-8000-000000000002',1);
set local role authenticated;
select throws_ok($$select pg_temp.sp('detail',jsonb_build_object('id',current_setting('sp.duplicated')::jsonb->>'id'))$$,'42501',null,'shared service never leaks other team roster');
reset role;
update private.scale_grants set active=false;
set local role authenticated;
select throws_ok($$select pg_temp.sp('choices')$$,'42501',null,'revocation takes effect immediately');
reset role;
update private.scale_grants set active=true,capabilities=array['read','manage'];
set local role authenticated;
select set_config('sp.noassign',(current_setting('sp.data')::jsonb||jsonb_build_object('id',current_setting('sp.duplicated')::jsonb->>'id','repeat','none','count',1))::text,true);
-- Use a service with a single authorized team for the capability test.
reset role;
delete from private.scale_positions where service_id=(current_setting('sp.duplicated')::jsonb->>'id')::uuid and team_id='f5100000-0000-4000-8000-000000000002';
set local role authenticated;
select lives_ok($$select pg_temp.sp('preview',current_setting('sp.noassign')::jsonb)$$,'manager without assignment permission may preserve existing people');
select throws_ok($$select pg_temp.sp('preview',current_setting('sp.noassign')::jsonb||jsonb_build_object('positions',jsonb_build_array((current_setting('sp.noassign')::jsonb->'positions'->0)-'member',current_setting('sp.noassign')::jsonb->'positions'->1)))$$,'42501',null,'manager without assignment permission cannot remove assigned person');
reset role;
select throws_ok($$delete from private.scale_service_history$$,'42501',null,'history cannot be deleted');
select * from finish();rollback;
