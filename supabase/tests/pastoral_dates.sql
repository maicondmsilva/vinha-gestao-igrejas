begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Agenda pastoral: horários livres, pedidos do membro, regras de prazo e limite, confirmação e sigilo.
create function pg_temp.pa(t text) returns uuid language sql immutable as $$select md5('pastoral-dates-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.pa(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-pdates@example.invalid',now(),now(),now() from unnest(array['owner','pastor','member','member2','outsider'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pa('org'),'Pastoral fictício','pastoral-dates-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.pa('a'),pg_temp.pa('org'),'Igreja A','a','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) select pg_temp.pa(t||'-m'),pg_temp.pa('org'),pg_temp.pa(t),pg_temp.pa('a'),case when t='owner' then 'owner'::public.membership_role else 'member'::public.membership_role end,'active' from unnest(array['owner','pastor','member','member2'])t;
insert into public.people(id,organization_id,unit_id,full_name,status,auth_user_id,is_pastor) values
 (pg_temp.pa('p-pastor'),pg_temp.pa('org'),pg_temp.pa('a'),'Pr. Davi Fictício','active',pg_temp.pa('pastor'),true),
 (pg_temp.pa('p-member'),pg_temp.pa('org'),pg_temp.pa('a'),'Ana Membro','active',pg_temp.pa('member'),false),
 (pg_temp.pa('p-member2'),pg_temp.pa('org'),pg_temp.pa('a'),'Bruno Membro','active',pg_temp.pa('member2'),false);
create function pg_temp.at(days int,hhmm text) returns timestamptz language sql stable security definer as $$select ((current_date+days)+hhmm::time) at time zone private.unit_timezone(pg_temp.pa('a'))$$;
create function pg_temp.staff(a text,d jsonb default '{}') returns jsonb language sql as $$select public.pastoral_staff(pg_temp.pa('org'),pg_temp.pa('a'),a,d)$$;
create function pg_temp.member(a text,d jsonb default '{}') returns jsonb language sql as $$select public.pastoral_member(pg_temp.pa('org'),pg_temp.pa('a'),a,d)$$;
create function pg_temp.req(k text,days int,hhmm text,mins int default 30) returns jsonb language sql as $$select pg_temp.member('request',jsonb_build_object('id',pg_temp.pa(k),'attendant',pg_temp.pa('att'),'minutes',mins,'startsAt',pg_temp.at(days,hhmm),'kind','conversa','mode','presencial','message','Gostaria de conversar'))$$;
create function pg_temp.inbox() returns setof jsonb language sql as $$select jsonb_array_elements(public.member_agenda_self(pg_temp.pa('org'),'inbox',pg_temp.pa('a'),null,'{}')->'items')$$;
create function pg_temp.ver(k text) returns int language sql security definer as $$select version from private.pastoral_appointments where id=pg_temp.pa(k)$$;

select ok(not has_function_privilege('anon','public.pastoral_member(uuid,uuid,text,jsonb)','execute'),'sem acesso anônimo');
select ok(not has_table_privilege('authenticated','private.pastoral_appointments','select'),'atendimentos sem leitura direta');
select pg_temp.actor('owner');set local role authenticated;
select is(pg_temp.staff('save_attendant',jsonb_build_object('id',pg_temp.pa('att'),'person',pg_temp.pa('p-pastor'),'role','Pastor','about','Conversas e aconselhamento','autoConfirm',false,'durations',jsonb_build_array(30,60),'kinds',jsonb_build_array('conversa','aconselhamento','visita'),'modes',jsonb_build_array('presencial','visita'),'active',true,'version',0))->>'version','1','cadastra quem atende');
reset role;select pg_temp.actor('pastor');set local role authenticated;
select lives_ok($$select pg_temp.staff('hours',jsonb_build_object('attendant',pg_temp.pa('att'),'hours',(select jsonb_agg(jsonb_build_object('weekday',w,'starts','08:00','ends','20:00')) from generate_series(0,6) w)))$$,'pastor define os próprios horários');
select throws_ok($$select pg_temp.staff('hours',jsonb_build_object('attendant',pg_temp.pa('att'),'hours',jsonb_build_array(jsonb_build_object('weekday',1,'starts','08:00','ends','12:00'),jsonb_build_object('weekday',1,'starts','11:00','ends','13:00'))))$$,'22023',null,'faixas sobrepostas recusadas');
reset role;
create function pg_temp.av(a text,d jsonb) returns jsonb language sql as $$select public.pastoral_availability(pg_temp.pa('org'),pg_temp.pa('a'),a,d||jsonb_build_object('attendant',pg_temp.pa('att')))$$;
create function pg_temp.slots(days int) returns int language sql security definer as $$select count(*)::int from private.pastoral_slots(pg_temp.pa('att'),current_date+days,30,false)$$;
set local role authenticated;
select is(pg_temp.slots(10),24,'semana padrão: 08h às 20h');
select is(jsonb_array_length(pg_temp.av('month',jsonb_build_object('month',to_char(current_date,'YYYY-MM')))->'days')>=28,true,'mês com todos os dias');
select lives_ok($$select pg_temp.av('day',jsonb_build_object('date',current_date+10,'ranges',jsonb_build_array(jsonb_build_object('starts','14:00','ends','16:00'))))$$,'pastor marca horários de um dia');
select is(pg_temp.slots(10),4,'o dia usa só os horários próprios');
select is(pg_temp.slots(11),24,'os outros dias continuam com a semana padrão');
select ok((select (x->>'custom')::boolean from jsonb_array_elements(pg_temp.av('month',jsonb_build_object('month',to_char(current_date+10,'YYYY-MM')))->'days') x where x->>'date'=(current_date+10)::text),'calendário mostra o dia ajustado');
select lives_ok($$select pg_temp.av('day',jsonb_build_object('date',current_date+12,'ranges','[]'::jsonb))$$,'marca dia sem atendimento');
select is(pg_temp.slots(12),0,'dia sem atendimento não tem horários');
select lives_ok($$select pg_temp.av('reset',jsonb_build_object('date',current_date+12))$$,'volta à semana padrão');
select is(pg_temp.slots(12),24,'dia volta a ter os horários da semana');
select throws_ok($$select pg_temp.av('day',jsonb_build_object('date',current_date+10,'ranges',jsonb_build_array(jsonb_build_object('starts','14:00','ends','16:00'),jsonb_build_object('starts','15:00','ends','17:00'))))$$,'22023','invalid_pastoral','não aceita horários sobrepostos');
select throws_ok($$select pg_temp.av('day',jsonb_build_object('date',current_date-1,'ranges','[]'::jsonb))$$,'22023','invalid_pastoral','não altera dias passados');
reset role;select pg_temp.actor('member');set local role authenticated;
select throws_ok($$select pg_temp.av('month',jsonb_build_object('month',to_char(current_date,'YYYY-MM')))$$,'42501','pastoral_denied','membro não mexe na agenda de quem atende');
select * from finish();
rollback;
