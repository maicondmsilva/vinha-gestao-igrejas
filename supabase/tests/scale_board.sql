begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Escalas · quadro de montagem: funções × cultos do período, escalar várias datas e publicar em lote.
create function pg_temp.sb(t text) returns uuid language sql immutable as $$select md5('scale-board-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.sb(t),'role','authenticated','email',t||'-board@example.invalid')::text,true)$$;
create function pg_temp.board(a text, d jsonb) returns jsonb language sql as $$select public.scale_board(pg_temp.sb('org'),pg_temp.sb('unit'),a,d)$$;
create function pg_temp.ver(s text) returns int language sql security definer as $$select version from private.scale_services where id=pg_temp.sb(s)$$;
create function pg_temp.cell(s text, r text, o int) returns uuid language sql security definer as $$select member_id from private.scale_positions where service_id=pg_temp.sb(s) and role_id=pg_temp.sb(r) and ordinal=o$$;
create function pg_temp.status(s text) returns text language sql security definer as $$select status from private.scale_services where id=pg_temp.sb(s)$$;
create function pg_temp.set(s text, r text, o int, m text) returns jsonb language sql as $$select pg_temp.board('assign',jsonb_build_object('service',pg_temp.sb(s),'role',pg_temp.sb(r),'ordinal',o,'member',case when m is null then null else pg_temp.sb(m) end,'version',pg_temp.ver(s)))$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.sb(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-board@example.invalid',now(),now(),now() from unnest(array['owner','outsider']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.sb('org'),'Quadro fictício','scale-board-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.sb('unit'),pg_temp.sb('org'),'Sede quadro','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.sb('org'),pg_temp.sb('owner'),'owner','active',pg_temp.sb('unit')),(pg_temp.sb('org'),pg_temp.sb('outsider'),'member','active',pg_temp.sb('unit'));
insert into public.people(id,organization_id,unit_id,full_name,status) values
 (pg_temp.sb('ana-p'),pg_temp.sb('org'),pg_temp.sb('unit'),'Ana Porta','active'),(pg_temp.sb('bia-p'),pg_temp.sb('org'),pg_temp.sb('unit'),'Bia Porta','active'),(pg_temp.sb('caio-p'),pg_temp.sb('org'),pg_temp.sb('unit'),'Caio Café','active');
insert into private.scale_teams(id,organization_id,unit_id,name) values(pg_temp.sb('team'),pg_temp.sb('org'),pg_temp.sb('unit'),'Recepção');
insert into private.scale_roles(id,organization_id,unit_id,team_id,name,required_count) values
 (pg_temp.sb('porta'),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb('team'),'Porta',2),(pg_temp.sb('cafe'),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb('team'),'Café',1);
insert into private.scale_members(id,organization_id,unit_id,team_id,person_id,role_id) values
 (pg_temp.sb('ana'),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb('team'),pg_temp.sb('ana-p'),pg_temp.sb('porta')),
 (pg_temp.sb('bia'),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb('team'),pg_temp.sb('bia-p'),pg_temp.sb('porta')),
 (pg_temp.sb('caio'),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb('team'),pg_temp.sb('caio-p'),pg_temp.sb('cafe'));
insert into private.scale_services(id,organization_id,unit_id,series_id,title,arrival_at,starts_at,ends_at,timezone,created_by)
select pg_temp.sb(x),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb(x),'Culto '||x,date_trunc('day',now())+(d||' days')::interval+interval '21 hours 30 minutes',date_trunc('day',now())+(d||' days')::interval+interval '22 hours',date_trunc('day',now())+(d||' days')::interval+interval '23 hours 30 minutes','America/Sao_Paulo',pg_temp.sb('owner')
from (values('s1',7),('s2',14),('s3',90)) v(x,d);
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal)
select pg_temp.sb(s),pg_temp.sb('org'),pg_temp.sb('unit'),pg_temp.sb('team'),pg_temp.sb(r),o from unnest(array['s1','s2','s3']) s,(values('porta',1),('porta',2),('cafe',1)) v(r,o);
create function pg_temp.range() returns jsonb language sql as $$select jsonb_build_object('from',(current_date)::text,'to',(current_date+30)::text)$$;

set local role authenticated;
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.board('view',pg_temp.range())$$,'42501',null,'sem acesso a Escalas não vê o quadro');
select pg_temp.actor('owner');
select is(jsonb_array_length(pg_temp.board('view',pg_temp.range())->'services'),2,'quadro mostra os cultos do período');
select is(jsonb_array_length(pg_temp.board('view',pg_temp.range())->'rows'),3,'linhas são as funções com suas vagas');
select is(jsonb_array_length(pg_temp.board('view',pg_temp.range())->'cells'),6,'uma célula por vaga e culto');
select throws_ok($$select pg_temp.board('view',jsonb_build_object('from',current_date::text,'to',(current_date+90)::text))$$,'22023',null,'período longo demais recusado');

-- Escalar no rascunho
select lives_ok($$select pg_temp.set('s1','porta',1,'ana')$$,'escala Ana na porta do culto 1');
select is(pg_temp.cell('s1','porta',1),pg_temp.sb('ana'),'vaga preenchida');
select throws_ok($$select pg_temp.set('s1','porta',2,'ana')$$,'22023',null,'mesma pessoa duas vezes no culto recusada');
select throws_ok($$select pg_temp.set('s1','cafe',1,'ana')$$,'22023',null,'pessoa sem a função recusada');
select throws_ok($$select pg_temp.board('assign',jsonb_build_object('service',pg_temp.sb('s1'),'role',pg_temp.sb('porta'),'ordinal',2,'member',pg_temp.sb('bia'),'version',1))$$,'40001',null,'versão antiga recusada');
select lives_ok($$select pg_temp.set('s1','porta',2,'bia')$$,'escala Bia');
select lives_ok($$select pg_temp.set('s1','cafe',1,'caio')$$,'escala Caio');
select lives_ok($$select pg_temp.set('s1','porta',1,null)$$,'tira a pessoa da vaga');
select is(pg_temp.cell('s1','porta',1),null,'vaga volta a ficar aberta');
select lives_ok($$select pg_temp.set('s1','porta',1,'ana')$$,'escala Ana de novo');

-- Indisponibilidade aparece no quadro e exige confirmação na publicação
reset role;
insert into private.scale_availability(id,organization_id,person_id,kind,starts_at,ends_at,reason)
select gen_random_uuid(),pg_temp.sb('org'),pg_temp.sb('bia-p'),'unavailable',starts_at-interval '1 day',ends_at+interval '1 day','Viagem' from private.scale_services where id=pg_temp.sb('s2');
set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.set('s2','porta',1,'bia')$$,'rascunho aceita pessoa indisponível (só marca)');
select is((select c->'conflicts' from jsonb_array_elements(pg_temp.board('view',pg_temp.range())->'cells') c where c->>'service'=pg_temp.sb('s2')::text and c->>'role'=pg_temp.sb('porta')::text and (c->>'ordinal')::int=1),'["unavailable"]'::jsonb,'quadro marca a indisponibilidade');

-- Publicar em lote
select is((pg_temp.board('publish',jsonb_build_object('services',jsonb_build_array(pg_temp.sb('s1'),pg_temp.sb('s2'))))->'published'),jsonb_build_array(pg_temp.sb('s1')),'publica o culto sem conflito');
select is((pg_temp.board('publish',jsonb_build_object('services',jsonb_build_array(pg_temp.sb('s2'))))#>>'{failed,0,id}'),pg_temp.sb('s2')::text,'culto com conflito não é publicado sem confirmação');
select is(pg_temp.status('s1'),'published','culto 1 publicado');
select is(pg_temp.status('s2'),'draft','culto 2 continua rascunho');
reset role;
select is((select count(*)::int from private.scale_invites where service_id=pg_temp.sb('s1') and active),3,'publicar convida os escalados');
set local role authenticated;
select pg_temp.actor('owner');
select is((pg_temp.board('publish',jsonb_build_object('services',jsonb_build_array(pg_temp.sb('s2')),'override',true,'reason','Bia confirmou que volta antes do culto')))->'published',jsonb_build_array(pg_temp.sb('s2')),'publica com confirmação e motivo');

-- Culto publicado: vaga aberta preenchida pelo quadro vira convite; tirar alguém não é pelo quadro
select lives_ok($$select pg_temp.set('s2','porta',2,'ana')$$,'preenche vaga aberta de culto publicado');
reset role;
select is((select count(*)::int from private.scale_invites where service_id=pg_temp.sb('s2') and member_id=pg_temp.sb('ana') and active),1,'vaga preenchida no publicado gera convite');
set local role authenticated;
select pg_temp.actor('owner');
select throws_ok($$select pg_temp.set('s1','porta',1,null)$$,'22023',null,'no publicado, troca é pelo pedido de substituição');
select is((select c->>'response' from jsonb_array_elements(pg_temp.board('view',pg_temp.range())->'cells') c where c->>'service'=pg_temp.sb('s1')::text and c->>'role'=pg_temp.sb('porta')::text and (c->>'ordinal')::int=1),'pending','quadro mostra a resposta do convite');
reset role;
select ok((select count(*) from private.scale_service_history where service_id=pg_temp.sb('s1') and action='board.assign')>=3,'quadro registra o histórico');
select * from finish();
rollback;
