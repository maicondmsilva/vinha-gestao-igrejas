begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Louvor · visão do músico: o voluntário escalado vê o repertório publicado do culto e confirma o ensaio.
create function pg_temp.wm(t text) returns uuid language sql immutable as $$select md5('worship-musician-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wm(t),'role','authenticated','email',t||'-musician@example.invalid')::text,true)$$;
create function pg_temp.mus(a text, d jsonb) returns jsonb language sql as $$select public.worship_musician(pg_temp.wm('org'),a,d)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.wm(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-musician@example.invalid',now(),now(),now() from unnest(array['owner','ana','bob','cris']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.wm('org'),'Louvor músico','worship-musician-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.wm('unit'),pg_temp.wm('org'),'Sede','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
select pg_temp.wm('org'),pg_temp.wm(x),case x when 'owner' then 'owner' else 'member' end::public.membership_role,'active',pg_temp.wm('unit') from unnest(array['owner','ana','bob','cris']) x;
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,status)
select pg_temp.wm(x||'-p'),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm(x),initcap(x)||' Teste','active' from unnest(array['ana','bob','cris']) x;
insert into private.scale_teams(id,organization_id,unit_id,name) values(pg_temp.wm('team'),pg_temp.wm('org'),pg_temp.wm('unit'),'Louvor');
insert into private.scale_roles(id,organization_id,unit_id,team_id,name) values(pg_temp.wm('vocal'),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm('team'),'Vocal');
insert into private.scale_members(id,organization_id,unit_id,team_id,person_id,role_id)
select pg_temp.wm(x||'-m'),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm('team'),pg_temp.wm(x||'-p'),pg_temp.wm('vocal') from unnest(array['ana','bob','cris']) x;
insert into private.scale_services(id,organization_id,unit_id,series_id,title,arrival_at,starts_at,ends_at,timezone,status,created_by)
select pg_temp.wm(x),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm(x),'Culto '||x,now()+(d||' days')::interval,now()+(d||' days')::interval+interval '30 minutes',now()+(d||' days')::interval+interval '2 hours','America/Sao_Paulo','published',pg_temp.wm('owner')
from (values('s1',3),('s2',6),('old',-10)) v(x,d);
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id)
select pg_temp.wm(s),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm('team'),pg_temp.wm('vocal'),o,pg_temp.wm(m||'-m') from (values('s1',1,'ana'),('s1',2,'cris'),('s2',1,'ana'),('old',1,'ana')) v(s,o,m);
insert into private.scale_invites(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id,person_id,deadline,response)
select pg_temp.wm(s),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm('team'),pg_temp.wm('vocal'),o,pg_temp.wm(m||'-m'),pg_temp.wm(m||'-p'),now()+interval '1 day',r
from (values('s1',1,'ana','accepted'),('s1',2,'cris','declined'),('s2',1,'ana','pending'),('old',1,'ana','accepted')) v(s,o,m,r);
insert into private.worship_songs(id,organization_id,unit_id,title,artist,original_key,bpm,time_signature,chart,links,created_by,updated_by) values
 (pg_temp.wm('song1'),pg_temp.wm('org'),pg_temp.wm('unit'),'Santo','Autor','C',72,'4/4','[C]Santo, [G]santo','{"video":"https://example.invalid/v"}',pg_temp.wm('owner'),pg_temp.wm('owner')),
 (pg_temp.wm('song2'),pg_temp.wm('org'),pg_temp.wm('unit'),'Grande é o Senhor','Autor','G',90,'4/4','[G]Grande',  '{}',pg_temp.wm('owner'),pg_temp.wm('owner'));
insert into private.worship_setlists(id,organization_id,unit_id,service_id,status,notes,updated_by) values
 (pg_temp.wm('set1'),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm('s1'),'published','Chegar às 18h para passagem de som',pg_temp.wm('owner')),
 (pg_temp.wm('set2'),pg_temp.wm('org'),pg_temp.wm('unit'),pg_temp.wm('s2'),'draft','',pg_temp.wm('owner'));
insert into private.worship_setlist_items(setlist_id,position,song_id,song_key,minister_person_id,notes) values
 (pg_temp.wm('set1'),1,pg_temp.wm('song1'),'D',pg_temp.wm('ana-p'),'Repetir o refrão'),(pg_temp.wm('set1'),2,pg_temp.wm('song2'),'',null,''),
 (pg_temp.wm('set2'),1,pg_temp.wm('song2'),'A',null,'');

select ok(not has_table_privilege('authenticated','private.worship_rehearsals','SELECT'),'confirmações de ensaio não são lidas direto');
set local role authenticated;
select pg_temp.actor('ana');
select is(jsonb_array_length(pg_temp.mus('list','{}')->'items'),1,'músico vê só cultos futuros com repertório publicado');
select is(pg_temp.mus('list','{}')#>>'{items,0,service}',pg_temp.wm('s1')::text,'lista traz o culto em que está escalado');
select is((pg_temp.mus('list','{}')#>>'{items,0,songs}')::int,2,'lista conta as músicas');
select is(jsonb_array_length(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))->'items'),2,'repertório traz as músicas em ordem');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))#>>'{items,0,dayKey}','D','tom do dia');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))#>>'{items,0,originalKey}','C','tom original para transpor');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))#>>'{items,0,chart}','[C]Santo, [G]santo','cifra completa');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))#>>'{items,0,minister}','Ana Teste','quem ministra');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))#>>'{items,1,dayKey}','G','sem tom do dia, usa o original');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))->>'notes','Chegar às 18h para passagem de som','recado do culto');
select throws_ok($$select pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s2')))$$,'42501',null,'repertório em rascunho não aparece');
select lives_ok($$select pg_temp.mus('rehearsal',jsonb_build_object('service',pg_temp.wm('s1'),'confirmed',true))$$,'confirma o ensaio');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))->>'rehearsalConfirmed','true','confirmação aparece');
select is((pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))->>'rehearsalCount')::int,1,'conta quem confirmou');
select lives_ok($$select pg_temp.mus('rehearsal',jsonb_build_object('service',pg_temp.wm('s1'),'confirmed',false))$$,'desfaz a confirmação');
select is(pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))->>'rehearsalConfirmed','false','confirmação desfeita');

select pg_temp.actor('bob');
select is(jsonb_array_length(pg_temp.mus('list','{}')->'items'),0,'quem não está escalado não vê repertório');
select throws_ok($$select pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))$$,'42501',null,'não abre repertório de culto em que não está');
select pg_temp.actor('cris');
select throws_ok($$select pg_temp.mus('view',jsonb_build_object('service',pg_temp.wm('s1')))$$,'42501',null,'quem recusou o convite não vê o repertório');
select throws_ok($$select pg_temp.mus('rehearsal',jsonb_build_object('service',pg_temp.wm('s1'),'confirmed',true))$$,'42501',null,'quem recusou não confirma ensaio');
select * from finish();
rollback;
