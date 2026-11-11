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

create function pg_temp.insights(a text,d jsonb default '{}') returns jsonb language sql as $$
  select public.scale_insights('b5100000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001',a,d)
$$;
create function pg_temp.inbox() returns jsonb language sql as $$
  select public.member_agenda_self('b5100000-0000-4000-8000-000000000001','inbox','c5100000-0000-4000-8000-000000000002')->'items'
$$;
select ok(not has_function_privilege('anon','public.scale_insights(uuid,uuid,text,jsonb)','execute'),'anonymous cannot query reports');
select ok(not has_function_privilege('authenticated','private.member_inbox_rows(uuid,uuid)','execute'),'inbox helper is private');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('s4.date',(now() at time zone 'America/Sao_Paulo')::date::text,true);
select set_config('s4.report',jsonb_build_object('from',(current_setting('s4.date')::date-3),'to',(current_setting('s4.date')::date+3))::text,true);
select set_config('s4.plan',jsonb_build_object(
 'title','Escala fictícia para testar avisos','notes','NOTA PRIVADA',
 'arrivalLocal',((current_setting('s4.date')::date+2)::text||'T18:30'),
 'startsLocal',((current_setting('s4.date')::date+2)::text||'T19:00'),
 'endsLocal',((current_setting('s4.date')::date+2)::text||'T21:00'),
 'repeat','none','count',1,'positions',jsonb_build_array(
 jsonb_build_object('team','f5100000-0000-4000-8000-000000000001','role','f5200000-0000-4000-8000-000000000001','ordinal',1,'member','f5300000-0000-4000-8000-000000000001'),
 jsonb_build_object('team','f5100000-0000-4000-8000-000000000001','role','f5200000-0000-4000-8000-000000000001','ordinal',2)))::text,true);
select set_config('s4.service',pg_temp.plan('save',current_setting('s4.plan')::jsonb||jsonb_build_object('request',extensions.gen_random_uuid(),'token',pg_temp.plan('preview',current_setting('s4.plan')::jsonb)->>'token'))->>'id',true);
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'slots','0','draft excluded from coverage');
select set_config('s4.publish',jsonb_build_object('service',current_setting('s4.service'),'request',extensions.gen_random_uuid(),'token',pg_temp.op('view',jsonb_build_object('service',current_setting('s4.service')))->>'token')::text,true);
select lives_ok($$select pg_temp.op('publish',current_setting('s4.publish')::jsonb)$$,'publication exposes notices');
select lives_ok($$select pg_temp.op('publish',current_setting('s4.publish')::jsonb)$$,'idempotent publication does not duplicate notices');
select set_config('s4.invite',pg_temp.op('view',jsonb_build_object('service',current_setting('s4.service')))->'invites'->0->>'id',true);
select is(pg_temp.insights('pending')->>'total','2','pending board includes a vacancy and a reply');
select is(pg_temp.insights('pending','{"search":"sem correspondência"}')->>'total','0','search filters all pending rows');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'slots','2','coverage denominator counts required slots');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'invites','1','reply denominator counts invitations');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'attendanceBase','0','future service excluded from attendance denominator');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb||'{"role":"f5200000-0000-4000-8000-000000000002"}')->>'slots','0','role filter excludes other positions');

select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is(jsonb_array_length(pg_temp.inbox()),0,'member cannot see someone else’s invite');
select throws_ok($$select pg_temp.insights('report',current_setting('s4.report')::jsonb)$$,'42501',null,'membership without team grants cannot see reports');

select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(jsonb_array_length(pg_temp.inbox()),1,'official invitation appears even while following another unit');
select is(pg_temp.inbox()->0->>'target','scales','inbox routes to My schedules');
select ok(pg_temp.inbox()::text not like '%NOTA PRIVADA%','inbox omits internal instructions');
select lives_ok($$select public.member_agenda_self('b5100000-0000-4000-8000-000000000001','read','c5100000-0000-4000-8000-000000000002',null,jsonb_build_object('keys',jsonb_build_array(pg_temp.inbox()->0->>'message_key')))$$,'inbox read receipt works for schedule messages');
select is(pg_temp.inbox()->0->>'read','true','read receipt persists');
reset role;
update private.scale_invites set reminder_at=now()-interval '1 minute' where id=current_setting('s4.invite')::uuid;
set local role authenticated;
select is(jsonb_array_length(pg_temp.inbox()),2,'one reminder becomes visible at its scheduled time');
select lives_ok($$select pg_temp.vol('reply',jsonb_build_object('id',current_setting('s4.invite'),'version',1,'response','accepted','request',extensions.gen_random_uuid()))$$,'member confirms');
select is(jsonb_array_length(pg_temp.inbox()),1,'answered invitation no longer appears as a reminder');

select is(public.scale_calendar_manage('b5100000-0000-4000-8000-000000000001','status')->>'active','false','calendar requires a deliberate action');
select set_config('s4.calendar',public.scale_calendar_manage('b5100000-0000-4000-8000-000000000001','rotate')->>'token',true) is not null as generated;
select is(jsonb_array_length(public.scale_calendar_feed(current_setting('s4.calendar'))->'events'),1,'a private calendar shows only confirmed services');
select ok(public.scale_calendar_feed(current_setting('s4.calendar'))::text not like '%NOTA PRIVADA%','calendar omits operational notes');
select set_config('s4.previous_calendar',current_setting('s4.calendar'),true) is not null as preserved;
select set_config('s4.calendar',public.scale_calendar_manage('b5100000-0000-4000-8000-000000000001','rotate')->>'token',true) is not null as generated;
select is(public.scale_calendar_feed(current_setting('s4.previous_calendar')),null::jsonb,'rotating invalidates the old link');
set local role anon;
select is(jsonb_array_length(public.scale_calendar_feed(current_setting('s4.calendar'))->'events'),1,'calendar reader can subscribe with the private link');
reset role;
select ok(not has_table_privilege('anon','private.scale_calendar_links','select'),'anonymous cannot list private links');
set local role authenticated;
select throws_ok($$select pg_temp.insights('filters','{"team":"f5100000-0000-4000-8000-000000000002"}')$$,'42501',null,'leader cannot request filters for another team');
select throws_ok($$select public.scale_insights('b5100000-0000-4000-8000-000000000002','c5100000-0000-4000-8000-000000000003','filters')$$,'42501',null,'no cross-ministry report access');

select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'confirmed','1','confirmed only counts valid invitations');
select is(pg_temp.insights('pending')->>'total','1','answered invitation leaves the pending board');
select lives_ok($$select pg_temp.op('cancel',jsonb_build_object('service',current_setting('s4.service'),'request',extensions.gen_random_uuid(),'reason','Cancelamento fictício para teste','token',pg_temp.op('view',jsonb_build_object('service',current_setting('s4.service')))->>'token'))$$,'cancel publishes a change in the inbox');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'attendanceBase','0','cancelled assignments never count as absences');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'slots','0','cancelled service leaves the coverage report');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(pg_temp.inbox()->0->>'title','Escala cancelada','recipient sees cancellation instead of stale invitation');


reset role;
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,status,created_by)
select 'b4300000-0000-4000-8000-000000000001',organization_id,unit_id,'Sessão Kids fictícia',starts_at,ends_at,'open',created_by
from private.scale_services where id=current_setting('s4.service')::uuid;
insert into private.scale_services(id,organization_id,unit_id,series_id,title,arrival_at,starts_at,ends_at,timezone,status,created_by)
select 'b4400000-0000-4000-8000-000000000001',organization_id,unit_id,extensions.gen_random_uuid(),'Serviço encerrado fictício',
  now()-interval '2 days 1 hour',now()-interval '2 days',now()-interval '2 days'+interval '1 hour',timezone,'closed',created_by
from private.scale_services where id=current_setting('s4.service')::uuid;
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id)
select 'b4400000-0000-4000-8000-000000000001',organization_id,unit_id,team_id,role_id,ordinal,'f5300000-0000-4000-8000-000000000001'
from private.scale_positions where service_id=current_setting('s4.service')::uuid;
insert into private.scale_invites(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,response,presence,invited_at,deadline)
select q.service_id,q.organization_id,q.unit_id,q.team_id,q.role_id,q.ordinal,q.member_id,'e5100000-0000-4000-8000-000000000001','accepted','present',now()-interval '3 days',now()-interval '2 days'
from private.scale_positions q where q.service_id='b4400000-0000-4000-8000-000000000001';
set local role authenticated;
select is(jsonb_array_length(pg_temp.insights('connections',jsonb_build_object('service',current_setting('s4.service')))->'kids'),0,'a scales leader does not inherit Kids permission');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(pg_temp.insights('connections',jsonb_build_object('service',current_setting('s4.service')))->'kids'),1,'authorized Kids coordination sees overlapping session');
select ok(not (pg_temp.insights('connections',jsonb_build_object('service',current_setting('s4.service')))->'kids'->0 ? 'children'),'Kids integration does not include child records');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'attendanceBase','1','two positions for one person count once in attendance');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->>'present','1','the same person has one presence per service');
select is(pg_temp.insights('report',current_setting('s4.report')::jsonb)->'distribution'->0->>'services','1','distribution counts distinct services');
select is(jsonb_array_length(public.scale_calendar_feed(current_setting('s4.calendar'))->'events'),0,'cancellation removes the event from the private feed');
select set_config('request.jwt.claims','{"sub":"a5100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(public.scale_calendar_manage('b5100000-0000-4000-8000-000000000001','revoke')->>'active','false','member revokes the private calendar');
select is(public.scale_calendar_feed(current_setting('s4.calendar')),null::jsonb,'revoked link stops resolving');
select is(pg_temp.insights('export',current_setting('s4.report')::jsonb||'{"page":2}')->'distribution'->0->>'services','1','export includes full authorized distribution independent of page');
select * from finish();
rollback;
