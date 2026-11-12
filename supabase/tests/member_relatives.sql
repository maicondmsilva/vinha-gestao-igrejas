begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Aplicativo: minha família (só nome e parentesco) e pedido de inclusão de familiar, analisado em Pessoas.
create function pg_temp.mr(t text) returns uuid language sql immutable as $$select md5('member-relatives-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.mr(t),'role','authenticated','email',t||'-rel@example.invalid')::text,true)$$;
create function pg_temp.me(a text, d jsonb) returns jsonb language sql as $$select public.member_relatives(pg_temp.mr('org'),a,d)$$;
create function pg_temp.adm(a text, d jsonb) returns jsonb language sql as $$select public.member_relatives_admin(pg_temp.mr('org'),a,d)$$;
create function pg_temp.inbox() returns setof jsonb language sql security definer as $$select to_jsonb(x) from private.member_inbox_rows(pg_temp.mr('org'),pg_temp.mr('unit')) x where x.message_key like 'relative-review:%'$$;
create function pg_temp.req(n text) returns uuid language sql security definer as $$select id from private.member_family_requests where organization_id=pg_temp.mr('org') and kind='relative' and data->>'name'=n$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.mr(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-rel@example.invalid',now(),now(),now() from unnest(array['owner','ana','bia','nobody']) t;
insert into public.organizations(id,name,slug,status) values(pg_temp.mr('org'),'Igreja parentes','member-relatives-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.mr('unit'),pg_temp.mr('org'),'Sede parentes','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values
 (pg_temp.mr('org'),pg_temp.mr('owner'),pg_temp.mr('unit'),'owner','active'),
 (pg_temp.mr('org'),pg_temp.mr('ana'),pg_temp.mr('unit'),'member','active'),
 (pg_temp.mr('org'),pg_temp.mr('bia'),pg_temp.mr('unit'),'member','active'),
 (pg_temp.mr('org'),pg_temp.mr('nobody'),pg_temp.mr('unit'),'member','active');
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,birth_date,status,journey_status) values
 (pg_temp.mr('ana-p'),pg_temp.mr('org'),pg_temp.mr('unit'),pg_temp.mr('ana'),'Ana Parente','1985-01-01','active','Membro'),
 (pg_temp.mr('bia-p'),pg_temp.mr('org'),pg_temp.mr('unit'),pg_temp.mr('bia'),'Bia Parente','1990-01-01','active','Membro'),
 (pg_temp.mr('marido'),pg_temp.mr('org'),pg_temp.mr('unit'),null,'Carlos Parente','1983-02-02','active','Membro'),
 (pg_temp.mr('sobrinha'),pg_temp.mr('org'),pg_temp.mr('unit'),null,'Duda Parente','2012-03-03','active','Visitante');
insert into private.person_relationships(organization_id,person_id,related_person_id,relation,same_household) values
 (pg_temp.mr('org'),pg_temp.mr('ana-p'),pg_temp.mr('marido'),'conjuge',true),(pg_temp.mr('org'),pg_temp.mr('marido'),pg_temp.mr('ana-p'),'conjuge',true);

set local role authenticated;
select pg_temp.actor('ana');
select is(pg_temp.me('list','{}')->'items','[{"name":"Carlos Parente","relation":"conjuge"}]'::jsonb,'membro vê só nome e parentesco');
select lives_ok($$select pg_temp.me('request','{"nonce":"n1","name":"Enzo Parente","birth_date":"2020-04-04","relation":"filho","same_household":true}')$$,'membro pede inclusão de familiar');
select lives_ok($$select pg_temp.me('request','{"nonce":"n1","name":"Enzo Parente","birth_date":"2020-04-04","relation":"filho","same_household":true}')$$,'repetir o mesmo pedido não duplica');
select lives_ok($$select pg_temp.me('request','{"nonce":"n2","name":"Duda Parente","birth_date":"2012-03-03","relation":"sobrinho"}')$$,'pede familiar que já existe');
select lives_ok($$select pg_temp.me('request','{"nonce":"n3","name":"Fulano Errado","relation":"outro"}')$$,'pede familiar que será recusado');
select throws_ok($$select pg_temp.me('request','{"nonce":"n4","name":"X","relation":"filho"}')$$,'22023',null,'nome curto recusado');
select throws_ok($$select pg_temp.me('request','{"nonce":"n5","name":"Primo Qualquer","relation":"primo"}')$$,'22023',null,'parentesco fora da lista recusado');
select is((select count(*)::int from jsonb_array_elements(pg_temp.me('requests','{}')->'items') i where i->>'status'='pending'),3,'pedido relative entra pendente');
reset role;
select is((select count(*)::int from private.member_family_requests where organization_id=pg_temp.mr('org') and kind='relative'),3,'pedidos gravados com o tipo relative');
set local role authenticated;
select pg_temp.actor('nobody');
select throws_ok($$select pg_temp.me('request','{"nonce":"z","name":"Sem Cadastro","relation":"filho"}')$$,'42501',null,'sem cadastro de membro não pede');

-- Análise em Pessoas › Perfis pendentes
select pg_temp.actor('bia');
select throws_ok($$select pg_temp.adm('list','{}')$$,'42501',null,'membro comum não analisa');
select pg_temp.actor('owner');
select is((select count(*)::int from jsonb_array_elements(pg_temp.adm('list','{}')->'items')),3,'gestão vê os pedidos de familiares');
select is((select c->>'name' from jsonb_array_elements(pg_temp.adm('list','{}')->'items') i, jsonb_array_elements(i->'candidates') c where i->>'name'='Duda Parente'),'Duda Parente','sugere pessoa existente com mesmo nome e nascimento');
select lives_ok($$select pg_temp.adm('review',jsonb_build_object('id',pg_temp.req('Enzo Parente'),'decision','approve','journey','Membro'))$$,'aprova criando pessoa');
select lives_ok($$select pg_temp.adm('review',jsonb_build_object('id',pg_temp.req('Duda Parente'),'decision','approve','person',pg_temp.mr('sobrinha')))$$,'aprova ligando a pessoa existente');
select throws_ok($$select pg_temp.adm('review',jsonb_build_object('id',pg_temp.req('Fulano Errado'),'decision','reject','reason','x'))$$,'22023',null,'reprovação exige motivo');
select lives_ok($$select pg_temp.adm('review',jsonb_build_object('id',pg_temp.req('Fulano Errado'),'decision','reject','reason','Não encontramos esse familiar. Confira o nome.'))$$,'reprova com motivo');
select throws_ok($$select pg_temp.adm('review',jsonb_build_object('id',pg_temp.req('Enzo Parente'),'decision','approve'))$$,'40001',null,'pedido já analisado não é analisado de novo');
reset role;
select is((select count(*)::int from public.people where organization_id=pg_temp.mr('org') and full_name='Enzo Parente' and unit_id=pg_temp.mr('unit')),1,'aprovar cria pessoa na igreja de quem pediu');
select is((select r.relation from private.person_relationships r join public.people p on p.id=r.related_person_id where r.person_id=pg_temp.mr('ana-p') and p.full_name='Enzo Parente'),'filho','aprovar cria o vínculo');
select is((select relation from private.person_relationships where person_id=pg_temp.mr('ana-p') and related_person_id=pg_temp.mr('sobrinha')),'sobrinho','aprovar ligando a pessoa existente cria o vínculo');
select is((select count(*)::int from public.people where organization_id=pg_temp.mr('org') and full_name='Duda Parente'),1,'aprovar ligando a pessoa existente não duplica');
set local role authenticated;
select pg_temp.actor('ana');
select is((select count(*)::int from pg_temp.inbox()),1,'reprovar avisa o membro');
select ok((select i->>'body' from pg_temp.inbox() i) like '%Não encontramos esse familiar%','aviso traz o motivo');
select is(jsonb_array_length(pg_temp.me('list','{}')->'items'),3,'família do membro mostra os aprovados');
select * from finish();
rollback;
