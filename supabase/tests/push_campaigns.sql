begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.pc(t text) returns uuid language sql immutable as $$select md5('push-campaign-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pc(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.pc(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-push@example.invalid',now(),now(),now()
 from unnest(array['admin','young','adult','cellmate','deceased','plain'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pc('org'),'Ministério fictício push','push-campaign-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.pc('a'),pg_temp.pc('org'),'Sede fictícia','a','headquarters'),(pg_temp.pc('b'),pg_temp.pc('org'),'Filial fictícia','b','campus');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status)
 select pg_temp.pc(t||'-m'),pg_temp.pc('org'),pg_temp.pc(t),pg_temp.pc('a'),case when t='admin' then 'admin'::public.membership_role else 'member'::public.membership_role end,'active'
 from unnest(array['admin','young','adult','cellmate','deceased','plain'])t;
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,status,birth_date) values
 (pg_temp.pc('young-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('young'),'Jovem fictício','active',current_date-interval '16 years'),
 (pg_temp.pc('adult-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('adult'),'Adulto fictício','active',current_date-interval '40 years'),
 (pg_temp.pc('cellmate-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('cellmate'),'Celular fictício','active',current_date-interval '30 years'),
 (pg_temp.pc('deceased-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('deceased'),'Falecido fictício','deceased',current_date-interval '70 years');
insert into private.member_push_apps values(pg_temp.pc('org'),pg_temp.pc('project'),'com.vinha.pushtest',true,now());
insert into auth.sessions(id,user_id) select pg_temp.pc(t||'-s'),pg_temp.pc(t) from unnest(array['young','adult','cellmate','deceased','plain'])t;
insert into private.member_push_devices(id,organization_id,user_id,unit_id,token,enabled,session_id)
 select pg_temp.pc(t||'-d'),pg_temp.pc('org'),pg_temp.pc(t),pg_temp.pc('a'),'ExpoPushToken['||t||'abcdefghijk]',true,pg_temp.pc(t||'-s')
 from unnest(array['young','adult','cellmate','deceased','plain'])t;

create function pg_temp.adm(a text,d jsonb default '{}',id uuid default null,v int default null) returns jsonb language sql as $$select public.push_admin(md5('push-campaign-test-org')::uuid,md5('push-campaign-test-a')::uuid,a,id,v,d)$$;
create function pg_temp.body(extra jsonb default '{}') returns jsonb language sql as $$select jsonb_build_object('title','Culto de domingo','body','Hoje às 19h, traga sua família!','targets',jsonb_build_array(md5('push-campaign-test-a')::uuid),'link',jsonb_build_object('screen','agenda'),'audience','{}'::jsonb)||extra$$;

-- Privileges
select ok(not has_function_privilege('anon','public.push_admin(uuid,uuid,text,uuid,integer,jsonb)','execute'),'visitante não usa o painel de push');
select ok(not has_function_privilege('authenticated','public.push_engine(text,jsonb)','execute'),'app não aciona o motor de envio');
select ok(has_function_privilege('service_role','public.push_engine(text,jsonb)','execute'),'servidor aciona o motor');
select ok(not has_table_privilege('authenticated','private.push_messages','select'),'cliente não lê a fila');

-- A plain member cannot send.
set local role authenticated;select pg_temp.actor('plain');
select throws_ok($$select pg_temp.adm('preview',pg_temp.body())$$,'42501',null,'membro comum não envia push');
reset role;

-- Audience counts
set local role authenticated;select pg_temp.actor('admin');
select is((pg_temp.adm('preview',pg_temp.body())->>'devices')::int,4,'todos os aparelhos ativos, sem o de pessoa falecida');
select is((pg_temp.adm('preview',pg_temp.body(jsonb_build_object('audience',jsonb_build_object('ageMax',17))))->>'devices')::int,1,'filtro de idade máxima');
select is((pg_temp.adm('preview',pg_temp.body(jsonb_build_object('audience',jsonb_build_object('ageMin',18,'ageMax',35))))->>'devices')::int,1,'faixa etária');
select is((pg_temp.adm('preview',pg_temp.body(jsonb_build_object('audience',jsonb_build_object('roles',jsonb_build_array('admin')))))->>'devices')::int,0,'filtro por papel');
select throws_ok($$select pg_temp.adm('preview',pg_temp.body(jsonb_build_object('audience',jsonb_build_object('everyone',true))))$$,'22023',null,'filtro desconhecido é recusado');
select throws_ok($$select pg_temp.adm('preview',pg_temp.body(jsonb_build_object('targets',jsonb_build_array(md5('push-campaign-test-elsewhere')::uuid))))$$,'42501',null,'igreja fora do acesso é recusada');
select throws_ok($$select pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','now','request',md5('push-campaign-test-r0')::uuid,'link',jsonb_build_object('screen','event'))))$$,'22023',null,'link de evento exige o evento');

select is(jsonb_array_length(pg_temp.adm('options')->'units'),2,'opções listam as igrejas permitidas');
-- Create, idempotency, edit lock
select is(pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','now','request',md5('push-campaign-test-r1')::uuid)))->'campaign'->>'status','scheduled','envio imediato entra na fila');
select is(pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','now','request',md5('push-campaign-test-r1')::uuid)))->>'repeated','true','mesmo pedido não duplica a campanha');
select is(pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','draft','request',md5('push-campaign-test-r2')::uuid)))->'campaign'->>'status','draft','rascunho');
reset role;
select is((select count(*)::int from private.push_campaigns where organization_id=pg_temp.pc('org')),2,'duas campanhas');

-- Engine
set local role service_role;
select is((public.push_engine('materialize')->>'runs')::int,1,'materializa só a campanha devida');
reset role;
select is((select count(*)::int from private.push_messages),4,'uma mensagem por aparelho elegível');
select is((select status from private.push_campaigns where request_id=pg_temp.pc('r1')),'sending','campanha única passa a enviar');
set local role service_role;
create temp table claimed as select public.push_engine('claim',jsonb_build_object('limit',100)) j;
reset role;
select is(jsonb_array_length((select j->'items' from claimed)),4,'lote entregue ao servidor');
select is((select j->'items'->0->>'title' from claimed),'Culto de domingo','título real da campanha');
select is((select j->'items'->0->'data'->>'screen' from claimed),'agenda','link para a tela certa');
set local role service_role;
select is(jsonb_array_length(public.push_engine('claim')->'items'),0,'segunda chamada não reenvia');
select lives_ok($$select public.push_engine('settle',jsonb_build_object('items',(select jsonb_agg(jsonb_build_object('id',x->>'id','state',case when x->>'token' like '%plain%' then 'failed' else 'submitted' end,'ticket','t-'||(x->>'id'),'error',case when x->>'token' like '%plain%' then 'DeviceNotRegistered' end)) from claimed,jsonb_array_elements(j->'items') x)))$$,'resultados registrados');
reset role;
select is((select enabled from private.member_push_devices where id=pg_temp.pc('plain-d')),false,'aparelho desinstalado é desligado');
select is((select count(*)::int from private.push_messages where state='submitted'),3,'enviados confirmados');
set local role service_role;select public.push_engine('materialize');reset role;
select is((select status from private.push_campaigns where request_id=pg_temp.pc('r1')),'sent','campanha concluída quando nada está pendente');

-- Edit and cancel rules
set local role authenticated;select pg_temp.actor('admin');
select throws_ok(format($$select pg_temp.adm('edit',pg_temp.body(jsonb_build_object('mode','now')),%L::uuid,1)$$,(select id from private.push_campaigns where request_id=pg_temp.pc('r1'))),'40001',null,'campanha já enviada não é editada');
select is(pg_temp.adm('cancel','{}',(select id from private.push_campaigns where request_id=pg_temp.pc('r2')),1)->'campaign'->>'status','cancelled','rascunho cancelado');
select is((pg_temp.adm('detail','{}',(select id from private.push_campaigns where request_id=pg_temp.pc('r1')))->'stats'->>'delivered')::int,3,'estatísticas de entrega');
reset role;

-- Opened metric: only the recipient can mark it.
set local role authenticated;select pg_temp.actor('admin');
select public.push_opened((select id from private.push_messages where user_id=pg_temp.pc('adult')));
reset role;
select is((select opened_at from private.push_messages where user_id=pg_temp.pc('adult')),null,'outra pessoa não marca abertura');
set local role authenticated;select pg_temp.actor('adult');
select public.push_opened((select id from private.push_messages where user_id=pg_temp.pc('adult')));
reset role;
select isnt((select opened_at from private.push_messages where user_id=pg_temp.pc('adult')),null,'destinatário marca abertura');

-- Recurrence keeps the campaign scheduled for the next occurrence.
set local role authenticated;select pg_temp.actor('admin');
select pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','now','recurrence','weekly','request',md5('push-campaign-test-r3')::uuid)));
reset role;
set local role service_role;select public.push_engine('materialize');reset role;
select is((select status from private.push_campaigns where request_id=pg_temp.pc('r3')),'scheduled','recorrente continua agendada');
select ok((select next_run_at>now()+interval '6 days' from private.push_campaigns where request_id=pg_temp.pc('r3')),'próxima ocorrência em uma semana');
select * from finish();
rollback;
