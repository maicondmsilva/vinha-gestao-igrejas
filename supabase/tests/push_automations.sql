begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.pa(t text) returns uuid language sql immutable as $$select md5('push-automation-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.pa(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-auto@example.invalid',now(),now(),now()
 from unnest(array['admin','secretary','birthday','other'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pa('org'),'Ministério fictício automações','push-automation-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type,communication_autonomy) values(pg_temp.pa('a'),pg_temp.pa('org'),'Sede fictícia','a','headquarters',true);
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status)
 select pg_temp.pa(t||'-m'),pg_temp.pa('org'),pg_temp.pa(t),pg_temp.pa('a'),case t when 'admin' then 'admin' when 'secretary' then 'secretary' else 'member' end::public.membership_role,'active'
 from unnest(array['admin','secretary','birthday','other'])t;
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,status,birth_date) values
 (pg_temp.pa('birthday-p'),pg_temp.pa('org'),pg_temp.pa('a'),pg_temp.pa('birthday'),'Aniversariante fictício','active',((now() at time zone 'America/Sao_Paulo')::date-interval '30 years')::date),
 (pg_temp.pa('other-p'),pg_temp.pa('org'),pg_temp.pa('a'),pg_temp.pa('other'),'Outra pessoa fictícia','active',((now() at time zone 'America/Sao_Paulo')::date-interval '30 years 2 days')::date);
insert into private.member_push_apps values(pg_temp.pa('org'),pg_temp.pa('project'),'com.vinha.autotest',true,now());
insert into auth.sessions(id,user_id) select pg_temp.pa(t||'-s'),pg_temp.pa(t) from unnest(array['birthday','other'])t;
create function pg_temp.device(t text) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated','session_id',pg_temp.pa(t||'-s'))::text,true);
 insert into private.member_push_devices(id,organization_id,user_id,unit_id,token,enabled) values(pg_temp.pa(t||'-d'),pg_temp.pa('org'),pg_temp.pa(t),pg_temp.pa('a'),'ExpoPushToken['||t||'abcdefghijk]',true);
end $$;
select pg_temp.device(t) from unnest(array['birthday','other'])t;
reset role;

select ok(not has_function_privilege('authenticated','public.live_engine(text,jsonb)','execute'),'app não altera o estado da live');
select ok(has_function_privilege('service_role','public.live_engine(text,jsonb)','execute'),'servidor altera o estado da live');
select ok(not has_function_privilege('anon','public.communication_metrics(uuid,uuid,integer)','execute'),'visitante não vê métricas');

-- Settings: only publishers read; only owner/admin/pastor change.
set local role authenticated;select pg_temp.actor('other');
select throws_ok($$select public.push_automation(md5('push-automation-test-org')::uuid,md5('push-automation-test-a')::uuid,'get')$$,'42501',null,'membro não vê automações');
select pg_temp.actor('admin');
select is(public.push_automation(pg_temp.pa('org'),pg_temp.pa('a'),'get')->>'canEdit','true','administração pode alterar');
select is(public.push_automation(pg_temp.pa('org'),pg_temp.pa('a'),'save',1,'{"birthdays":true,"livePush":true,"birthdayTitle":"Parabéns!","birthdayBody":"Deus abençoe seu novo ano"}')->>'birthdays','true','administração liga aniversários');
select throws_ok($$select public.push_automation(md5('push-automation-test-org')::uuid,md5('push-automation-test-a')::uuid,'save',1,'{"birthdays":false,"livePush":true,"birthdayTitle":"Parabéns!","birthdayBody":"Deus abençoe"}')$$,'40001',null,'versão antiga é recusada');
reset role;

-- Birthdays: one campaign per day, only the person with birthday today receives.
select is(private.push_birthdays(),1,'campanha de aniversário do dia criada');
select is(private.push_birthdays(),0,'mesma data não duplica');
set local role service_role;select public.push_engine('materialize');reset role;
select is((select count(*)::int from private.push_messages m join private.push_runs r on r.id=m.run_id join private.push_campaigns c on c.id=r.campaign_id where c.source='birthday'),1,'só o aniversariante recebe');
select is((select user_id from private.push_messages m join private.push_runs r on r.id=m.run_id join private.push_campaigns c on c.id=r.campaign_id where c.source='birthday'),pg_temp.pa('birthday'),'mensagem vai para o aniversariante');

-- Live: scheduled YouTube live becomes live, push created once, then ends.
insert into private.publishing_items(id,organization_id,owner_unit,kind,title,source,provider,scope,targets,status,live_state,starts_at,created_by)
 values(pg_temp.pa('live'),pg_temp.pa('org'),pg_temp.pa('a'),'live','Culto de celebração fictício','https://www.youtube.com/watch?v=abcdefghijk','youtube','local',array[pg_temp.pa('a')],'published','scheduled',now()-interval '5 minutes',pg_temp.pa('admin'));
set local role service_role;
select ok(exists(select 1 from jsonb_array_elements(public.live_engine('due')->'items') x where x->>'id'=md5('push-automation-test-live')::uuid::text),'live agendada entra na verificação');
select is(public.live_engine('set',jsonb_build_object('id',pg_temp.pa('live'),'state','live'))->>'changed','true','live passa a ao vivo');
select is(public.live_engine('set',jsonb_build_object('id',pg_temp.pa('live'),'state','live'))->>'changed','false','repetição não muda nada');
reset role;
select is((select live_state from private.publishing_items where id=pg_temp.pa('live')),'live','estado salvo');
select is((select live_state from private.ministry_media where publishing_id=pg_temp.pa('live') limit 1),'live','mídia do app acompanha');
select is((select count(*)::int from private.push_campaigns where source='live' and source_key='live:'||pg_temp.pa('live')),1,'um push de início de live');
select is((select link->>'screen' from private.push_campaigns where source='live'),'live','push abre a live');
set local role service_role;
select is(public.live_engine('set',jsonb_build_object('id',pg_temp.pa('live'),'state','ended'))->>'changed','true','live encerrada');
select is(public.live_engine('set',jsonb_build_object('id',pg_temp.pa('live'),'state','live'))->>'changed','false','live encerrada não volta sozinha');
reset role;

-- Metrics and banner taps
insert into private.publishing_items(id,organization_id,owner_unit,kind,title,source,scope,targets,status,created_by)
 values(pg_temp.pa('banner'),pg_temp.pa('org'),pg_temp.pa('a'),'banner','Banner fictício','https://example.com/inscricao','local',array[pg_temp.pa('a')],'published',pg_temp.pa('admin'));
set local role authenticated;select pg_temp.actor('other');
select public.publishing_click(pg_temp.pa('banner'));select public.publishing_click(pg_temp.pa('banner'));
reset role;
select is((select count(*)::int from private.publishing_clicks where item_id=pg_temp.pa('banner')),1,'clique contado uma vez por pessoa');
set local role authenticated;select pg_temp.actor('other');
select throws_ok($$select public.communication_metrics(md5('push-automation-test-org')::uuid,md5('push-automation-test-a')::uuid,30)$$,'42501',null,'membro não vê métricas');
select pg_temp.actor('admin');
select is((public.communication_metrics(pg_temp.pa('org'),pg_temp.pa('a'),30)->'push'->>'recipients')::int,1,'métricas somam destinatários');
select is((select (x->>'clicks')::int from jsonb_array_elements(public.communication_metrics(pg_temp.pa('org'),pg_temp.pa('a'),30)->'notices') x where x->>'title'='Banner fictício'),1,'métricas mostram cliques no banner');
select throws_ok($$select public.communication_metrics(md5('push-automation-test-org')::uuid,md5('push-automation-test-a')::uuid,45)$$,'22023',null,'período inválido');
reset role;
select * from finish();
rollback;
