begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Agenda pastoral: horários livres, pedidos do membro, regras de prazo e limite, confirmação e sigilo.
create function pg_temp.pa(t text) returns uuid language sql immutable as $$select md5('pastoral-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.pa(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-pastoral@example.invalid',now(),now(),now() from unnest(array['owner','pastor','member','member2','outsider'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pa('org'),'Pastoral fictício','pastoral-test','active');
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
reset role;select pg_temp.actor('member');set local role authenticated;
select is(jsonb_array_length(pg_temp.member('attendants')->'items'),1,'membro vê quem atende');
select is(pg_temp.member('attendants')->'items'->0->>'pastor','true','identifica o pastor');
select is((select d->>'state' from jsonb_array_elements(pg_temp.member('month',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',30,'month',to_char(current_date+3,'YYYY-MM')))->'days') d where d->>'date'=(current_date+3)::text),'available','dia com horário livre');
select is((select d->>'state' from jsonb_array_elements(pg_temp.member('month',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',30,'month',to_char(current_date-1,'YYYY-MM')))->'days') d where d->>'date'=(current_date-1)::text),'past','dia passado');
select is(jsonb_array_length(pg_temp.member('day',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',30,'date',(current_date+3)::text))->'slots'),24,'horários de 30 em 30 min no dia');
select is(pg_temp.member('day',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',60,'date',(current_date+3)::text))->'slots'->-1->>'label','19:00','último horário de 1 h termina às 20:00');
select throws_ok($$select pg_temp.member('day',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',45,'date',(current_date+3)::text))$$,'22023',null,'duração não aceita por quem atende');
select throws_ok($$select pg_temp.req('soon',0,'23:30')$$,'40001',null,'menos de 24 h de antecedência recusado');
select is(pg_temp.req('r1',3,'10:00')->>'status','requested','pedido aguardando confirmação');
select is(pg_temp.req('r1',3,'10:00')->>'status','requested','reenvio não duplica');
select is(jsonb_array_length(pg_temp.member('day',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',30,'date',(current_date+3)::text))->'slots'),23,'horário pedido sai da lista');
select is(pg_temp.req('r2',4,'10:00',60)->>'status','requested','segundo pedido');
select throws_ok($$select pg_temp.req('r3',5,'10:00')$$,'54000',null,'no máximo 2 pedidos em aberto');
reset role;select pg_temp.actor('member2');set local role authenticated;
select throws_ok($$select pg_temp.req('x1',3,'10:00')$$,'40001',null,'horário já ocupado');
select throws_ok($$select pg_temp.member('cancel',jsonb_build_object('id',pg_temp.pa('r1'),'version',1))$$,'42501',null,'não cancela pedido de outra pessoa');
reset role;select pg_temp.actor('member');set local role authenticated;
select is((pg_temp.member('cancel',jsonb_build_object('id',pg_temp.pa('r2'),'version',1)))->>'version','2','cancela com mais de 12 h');
select is(pg_temp.req('r3',5,'10:00')->>'status','requested','cancelado libera um pedido');

-- equipe
select throws_ok($$select pg_temp.staff('overview')$$,'42501',null,'membro comum não vê a agenda');
reset role;select pg_temp.actor('pastor');set local role authenticated;
select is(jsonb_array_length(pg_temp.staff('overview')->'items'),3,'pastor vê os próprios atendimentos');
select is(pg_temp.staff('decide',jsonb_build_object('id',pg_temp.pa('r1'),'version',1,'decision','confirm','reason','','link',''))->>'version','2','pastor confirma');
select lives_ok($$select pg_temp.staff('note',jsonb_build_object('id',pg_temp.pa('r1'),'version',2,'notes','Anotação sigilosa'))$$,'anotação sigilosa');
select is(pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.pa('visit'),'attendant',pg_temp.pa('att'),'person',pg_temp.pa('p-member2'),'minutes',60,'startsAt',now()+interval '3 hours','kind','visita','mode','visita','message','Visita de cuidado','link',''))->>'version','1','pastor marca visita com membro');
select throws_ok($$select pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.pa('visit2'),'attendant',pg_temp.pa('att'),'person',pg_temp.pa('p-member'),'minutes',30,'startsAt',now()+interval '3 hours 30 minutes','kind','visita','mode','visita','message','','link',''))$$,'40001',null,'equipe também não sobrepõe horários');
reset role;select pg_temp.actor('member');set local role authenticated;
select is((select i->>'status' from jsonb_array_elements(pg_temp.member('mine')->'items') i where i->>'id'=pg_temp.pa('r1')::text),'confirmed','membro vê confirmado');
select is((select i->>'notes' from jsonb_array_elements(pg_temp.member('mine')->'items') i where i->>'id'=pg_temp.pa('r1')::text),'','membro nunca vê a anotação');
select is((select count(*)::int from pg_temp.inbox() q where q->>'target'='pastoral' and q->>'title'='Seu horário foi confirmado'),1,'aviso na caixa do app');
select ok((select bool_and(q->>'body' not like '%conversar%') from pg_temp.inbox() q where q->>'target'='pastoral'),'aviso sem o motivo do pedido');
reset role;select pg_temp.actor('member2');set local role authenticated;
select is((select q->>'title' from pg_temp.inbox() q where q->>'target'='pastoral'),'Marcamos um horário com você','visita marcada avisa o membro');
select throws_ok($$select pg_temp.member('cancel',jsonb_build_object('id',pg_temp.pa('visit'),'version',1))$$,'22023',null,'cancelar com menos de 12 h recusado');
select is(pg_temp.member('ack',jsonb_build_object('id',pg_temp.pa('visit'),'version',1))->>'version','2','membro confirma a visita');

-- confirmação automática (liga/desliga)
reset role;select pg_temp.actor('owner');set local role authenticated;
select lives_ok($$select pg_temp.staff('save_attendant',jsonb_build_object('id',pg_temp.pa('att'),'person',pg_temp.pa('p-pastor'),'role','Pastor','about','','autoConfirm',true,'durations',jsonb_build_array(30,60),'kinds',jsonb_build_array('conversa'),'modes',jsonb_build_array('presencial'),'active',true,'version',(select (x->>'version')::int from jsonb_array_elements(pg_temp.staff('overview')->'attendants') x)))$$,'liga confirmação automática');
select is((select i->>'notes' from jsonb_array_elements(pg_temp.staff('overview')->'items') i where i->>'id'=pg_temp.pa('r1')::text),'Anotação sigilosa','dono com permissão lê anotação');
reset role;select pg_temp.actor('member2');set local role authenticated;
select is(pg_temp.req('auto',6,'09:00')->>'status','confirmed','pedido confirmado na hora');
-- bloqueio de dias
reset role;select pg_temp.actor('pastor');set local role authenticated;
select lives_ok($$select pg_temp.staff('block',jsonb_build_object('attendant',pg_temp.pa('att'),'from',(current_date+10)::text,'to',(current_date+12)::text,'reason','Viagem'))$$,'bloqueia dias');
reset role;select pg_temp.actor('member');set local role authenticated;
select is((select d->>'state' from jsonb_array_elements(pg_temp.member('month',jsonb_build_object('attendant',pg_temp.pa('att'),'minutes',30,'month',to_char(current_date+11,'YYYY-MM')))->'days') d where d->>'date'=(current_date+11)::text),'none','dia bloqueado sem atendimento');
reset role;select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.req('o1',3,'15:00')$$,'42501',null,'conta sem cadastro na igreja não pede');
-- busca de pessoas
reset role;select pg_temp.actor('owner');set local role authenticated;
select is((select string_agg(i->>'name',',') from jsonb_array_elements(public.pastoral_people(pg_temp.pa('org'),pg_temp.pa('a'),'membro')->'items') i),'Ana Membro,Bruno Membro','administração busca membros');
reset role;select pg_temp.actor('member');set local role authenticated;
select throws_ok($$select public.pastoral_people(pg_temp.pa('org'),pg_temp.pa('a'),'membro')$$,'42501',null,'membro comum não busca pessoas');
reset role;select pg_temp.actor('pastor');set local role authenticated;
select is(jsonb_array_length(public.pastoral_people(pg_temp.pa('org'),pg_temp.pa('a'),'membro')->'items'),0,'quem atende sem permissão ampla só vê a própria célula');
select * from finish();
rollback;
