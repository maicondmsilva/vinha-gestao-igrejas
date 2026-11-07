begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.ch(t text) returns uuid language sql immutable as $$select md5('chat-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ch(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.ch(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-chat@example.invalid',now(),now(),now() from unnest(array['owner','ana','bia','caio','teen','leader','r3','outsider'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.ch('org'),'Chat fictício','chat-test','active'),(pg_temp.ch('org2'),'Outro ministério fictício','chat-test-other','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ch('unit'),pg_temp.ch('org'),'Sede fictícia','s','headquarters'),(pg_temp.ch('unit2'),pg_temp.ch('org2'),'Sede de outro ministério','o','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status)
 select pg_temp.ch(t||'-m'),pg_temp.ch('org'),pg_temp.ch(t),pg_temp.ch('unit'),case t when 'owner' then 'owner' when 'leader' then 'leader' else 'member' end::public.membership_role,'active'
 from unnest(array['owner','ana','bia','caio','teen','leader','r3'])t;
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values(pg_temp.ch('outsider-m'),pg_temp.ch('org2'),pg_temp.ch('outsider'),pg_temp.ch('unit2'),'owner','active');
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,birth_date,status)
 select pg_temp.ch(t||'-p'),pg_temp.ch('org'),pg_temp.ch('unit'),pg_temp.ch(t),initcap(t)||' da Silva Fictícia',case t when 'teen' then current_date-interval '15 years' else current_date-interval '30 years' end,'active'
 from unnest(array['ana','bia','caio','teen','leader','r3'])t;
create function pg_temp.c(a text,d jsonb default '{}') returns jsonb language sql as $$select public.chat(pg_temp.ch('org'),a,d)$$;
create temp table ids(k text primary key,v uuid);
grant all on ids to authenticated;

select ok(not has_function_privilege('anon','public.chat(uuid,text,jsonb)','execute'),'visitante não usa o chat');
select ok(not has_table_privilege('authenticated','private.chat_messages','select'),'mensagens sem acesso direto');
select ok(exists(select 1 from pg_policies where schemaname='realtime' and policyname='vinha_chat_listen'),'política do tempo real criada');

set local role authenticated;
-- Moderação cria canais
select pg_temp.actor('owner');
insert into ids select 'geral',(pg_temp.c('room_save',jsonb_build_object('unit',pg_temp.ch('unit'),'name','Geral','description','Conversa da igreja','audience','members','posting','all'))->>'id')::uuid;
insert into ids select 'equipe',(pg_temp.c('room_save',jsonb_build_object('unit',pg_temp.ch('unit'),'name','Equipe','audience','staff','posting','all'))->>'id')::uuid;
insert into ids select 'mural',(pg_temp.c('room_save',jsonb_build_object('unit',pg_temp.ch('unit'),'name','Mural','audience','members','posting','moderators'))->>'id')::uuid;
select throws_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','oi','client',gen_random_uuid()))$$,'42501','chat_adult_only','responsável sem cadastro de pessoa não conversa');
select is(jsonb_array_length(pg_temp.c('rooms')->'rooms'),3,'moderação vê os canais sem cadastro de pessoa');

select pg_temp.actor('ana');
select throws_ok($$select pg_temp.c('room_save',jsonb_build_object('unit',pg_temp.ch('unit'),'name','Meu canal','audience','members','posting','all'))$$,'42501','chat_denied','membro não cria canal');
select is(jsonb_array_length(pg_temp.c('rooms')->'rooms'),2,'membro não vê o canal da equipe');
select throws_ok($$select pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='equipe')))$$,'42501','chat_denied','membro não lê o canal da equipe');
select is(pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','  Bom dia, igreja!  ','client',pg_temp.ch('c1')))->'message'->>'body','Bom dia, igreja!','mensagem enviada');
select is(pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','repetida','client',pg_temp.ch('c1')))->'message'->>'body','Bom dia, igreja!','reenvio com o mesmo id não duplica');
select is(pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))->'messages'->0->>'sender','Ana F.','nome curto de quem enviou');
select is(pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))->'messages'->0->'senderId','null'::jsonb,'membro não vê o id de quem enviou');
select throws_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='mural'),'body','oi','client',gen_random_uuid()))$$,'42501','chat_read_only','mural só para moderação');
select throws_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body',repeat('a',2001),'client',gen_random_uuid()))$$,'22023','invalid_chat','mensagem longa demais');

-- Adolescente fica fora
select pg_temp.actor('teen');
select throws_ok($$select pg_temp.c('rooms')$$,'42501','chat_adult_only','menor de 18 não usa o chat');
-- Outro ministério
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))$$,'42501','chat_adult_only','outro ministério não lê');

-- Liderança vê o canal da equipe
select pg_temp.actor('leader');
select is(jsonb_array_length(pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='equipe')))->'messages'),0,'liderança lê o canal da equipe');

-- Não lidas
select pg_temp.actor('bia');
select is((select (r->>'unread')::int from jsonb_array_elements(pg_temp.c('rooms')->'rooms') r where r->>'name'='Geral'),1,'uma mensagem não lida');
select lives_ok($$select pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))$$,'abrir a conversa');
select is((select (r->>'unread')::int from jsonb_array_elements(pg_temp.c('rooms')->'rooms') r where r->>'name'='Geral'),0,'abrir marca como lida');

-- Denúncias: três ocultam
insert into ids select 'm1',(pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','Mensagem ruim fictícia','client',pg_temp.ch('c2')))->'message'->>'id')::uuid;
select throws_ok($$select pg_temp.c('report',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1'),'reason','spam'))$$,'42501','chat_denied','não denuncia a própria mensagem');
select pg_temp.actor('ana');select pg_temp.c('report',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1'),'reason','ofensa'));
select is(pg_temp.c('report',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1'),'reason','ofensa'))->>'hidden','false','denúncia repetida conta uma vez');
select pg_temp.actor('caio');select pg_temp.c('report',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1'),'reason','spam'));
select pg_temp.actor('r3');
select is(pg_temp.c('report',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1'),'reason','assedio'))->>'hidden','true','terceira denúncia oculta');
select is((select m->>'body' from jsonb_array_elements(pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))->'messages') m where m->>'id'=(select v::text from ids where k='m1')),'','membro não lê a mensagem oculta');

-- Moderação
select pg_temp.actor('owner');
select is((pg_temp.c('reports')->'reports'->0->>'count')::int,3,'fila de denúncias');
select is((select m->>'body' from jsonb_array_elements(pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))->'messages') m where m->>'id'=(select v::text from ids where k='m1')),'Mensagem ruim fictícia','moderação lê a mensagem oculta');
select lives_ok($$select pg_temp.c('resolve',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1')))$$,'manter a mensagem');
select is(jsonb_array_length(pg_temp.c('reports')->'reports'),0,'denúncias resolvidas');
select is(pg_temp.c('hide',jsonb_build_object('room',(select v from ids where k='geral'),'id',(select v from ids where k='m1')))->'message'->>'state','hidden','moderação oculta');
select lives_ok($$select pg_temp.c('mute',jsonb_build_object('room',(select v from ids where k='geral'),'user',pg_temp.ch('bia'),'minutes',60))$$,'silenciar por uma hora');
select pg_temp.c('settings');
select lives_ok($$select pg_temp.c('settings',jsonb_build_object('enabled',true,'blockedWords',jsonb_build_array('Palavrão'),'version',1))$$,'palavras bloqueadas');
select pg_temp.actor('bia');
select throws_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','oi','client',gen_random_uuid()))$$,'42501','chat_muted','silenciada não envia');
select is((pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='geral')))->>'canPost')::boolean,false,'tela sabe que não pode enviar');
select pg_temp.actor('caio');
select throws_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','um PALAVRÃO aqui','client',gen_random_uuid()))$$,'22023','chat_blocked_word','palavra bloqueada');

-- Conversa direta
select pg_temp.actor('caio');
select throws_ok($$select pg_temp.c('direct',jsonb_build_object('person',pg_temp.ch('teen-p')))$$,'22023','chat_direct_unavailable','não conversa em particular com menor');
insert into ids select 'dm',(pg_temp.c('direct',jsonb_build_object('person',pg_temp.ch('ana-p')))->>'room')::uuid;
select is((pg_temp.c('direct',jsonb_build_object('person',pg_temp.ch('ana-p')))->>'room')::uuid,(select v from ids where k='dm'),'mesma conversa direta');
select is(jsonb_array_length(pg_temp.c('people',jsonb_build_object('search','fictícia'))->'people'),4,'busca só adultos');
select lives_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='dm'),'body','Oi, Ana','client',gen_random_uuid()))$$,'mensagem direta');
select pg_temp.actor('bia');
select throws_ok($$select pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='dm')))$$,'42501','chat_denied','terceiro não lê conversa direta');
select pg_temp.actor('owner');
select throws_ok($$select pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='dm')))$$,'42501','chat_denied','moderação não lê conversa direta');
select pg_temp.actor('ana');
select is(pg_temp.c('messages',jsonb_build_object('room',(select v from ids where k='dm')))->'messages'->0->>'body','Oi, Ana','destinatária lê');
select is((select r->>'name' from jsonb_array_elements(pg_temp.c('rooms')->'rooms') r where r->>'kind'='direct'),'Caio da Silva Fictícia','conversa direta mostra o nome da outra pessoa');

-- Tempo real
select is(public.chat_listen((select v from ids where k='dm')),true,'participante ouve a conversa');
select pg_temp.actor('bia');
select is(public.chat_listen((select v from ids where k='dm')),false,'terceiro não ouve a conversa');
select is(public.chat_listen((select v from ids where k='equipe')),false,'membro não ouve a equipe');

-- Limite de envio
select pg_temp.actor('r3');
select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','msg '||g,'client',gen_random_uuid())) from generate_series(1,10) g;
select throws_ok($$select pg_temp.c('send',jsonb_build_object('room',(select v from ids where k='geral'),'body','mais uma','client',gen_random_uuid()))$$,'54000','chat_slow_down','limite de envio');

-- Arquivar canal
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.c('room_archive',jsonb_build_object('id',(select v from ids where k='mural')))$$,'arquivar canal');
select pg_temp.actor('ana');
select is(jsonb_array_length(pg_temp.c('rooms')->'rooms'),2,'canal arquivado some (geral e conversa direta)');
reset role;
select is((select count(*)::int from public.audit_logs where organization_id=pg_temp.ch('org') and action like 'chat.%'),8,'moderação registrada na auditoria');
select * from finish();
rollback;
