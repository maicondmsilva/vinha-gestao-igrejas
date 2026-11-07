begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.pa(t text) returns uuid language sql immutable as $$select md5('recurrence-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.pa(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-recurrence@example.invalid',now(),now(),now() from unnest(array['owner','member'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pa('org'),'Recorrência fictícia','recurrence-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.pa('unit'),pg_temp.pa('org'),'Igreja fictícia R','r','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) select pg_temp.pa(t||'-m'),pg_temp.pa('org'),pg_temp.pa(t),pg_temp.pa('unit'),t::public.membership_role,'active' from unnest(array['owner','member'])t;
create function pg_temp.cmd(a text,i uuid default null,d jsonb default '{}') returns jsonb language sql as $$select public.programming_admin(pg_temp.pa('org'),pg_temp.pa('unit'),a,i,null,d)$$;
create function pg_temp.first() returns timestamp language sql stable as $$select make_timestamp(extract(year from now())::integer+1,1,31,19,0,0)$$;
create function pg_temp.fields(extra jsonb) returns jsonb language sql as $$select jsonb_build_object('title','Encontro fictício','description','Somente teste','kind','service','startsLocal',to_char(pg_temp.first(),'YYYY-MM-DD"T"HH24:MI'),'endsLocal',to_char(pg_temp.first()+interval '2 hours','YYYY-MM-DD"T"HH24:MI'),'location','Local fictício','address','','capacity',10,'category','','cover','')||extra$$;
create function pg_temp.starts(series_of uuid) returns text[] language sql security definer set search_path='' as $$select array_agg(to_char(starts_at at time zone 'America/Sao_Paulo','YYYY-MM-DD') order by starts_at) from private.church_app_events where series_id=(select series_id from private.church_app_events where id=series_of)$$;

create temp table made(id uuid);grant all on made to authenticated;
create temp table tok(t text);grant all on tok to authenticated;

-- Regra pura, igual a shared/recurrence.ts
select is((private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"weekly","ends":"until","until":"2030-03-31","startsLocal":"2030-03-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)->>'count')::int,5,'semanal até 31/03: 5 encontros');
select is((private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"monthly","ends":"never","startsLocal":"2030-01-31T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)->>'count')::int,12,'mensal sem término: 12 meses');
select is((private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"daily","ends":"never","startsLocal":"2030-01-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)->>'count')::int,120,'diária sem término: limite de 120');
select is((private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"yearly","ends":"until","until":"2031-12-31","startsLocal":"2030-06-10T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)->>'count')::int,2,'anual até o fim do ano seguinte');
select ok(not (private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"weekly","ends":"never","startsLocal":"2030-01-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb) ?| array['ends','until']),'remove campos de término');
select throws_ok($$select private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"daily","ends":"until","until":"2031-01-01","startsLocal":"2030-01-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)$$,'22023','programming_repeat_too_long','data muito distante');
select throws_ok($$select private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"weekly","ends":"until","until":"2029-12-01","startsLocal":"2030-01-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)$$,'22023','programming_repeat_until','data antes do início');
select throws_ok($$select private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"weekly","ends":"never","count":3,"startsLocal":"2030-01-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)$$,'22023','invalid_member_agenda','sem término não aceita quantidade');
select throws_ok($$select private.programming_repeat_count((replace(replace(replace(replace('{"repeat":"weekly","ends":"until","startsLocal":"2030-01-01T19:00"}','2029',(extract(year from now())::int+1+(-1))::text),'2030',(extract(year from now())::int+1+(0))::text),'2031',(extract(year from now())::int+1+(1))::text),'2034',(extract(year from now())::int+1+(4))::text))::jsonb)$$,'22023','invalid_member_agenda','data obrigatória');

-- Pelo painel: anual por quantidade e mensal até uma data (31 de jan → fim de fev → 31 de mar)
select pg_temp.actor('owner');set local role authenticated;
select is((pg_temp.cmd('create',pg_temp.pa('req1'),pg_temp.fields('{"repeat":"yearly","count":2,"ends":"count"}'))->>'count')::int,2,'série anual criada');
select throws_ok($$select pg_temp.cmd('create',pg_temp.pa('req3'),pg_temp.fields('{"repeat":"yearly","count":4,"ends":"count"}'))$$,'22023','programming_repeat_horizon','agenda aceita até 2 anos à frente');
insert into made select (pg_temp.cmd('create',pg_temp.pa('req2'),pg_temp.fields(jsonb_build_object('repeat','monthly','ends','until','until',to_char(pg_temp.first()+interval '2 months','YYYY-MM-DD'))))->>'id')::uuid;
reset role;
select is(array_length(pg_temp.starts((select id from made)),1),3,'mensal até a data: 3 encontros');
select is((pg_temp.starts((select id from made)))[2],to_char((pg_temp.first()+interval '1 month')::date,'YYYY-MM-DD'),'fevereiro no último dia do mês');

-- Assinatura (.ics)
select is(public.agenda_feed(repeat('a',40)),null,'link inexistente');
select is(public.agenda_feed('nao-hex'),null,'formato inválido');
set local role authenticated;select pg_temp.actor('member');
select throws_ok($$select public.agenda_feed_admin(pg_temp.pa('org'),pg_temp.pa('unit'),'rotate')$$,'42501',null,'membro não cria link');
select pg_temp.actor('owner');
select is(public.agenda_feed_admin(pg_temp.pa('org'),pg_temp.pa('unit'),'get')->>'token',null,'sem link no início');
insert into tok select public.agenda_feed_admin(pg_temp.pa('org'),pg_temp.pa('unit'),'rotate')->>'token';
reset role;
select is(jsonb_array_length(public.agenda_feed((select t from tok))->'events'),0,'rascunhos não aparecem');
update private.church_app_events set status='published' where series_id is not null and organization_id=pg_temp.pa('org');
set local role anon;
select ok(jsonb_array_length(public.agenda_feed((select t from tok))->'events')>=3,'eventos publicados aparecem para quem tem o link');
select is(public.agenda_feed((select t from tok))->>'timezone','America/Sao_Paulo','fuso da igreja no feed');
reset role;
set local role authenticated;select pg_temp.actor('owner');
select isnt(public.agenda_feed_admin(pg_temp.pa('org'),pg_temp.pa('unit'),'rotate')->>'token',(select t from tok),'trocar gera outro link');
reset role;
select is(public.agenda_feed((select t from tok)),null,'link antigo deixa de funcionar');
set local role authenticated;select pg_temp.actor('owner');
select is(public.agenda_feed_admin(pg_temp.pa('org'),pg_temp.pa('unit'),'disable')->>'token',null,'link desativado');
reset role;
select ok(not has_table_privilege('anon','private.agenda_feeds','select'),'tabela de links sem acesso direto');
select is((select count(*)::int from public.audit_logs where organization_id=pg_temp.pa('org') and action like 'agenda.feed.%'),3,'auditoria do link');
select * from finish();
rollback;
