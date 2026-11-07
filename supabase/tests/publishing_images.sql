begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.pa(t text) returns uuid language sql immutable as $$select md5('publishing-images-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.pa(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-pimg@example.invalid',now(),now(),now() from unnest(array['owner','member','other'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pa('org'),'Imagens fictícias','publishing-images-test','active'),(pg_temp.pa('org2'),'Outro ministério fictício','publishing-images-other','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.pa('unit'),pg_temp.pa('org'),'Sede fictícia','s','headquarters'),(pg_temp.pa('unit2'),pg_temp.pa('org2'),'Sede de outro ministério','o','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values
 (pg_temp.pa('owner-m'),pg_temp.pa('org'),pg_temp.pa('owner'),pg_temp.pa('unit'),'owner','active'),
 (pg_temp.pa('member-m'),pg_temp.pa('org'),pg_temp.pa('member'),pg_temp.pa('unit'),'member','active'),
 (pg_temp.pa('other-m'),pg_temp.pa('org2'),pg_temp.pa('other'),pg_temp.pa('unit2'),'owner','active');
create function pg_temp.img(a text,i uuid default null,d jsonb default '{}') returns jsonb language sql as $$select public.publishing_image(pg_temp.pa('org'),pg_temp.pa('unit'),a,i,d)$$;

select ok(not has_function_privilege('anon','public.publishing_image(uuid,uuid,text,uuid,jsonb)','execute'),'visitante não usa o banco de imagens');
select ok(not has_table_privilege('authenticated','private.publishing_images','select'),'tabela sem acesso direto');
select is((select public from storage.buckets where id='vinha-publishing-images'),false,'bucket privado');

set local role authenticated;select pg_temp.actor('member');
select throws_ok($$select pg_temp.img('list')$$,'42501','publishing_denied','membro não acessa');
select pg_temp.actor('owner');
select throws_ok($$select pg_temp.img('prepare',pg_temp.pa('i1'),'{"mime":"image/gif","bytes":10,"name":"x"}')$$,'22023','invalid_publishing_image','tipo recusado');
select throws_ok($$select pg_temp.img('prepare',pg_temp.pa('i1'),'{"mime":"image/png","bytes":6000000,"name":"x"}')$$,'22023','invalid_publishing_image','arquivo grande demais');
select is(pg_temp.img('prepare',pg_temp.pa('i1'),'{"mime":"image/png","bytes":1200,"name":"Culto de domingo"}')->>'path',pg_temp.pa('org')::text||'/'||pg_temp.pa('unit')::text||'/'||pg_temp.pa('i1')::text,'caminho dentro do ministério');
select is(jsonb_array_length(pg_temp.img('list')->'items'),0,'imagem incompleta não aparece');
select lives_ok($$select pg_temp.img('finish',pg_temp.pa('i1'))$$,'envio confirmado');
select throws_ok($$select pg_temp.img('finish',pg_temp.pa('i1'))$$,'42501','publishing_denied','confirmação não repete');
select is(pg_temp.img('list')->'items'->0->>'name','Culto de domingo','lista mostra a imagem');
select is(jsonb_array_length(pg_temp.img('list',null,'{"search":"batismo"}')->'items'),0,'busca filtra pelo nome');
select is(pg_temp.img('update',pg_temp.pa('i1'),'{"alt":"Igreja reunida no culto"}')->'items'->0->>'alt','Igreja reunida no culto','descrição salva');
select is((public.publishing_image_file(pg_temp.pa('i1'))->>'public')::boolean,false,'quem publica vê a prévia');
reset role;

-- Visitante só vê imagem usada em publicação publicada do mesmo ministério
set local role anon;
select is(public.publishing_image_file(pg_temp.pa('i1')),null,'imagem não publicada fica privada');
reset role;
insert into private.publishing_items(id,organization_id,owner_unit,kind,title,body,source,scope,targets,status,created_by)
 values(pg_temp.pa('other-post'),pg_temp.pa('org2'),pg_temp.pa('unit2'),'notice','Aviso de outro ministério','![x](img:'||pg_temp.pa('i1')||')','','local',array[pg_temp.pa('unit2')],'published',pg_temp.pa('other'));
set local role anon;
select is(public.publishing_image_file(pg_temp.pa('i1')),null,'outro ministério não libera a imagem');
reset role;
insert into private.publishing_items(id,organization_id,owner_unit,kind,title,body,source,scope,targets,status,created_by)
 values(pg_temp.pa('post'),pg_temp.pa('org'),pg_temp.pa('unit'),'notice','Aviso fictício','Texto **forte**'||chr(10)||'![Igreja](img:'||pg_temp.pa('i1')||')','','local',array[pg_temp.pa('unit')],'published',pg_temp.pa('owner'));
set local role anon;
select is((public.publishing_image_file(pg_temp.pa('i1'))->>'public')::boolean,true,'imagem do aviso publicado é pública');
reset role;
set local role authenticated;select pg_temp.actor('owner');
select lives_ok($$select pg_temp.img('archive',pg_temp.pa('i1'))$$,'arquivar');
select is(jsonb_array_length(pg_temp.img('list')->'items'),0,'arquivada sai do banco de imagens');
reset role;
set local role anon;
select is((public.publishing_image_file(pg_temp.pa('i1'))->>'public')::boolean,true,'aviso publicado continua com a imagem');
reset role;
select * from finish();
rollback;
