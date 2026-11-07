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
update private.scale_members set role_id='f5200000-0000-4000-8000-000000000001' where organization_id='b5100000-0000-4000-8000-000000000001';
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name) values('e5100000-0000-4000-8000-000000000004','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','a5100000-0000-4000-8000-000000000003','Substituto fictício');
insert into private.scale_members(id,organization_id,unit_id,team_id,person_id,role_id) values
 ('f5300000-0000-4000-8000-000000000002','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','e5100000-0000-4000-8000-000000000004','f5200000-0000-4000-8000-000000000001');
create function pg_temp.op(a text,d jsonb default '{}') returns jsonb language sql as $$select public.scale_operations('b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001',a,d)$$;
create function pg_temp.vol(a text,d jsonb default '{}') returns jsonb language sql as $$select public.scale_volunteer('b5100000-0000-4000-8000-000000000001',a,d)$$;
create function pg_temp.plan(a text,d jsonb) returns jsonb language sql as $$select public.scale_planning('b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001',a,d)$$;
select ok(not has_function_privilege('anon','public.scale_volunteer(uuid,text,jsonb)','execute'),'anonymous cannot read invitations');
select ok(not has_table_privilege('authenticated','private.scale_invites','select'),'invitation rows are private');
select ok(not has_function_privilege('authenticated','private.scale_conflicts(uuid,uuid,uuid,integer)','execute'),'private conflict helper not exposed');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('op.plan',jsonb_build_object('title','Serviço fictício','location','Local restrito da equipe','notes','Orientação restrita da equipe','arrivalLocal',to_char((now()+interval '2 days') at time zone 'America/Sao_Paulo','YYYY-MM-DD')||'T18:30','startsLocal',to_char((now()+interval '2 days') at time zone 'America/Sao_Paulo','YYYY-MM-DD')||'T19:00','endsLocal',to_char((now()+interval '2 days') at time zone 'America/Sao_Paulo','YYYY-MM-DD')||'T21:00','repeat','none','count',1,'positions',jsonb_build_array(jsonb_build_object('team','f5100000-0000-4000-8000-000000000001','role','f5200000-0000-4000-8000-000000000001','ordinal',1,'member','f5300000-0000-4000-8000-000000000001'),jsonb_build_object('team','f5100000-0000-4000-8000-000000000001','role','f5200000-0000-4000-8000-000000000001','ordinal',2)))::text,true);
select set_config('op.service',pg_temp.plan('save',current_setting('op.plan')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.plan('preview',current_setting('op.plan')::jsonb)->>'token'))->>'id',true);
select set_config('op.publish',jsonb_build_object('service',current_setting('op.service'),'request',extensions.gen_random_uuid(),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->>'token')::text,true);
select lives_ok($$select pg_temp.op('publish',current_setting('op.publish')::jsonb)$$,'owner publishes individual invitations');
select lives_ok($$select pg_temp.op('publish',current_setting('op.publish')::jsonb)$$,'retry does not duplicate invitations');
select is(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'service'->>'status','published','published state persisted');
select is(jsonb_array_length(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'invites'),1,'empty vacancy never creates a fake invitation');
select set_config('op.invite',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'invites'->0->>'id',true);
select throws_ok($$select pg_temp.plan('save',current_setting('op.plan')::jsonb||jsonb_build_object('id',current_setting('op.service'),'request',extensions.gen_random_uuid(),'token',pg_temp.plan('preview',current_setting('op.plan')::jsonb||jsonb_build_object('id',current_setting('op.service')))->>'token'))$$,'22023',null,'published planning cannot silently overwrite replies');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is(pg_temp.vol('list')->>'total','0','another member cannot list an invitation not addressed to them');
select throws_ok($$select pg_temp.vol('reply',jsonb_build_object('id',current_setting('op.invite'),'version',1,'response','accepted','request',extensions.gen_random_uuid()))$$,'42501',null,'another member cannot answer the invitation');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(pg_temp.vol('list')->>'total','1','canonical member sees their own invitation without panel management access');
select set_config('op.reply',jsonb_build_object('id',current_setting('op.invite'),'version',1,'response','accepted','request',extensions.gen_random_uuid())::text,true);
select lives_ok($$select pg_temp.vol('reply',current_setting('op.reply')::jsonb)$$,'volunteer confirms through their own account');
select lives_ok($$select pg_temp.vol('reply',current_setting('op.reply')::jsonb)$$,'lost response retry is idempotent');
select is(pg_temp.vol('list')->'items'->0->>'presence','unset','acceptance never records presence');
select throws_ok($$select pg_temp.vol('reply',current_setting('op.reply')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'response','declined'))$$,'40001',null,'stale reply cannot overwrite newer response');
select set_config('op.unavailable',jsonb_build_object('id','f5700000-0000-4000-8000-000000000001','version',0,'kind','unavailable','startsLocal',current_setting('op.plan')::jsonb->>'arrivalLocal','endsLocal',current_setting('op.plan')::jsonb->>'endsLocal','reason','MOTIVO PARTICULAR FICTICIO','request',extensions.gen_random_uuid())::text,true);
select lives_ok($$select pg_temp.vol('available.save',current_setting('op.unavailable')::jsonb)$$,'member records personal unavailability');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select ok((pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'slots'->0->'conflicts')?'unavailable','availability changes recalculate existing service conflicts');
select ok(strpos(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))::text,'MOTIVO PARTICULAR')=0,'leadership never receives private unavailability reason');
select throws_ok($$select pg_temp.op('reply',jsonb_build_object('id',current_setting('op.invite'),'version',2,'response','declined','request',extensions.gen_random_uuid()))$$,'22023',null,'leadership cannot answer silently without reason');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$select pg_temp.vol('replacement.request',jsonb_build_object('id',current_setting('op.invite'),'version',2,'suggestion','f5300000-0000-4000-8000-000000000002','reason','Preciso de substituição fictícia','request',extensions.gen_random_uuid()))$$,'member requests replacement with optional qualified suggestion');
select set_config('op.case',pg_temp.vol('list')->'items'->0->'replacement'->>'id',true);
select is(pg_temp.vol('list')->'items'->0->>'response','accepted','request does not erase previous response');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$select pg_temp.vol('available.save',current_setting('op.unavailable')::jsonb||jsonb_build_object('id','f5700000-0000-4000-8000-000000000002','request',extensions.gen_random_uuid()))$$,'suggested member becomes unavailable after request');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select pg_temp.op('decision',jsonb_build_object('id',current_setting('op.case'),'version',1,'decision','approve','member','f5300000-0000-4000-8000-000000000002','reason','Aprovação fictícia pela liderança','request',extensions.gen_random_uuid()))$$,'22023',null,'approval rechecks availability transactionally');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$select pg_temp.vol('available.save',jsonb_build_object('id','f5700000-0000-4000-8000-000000000002','version',1,'active',false,'request',extensions.gen_random_uuid()))$$,'owner of personal unavailability can cancel it');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select pg_temp.op('decision',jsonb_build_object('id',current_setting('op.case'),'version',1,'decision','approve','member','f5300000-0000-4000-8000-000000000002','reason','Aprovação fictícia pela liderança','request',extensions.gen_random_uuid()))$$,'qualified available replacement is approved');
select is((select x from jsonb_array_elements(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'invites') x where (x->>'active')::boolean limit 1)->>'response','pending','replacement receives pending invitation, never automatic confirmation');
select set_config('op.newinvite',(select x from jsonb_array_elements(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'invites') x where (x->>'active')::boolean limit 1)->>'id',true);
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(pg_temp.vol('list')->'items'->0->>'location','','replaced member cannot read current service location');
select is(pg_temp.vol('list')->'items'->0->>'notes','','replaced member cannot read current service instructions');
select is(pg_temp.vol('list')->'items'->0->>'response','accepted','old response preserved after replacement');
select throws_ok($$select pg_temp.vol('reply',jsonb_build_object('id',current_setting('op.invite'),'version',4,'response','declined','request',extensions.gen_random_uuid()))$$,'22023',null,'replaced invitation cannot receive new replies');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('op.oldtoken',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->>'token',true);
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$select pg_temp.vol('reply',jsonb_build_object('id',current_setting('op.newinvite'),'version',1,'response','accepted','request',extensions.gen_random_uuid()))$$,'new member can answer their invitation');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select pg_temp.op('revise',jsonb_build_object('service',current_setting('op.service'),'token',current_setting('op.oldtoken'),'reason','Revisão de horário fictícia','request',extensions.gen_random_uuid()))$$,'40001',null,'reply racing a revision invalidates stale preview');
select lives_ok($$select pg_temp.op('revise',jsonb_build_object('service',current_setting('op.service'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->>'token','reason','Revisão de horário fictícia','request',extensions.gen_random_uuid()))$$,'explicit revision reopens draft and preserves prior invitations');
select is(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'service'->>'status','draft','revision returns draft for controlled planning');
select is((select x from jsonb_array_elements(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'invites') x where x->>'id'=current_setting('op.newinvite'))->>'response','accepted','revision does not erase accepted answer');
select throws_ok($$select public.scale_operations('b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000002','view',jsonb_build_object('service',current_setting('op.service')))$$,'42501',null,'another church cannot read operation');
select set_config('op.today',(current_setting('op.plan')::jsonb||jsonb_build_object('title','Presença fictícia','arrivalLocal',to_char((now()+interval '30 minutes') at time zone 'America/Sao_Paulo','YYYY-MM-DD"T"HH24:MI'),'startsLocal',to_char((now()+interval '1 hour') at time zone 'America/Sao_Paulo','YYYY-MM-DD"T"HH24:MI'),'endsLocal',to_char((now()+interval '2 hours') at time zone 'America/Sao_Paulo','YYYY-MM-DD"T"HH24:MI')))::text,true);
select set_config('op.todayid',pg_temp.plan('save',current_setting('op.today')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.plan('preview',current_setting('op.today')::jsonb)->>'token'))->>'id',true);
select lives_ok($$select pg_temp.op('publish',jsonb_build_object('service',current_setting('op.todayid'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->>'token','request',extensions.gen_random_uuid()))$$,'service near current time can publish');
select set_config('op.todayinvite',pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->'invites'->0->>'id',true);
select lives_ok($$select pg_temp.op('presence',jsonb_build_object('id',current_setting('op.todayinvite'),'version',1,'presence','present','request',extensions.gen_random_uuid()))$$,'leadership records observed presence independently of acceptance');
select is(pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->'invites'->0->>'response','pending','presence never infers confirmation');
select is(pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->'invites'->0->>'presence','present','presence recorded');
select throws_ok($$select pg_temp.op('presence',jsonb_build_object('id',current_setting('op.todayinvite'),'version',2,'presence','absent','request',extensions.gen_random_uuid()))$$,'22023',null,'presence correction requires reason');
select lives_ok($$select pg_temp.op('presence',jsonb_build_object('id',current_setting('op.todayinvite'),'version',2,'presence','absent','reason','Correção conferida presencialmente','request',extensions.gen_random_uuid()))$$,'presence correction with reason succeeds');
select lives_ok($$select pg_temp.op('fill',jsonb_build_object('service',current_setting('op.todayid'),'role','f5200000-0000-4000-8000-000000000001','ordinal',2,'member','f5300000-0000-4000-8000-000000000002','version',(pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->'service'->>'version')::integer,'request',extensions.gen_random_uuid()))$$,'empty published vacancy can be filled with pending invitation');
select throws_ok($$select pg_temp.op('close',jsonb_build_object('service',current_setting('op.todayid'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->>'token','request',extensions.gen_random_uuid()))$$,'22023',null,'service cannot close before end');
reset role;
update private.scale_services set arrival_at=now()-interval '3 hours',starts_at=now()-interval '2 hours',ends_at=now()-interval '1 minute' where id=current_setting('op.todayid')::uuid;
set local role authenticated;
select lives_ok($$select pg_temp.op('close',jsonb_build_object('service',current_setting('op.todayid'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->>'token','request',extensions.gen_random_uuid()))$$,'service can close after end');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.op('view',jsonb_build_object('service',current_setting('op.todayid')))->'invites')x where x->>'presence'='unset'),1,'closing never turns unanswered invitation into absence');
reset role;
insert into private.scale_roles(id,organization_id,unit_id,team_id,name) values('f5200000-0000-4000-8000-000000000003','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','Orientar');
set local role authenticated;
select lives_ok($$select pg_temp.op('qualify','{"team":"f5100000-0000-4000-8000-000000000001","member":"f5300000-0000-4000-8000-000000000001","role":"f5200000-0000-4000-8000-000000000003","version":1}'||jsonb_build_object('request',extensions.gen_random_uuid()))$$,'manager can qualify canonical team member for another function');
select throws_ok($$select pg_temp.op('qualify','{"team":"f5100000-0000-4000-8000-000000000001","member":"f5300000-0000-4000-8000-000000000001","role":"f5200000-0000-4000-8000-000000000001","active":false,"version":2}'||jsonb_build_object('request',extensions.gen_random_uuid()))$$,'22023',null,'primary qualification cannot be silently removed');
select lives_ok($$select pg_temp.op('policy','{"team":"f5100000-0000-4000-8000-000000000001","role":"f5200000-0000-4000-8000-000000000001","parallel":true,"version":1}'||jsonb_build_object('request',extensions.gen_random_uuid()))$$,'role can explicitly permit coexistence');
select lives_ok($$select pg_temp.op('policy','{"team":"f5100000-0000-4000-8000-000000000001","role":"f5200000-0000-4000-8000-000000000003","parallel":true,"version":1}'||jsonb_build_object('request',extensions.gen_random_uuid()))$$,'both functions must explicitly permit coexistence');
select set_config('op.dual',(current_setting('op.plan')::jsonb||jsonb_build_object('positions',jsonb_build_array(current_setting('op.plan')::jsonb->'positions'->0,(current_setting('op.plan')::jsonb->'positions'->0)||'{"role":"f5200000-0000-4000-8000-000000000003"}')))::text,true);
select lives_ok($$select pg_temp.plan('preview',current_setting('op.dual')::jsonb)$$,'qualified coexistence is accepted in planning');
select throws_ok($$select pg_temp.plan('preview',current_setting('op.dual')::jsonb||jsonb_build_object('positions',jsonb_build_array(current_setting('op.plan')::jsonb->'positions'->0,(current_setting('op.plan')::jsonb->'positions'->0)||'{"ordinal":2}')))$$,'22023',null,'same person cannot fill two vacancies of the same function');
select set_config('op.unqualified',(current_setting('op.plan')::jsonb||jsonb_build_object('positions',jsonb_build_array((current_setting('op.plan')::jsonb->'positions'->0)||'{"member":"f5300000-0000-4000-8000-000000000002","role":"f5200000-0000-4000-8000-000000000003"}')))::text,true);
select set_config('op.unqualifiedid',pg_temp.plan('save',current_setting('op.unqualified')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.plan('preview',current_setting('op.unqualified')::jsonb)->>'token'))->>'id',true);
select throws_ok($$select pg_temp.op('publish',jsonb_build_object('service',current_setting('op.unqualifiedid'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.unqualifiedid')))->>'token','override',true,'reason','Exceção não permite função não habilitada','request',extensions.gen_random_uuid()))$$,'22023',null,'override never bypasses qualification');
select lives_ok($$select pg_temp.op('policy','{"team":"f5100000-0000-4000-8000-000000000001","travel":30,"version":1}'||jsonb_build_object('request',extensions.gen_random_uuid()))$$,'travel interval configured for team');
select is(pg_temp.op('settings','{"team":"f5100000-0000-4000-8000-000000000001"}')->'team'->>'travel','30','travel interval persisted');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select lives_ok($$select pg_temp.vol('available.save',jsonb_build_object('id','f5700000-0000-4000-8000-000000000003','version',0,'kind','weekly','weekday',(extract(dow from (current_setting('op.plan')::jsonb->>'startsLocal')::timestamp)::integer+1)%7,'startMinute',0,'endMinute',1440,'request',extensions.gen_random_uuid()))$$,'member configures weekly window through local church time');
select is(pg_temp.vol('list','{"unit":"c5100000-0000-4000-8000-000000000002"}')->>'unit','c5100000-0000-4000-8000-000000000001','content selection never changes official scheduling church');
select throws_ok($$select pg_temp.vol('available.save',jsonb_build_object('id','f5700000-0000-4000-8000-000000000001','version',1,'active',false,'request',extensions.gen_random_uuid()))$$,'42501',null,'another member cannot edit private availability');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select ok((pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'slots'->0->'conflicts')?'availability','weekly availability recalculates conflict in existing drafts');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$select pg_temp.op('publish',jsonb_build_object('service',current_setting('op.service'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->>'token','request',extensions.gen_random_uuid()))$$,'42501',null,'assign permission alone cannot publish');
reset role;
select throws_ok($$delete from private.scale_person_history$$,'42501',null,'personal history is immutable');
reset role;
-- A future invitation whose individual deadline expired must require the leader.
update private.scale_services set status='published' where id=current_setting('op.service')::uuid;
insert into private.scale_invites(id,service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,deadline)
values('f5800000-0000-4000-8000-000000000001',current_setting('op.service')::uuid,'b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','f5200000-0000-4000-8000-000000000001',1,'f5300000-0000-4000-8000-000000000002','e5100000-0000-4000-8000-000000000004',now()-interval '1 minute');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$select pg_temp.vol('reply',jsonb_build_object('id','f5800000-0000-4000-8000-000000000001','version',1,'response','accepted','request',extensions.gen_random_uuid()))$$,'22023','scale_deadline','expired deadline prevents self reply');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$select pg_temp.op('reply',jsonb_build_object('id','f5800000-0000-4000-8000-000000000001','version',1,'response','accepted','reason','Confirmado pessoalmente pela liderança','request',extensions.gen_random_uuid()))$$,'leader can record late response with explicit reason');
select lives_ok($$select pg_temp.op('revise',jsonb_build_object('service',current_setting('op.service'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->>'token','reason','Revisão para republicação fictícia','request',extensions.gen_random_uuid()))$$,'published service returns to draft with explicit revision');
select lives_ok($$select pg_temp.op('publish',jsonb_build_object('service',current_setting('op.service'),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->>'token','override',true,'reason','Teste fictício de nova confirmação após revisão','request',extensions.gen_random_uuid()))$$,'republishing creates a fresh pending invitation');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.op('view',jsonb_build_object('service',current_setting('op.service')))->'invites')x where (x->>'active')::boolean and x->>'response'='pending'),1,'new revision has one pending invitation, preserving old confirmations');
reset role;
insert into private.scale_services(id,organization_id,unit_id,series_id,title,arrival_at,starts_at,ends_at,timezone,status,created_by)
select 'f5900000-0000-4000-8000-000000000001',organization_id,unit_id,extensions.gen_random_uuid(),'Intervalo fictício',ends_at+interval '15 minutes',ends_at+interval '30 minutes',ends_at+interval '1 hour',timezone,'draft',created_by from private.scale_services where id=current_setting('op.service')::uuid;
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id)
values('f5900000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','f5100000-0000-4000-8000-000000000001','f5200000-0000-4000-8000-000000000001',1,'f5300000-0000-4000-8000-000000000002');
select ok('overlap'=any(private.scale_conflicts('f5900000-0000-4000-8000-000000000001','f5200000-0000-4000-8000-000000000001','f5300000-0000-4000-8000-000000000002',1)),'15 minute gap conflicts with 30 minute travel buffer');
update private.scale_teams set travel_minutes=0 where id='f5100000-0000-4000-8000-000000000001';
select ok(not('overlap'=any(private.scale_conflicts('f5900000-0000-4000-8000-000000000001','f5200000-0000-4000-8000-000000000001','f5300000-0000-4000-8000-000000000002',1))),'removing buffer removes overlap for adjacent different services');

select * from finish();rollback;
