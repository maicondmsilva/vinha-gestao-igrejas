begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Louvor (L1): repertório, repertório do culto ligado à Escala, permissões e histórico.
create function pg_temp.wi(t text) returns uuid language sql immutable as $$select md5('worship-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wi(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.wi(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-worship@example.invalid',now(),now(),now() from unnest(array['owner','leader','musician','outsider']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.wi('org'),'Louvor fictício','worship-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.wi('unit'),pg_temp.wi('org'),'Sede louvor','sede','headquarters'),(pg_temp.wi('other'),pg_temp.wi('org'),'Outra louvor','outra','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.wi('owner-m'),pg_temp.wi('org'),pg_temp.wi('owner'),'owner','active',pg_temp.wi('unit')),
 (pg_temp.wi('leader-m'),pg_temp.wi('org'),pg_temp.wi('leader'),'member','active',pg_temp.wi('unit')),
 (pg_temp.wi('musician-m'),pg_temp.wi('org'),pg_temp.wi('musician'),'member','active',pg_temp.wi('unit'));
insert into public.people(id,organization_id,unit_id,full_name,status) values
 (pg_temp.wi('p-ana'),pg_temp.wi('org'),pg_temp.wi('unit'),'Ana Vocal','active'),(pg_temp.wi('p-beto'),pg_temp.wi('org'),pg_temp.wi('unit'),'Beto Violão','active');
-- Equipes de escala: Louvor e Mídia; um culto passado e um futuro com a equipe de Louvor.
insert into private.scale_teams(id,organization_id,unit_id,name) values(pg_temp.wi('t-louvor'),pg_temp.wi('org'),pg_temp.wi('unit'),'Louvor'),(pg_temp.wi('t-midia'),pg_temp.wi('org'),pg_temp.wi('unit'),'Mídia');
insert into private.scale_roles(id,organization_id,unit_id,team_id,name) values(pg_temp.wi('r-vocal'),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('t-louvor'),'Vocal'),(pg_temp.wi('r-cam'),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('t-midia'),'Câmera');
insert into private.scale_members(id,organization_id,unit_id,team_id,person_id,role_id) values(pg_temp.wi('m-ana'),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('t-louvor'),pg_temp.wi('p-ana'),pg_temp.wi('r-vocal'));
insert into private.scale_services(id,organization_id,unit_id,series_id,title,arrival_at,starts_at,ends_at,timezone,status,created_by)
select pg_temp.wi(s),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('series'),t,d-interval '1 hour',d,d+interval '2 hours','America/Sao_Paulo','published',pg_temp.wi('owner')
from (values('past','Culto passado',now()-interval '7 days'),('next','Culto de domingo',now()+interval '3 days'),('midia','Culto só mídia',now()+interval '5 days')) v(s,t,d);
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal,member_id) values
 (pg_temp.wi('next'),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('t-louvor'),pg_temp.wi('r-vocal'),1,pg_temp.wi('m-ana')),
 (pg_temp.wi('past'),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('t-louvor'),pg_temp.wi('r-vocal'),1,pg_temp.wi('m-ana')),
 (pg_temp.wi('midia'),pg_temp.wi('org'),pg_temp.wi('unit'),pg_temp.wi('t-midia'),pg_temp.wi('r-cam'),1,null);
create function pg_temp.songs(a text,d jsonb default '{}') returns jsonb language sql as $$select public.worship_songs(pg_temp.wi('org'),pg_temp.wi('unit'),a,d)$$;
create function pg_temp.sets(a text,d jsonb default '{}') returns jsonb language sql as $$select public.worship_setlists(pg_temp.wi('org'),pg_temp.wi('unit'),a,d)$$;
create function pg_temp.song(t text,title text,v integer default 0,extra jsonb default '{}') returns jsonb language sql as $$select pg_temp.songs('save',jsonb_build_object('id',pg_temp.wi(t),'version',v,'title',title,'artist','Ministério fictício','originalKey','G','bpm','72','timeSignature','4/4','chart','[G]Santo, [D]santo','tags',jsonb_build_array('Adoração','ceia'))||extra)$$;

select ok(not has_table_privilege('authenticated','private.worship_songs','select'),'repertório sem leitura direta');
select ok(not has_function_privilege('anon','public.worship_songs(uuid,uuid,text,jsonb)','execute'),'visitante sem acesso');
select ok(exists(select 1 from private.permission_catalog where code='worship.setlists' and 'scale_team'=any(group_kinds)),'catálogo com Repertório do culto limitado por equipe');

set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.song('s1','Santo')$$,'dono cadastra música');
select lives_ok($$select pg_temp.song('s2','Grande é o Senhor',0,'{"originalKey":"A","tags":["celebração"]}')$$,'segunda música');
select lives_ok($$select pg_temp.song('s1','Santo')$$,'repetição do mesmo envio não duplica');
select throws_ok($$select pg_temp.song('s9','santo ')$$,'23505',null,'mesmo título e artista não duplica');
select throws_ok($$select pg_temp.song('s8','Tom errado',0,'{"originalKey":"H"}')$$,'23514',null,'tom inválido recusado');
select is(pg_temp.songs('list')->>'total','2','lista o repertório da igreja');
select is(pg_temp.songs('list','{"tag":"ceia"}')->>'total','1','filtra por etiqueta (minúsculas)');
select is(pg_temp.songs('list','{"search":"grande"}')->'items'->0->>'title','Grande é o Senhor','busca por título');
select throws_ok($$select pg_temp.song('s1','Santo editado',5)$$,'40001',null,'versão antiga não sobrescreve');
select lives_ok($$select pg_temp.song('s1','Santo',1,'{"status":"rehearsal"}')$$,'edita com a versão certa');

-- Repertório do culto.
select is(jsonb_array_length(pg_temp.sets('services')->'items'),3,'lista os cultos da escala');
select lives_ok($$select pg_temp.sets('save',jsonb_build_object('service',pg_temp.wi('next'),'version',0,'notes','Ensaio sábado 18h','items',jsonb_build_array(
 jsonb_build_object('song',pg_temp.wi('s2'),'key','B','minister',pg_temp.wi('p-ana')),jsonb_build_object('song',pg_temp.wi('s1')))))$$,'monta o repertório do culto');
select is((select string_agg(x->>'title'||':'||(x->>'key'),', ') from jsonb_array_elements(pg_temp.sets('get',jsonb_build_object('service',pg_temp.wi('next')))->'items') x),'Grande é o Senhor:B, Santo:G','ordem e tom do dia (sem tom = original)');
select is(pg_temp.sets('get',jsonb_build_object('service',pg_temp.wi('next')))->'team'->0->>'name','Ana Vocal','mostra quem está escalado no culto');
select throws_ok($$select pg_temp.sets('save',jsonb_build_object('service',pg_temp.wi('next'),'version',0,'items','[]'::jsonb))$$,'40001',null,'versão do repertório protegida');
select throws_ok($$select pg_temp.sets('save',jsonb_build_object('service',pg_temp.wi('next'),'version',1,'items',jsonb_build_array(jsonb_build_object('song',extensions.gen_random_uuid()))))$$,'22023',null,'música de fora do repertório recusada');
select lives_ok($$select pg_temp.sets('publish',jsonb_build_object('service',pg_temp.wi('next'),'version',1))$$,'publica o repertório');
select lives_ok($$select pg_temp.sets('save',jsonb_build_object('service',pg_temp.wi('past'),'version',0,'items',jsonb_build_array(jsonb_build_object('song',pg_temp.wi('s2'),'key','A'))))$$,'repertório do culto passado');
select lives_ok($$select pg_temp.sets('publish',jsonb_build_object('service',pg_temp.wi('past'),'version',1))$$,'publica o passado');
select is((select x->>'times_played' from jsonb_array_elements(pg_temp.songs('list')->'items') x where x->>'title'='Grande é o Senhor'),'1','histórico conta só cultos que já aconteceram');
select throws_ok($$select pg_temp.songs('delete',jsonb_build_object('id',pg_temp.wi('s2'),'version',1))$$,'23503',null,'música já usada não é excluída (arquivar)');

-- Permissões concedidas: líder de louvor limitado à equipe Louvor.
select pg_temp.actor('leader');
select throws_ok($$select pg_temp.songs('list')$$,'42501',null,'sem permissão não vê o repertório');
select pg_temp.actor('owner');
select lives_ok($$select public.permission_admin(pg_temp.wi('org'),'set',jsonb_build_object('membership',pg_temp.wi('leader-m'),'permission','worship.songs','unit',pg_temp.wi('unit'),'actions',jsonb_build_array('view','create','edit'),'includeChildren',false))$$,'concede Repertório');
select lives_ok($$select public.permission_admin(pg_temp.wi('org'),'set',jsonb_build_object('membership',pg_temp.wi('leader-m'),'permission','worship.setlists','unit',pg_temp.wi('unit'),'actions',jsonb_build_array('view','edit'),'includeChildren',false,'groupKind','scale_team','groups',jsonb_build_array(pg_temp.wi('t-louvor'))))$$,'concede Repertório do culto só na equipe Louvor');
select pg_temp.actor('leader');
select is(pg_temp.songs('list')->>'canDelete','false','sem excluir');
select lives_ok($$select pg_temp.song('s3','Nova canção')$$,'líder cadastra música');
select is((select string_agg(x->>'title',', ' order by x->>'title') from jsonb_array_elements(pg_temp.sets('services')->'items') x),'Culto de domingo, Culto passado','vê só os cultos da equipe Louvor');
select lives_ok($$select pg_temp.sets('save',jsonb_build_object('service',pg_temp.wi('next'),'version',2,'items',jsonb_build_array(jsonb_build_object('song',pg_temp.wi('s3'),'key','C'))))$$,'edita o repertório do culto da equipe');
select throws_ok($$select pg_temp.sets('get',jsonb_build_object('service',pg_temp.wi('midia')))$$,'42501',null,'culto de outra equipe fechado');
select throws_ok($$select pg_temp.sets('publish',jsonb_build_object('service',pg_temp.wi('next'),'version',3))$$,'42501',null,'publicar exige aprovar');
select throws_ok($$select public.worship_songs(pg_temp.wi('org'),pg_temp.wi('other'),'list','{}')$$,'42501',null,'outra igreja fechada');
reset role;
select * from finish();
rollback;
