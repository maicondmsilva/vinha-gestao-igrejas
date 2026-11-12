begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Vínculos familiares: inverso automático, par único, permissões, cadastro rápido, data de casamento e sugestão para o Kids.
create function pg_temp.pf(t text) returns uuid language sql immutable as $$select md5('person-family-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pf(t),'role','authenticated')::text,true)$$;
create function pg_temp.fam(a text, d jsonb) returns jsonb language sql as $$select public.person_family(pg_temp.pf('org'),a,d)$$;
create function pg_temp.rel(a text, b text) returns text language sql security definer as $$select relation from private.person_relationships where person_id=pg_temp.pf(a) and related_person_id=pg_temp.pf(b)$$;
create function pg_temp.ver(a text, b text) returns int language sql security definer as $$select version from private.person_relationships where person_id=pg_temp.pf(a) and related_person_id=pg_temp.pf(b)$$;
create function pg_temp.rid(a text, b text) returns uuid language sql security definer as $$select id from private.person_relationships where person_id=pg_temp.pf(a) and related_person_id=pg_temp.pf(b)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.pf(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-family@example.invalid',now(),now(),now() from unnest(array['owner','sec','outsider']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.pf('org'),'Família fictícia','person-family-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 (pg_temp.pf('unit'),pg_temp.pf('org'),'Sede família','sede','headquarters'),
 (pg_temp.pf('unit2'),pg_temp.pf('org'),'Bairro família','bairro','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.pf('owner-m'),pg_temp.pf('org'),pg_temp.pf('owner'),'owner','active',pg_temp.pf('unit')),
 (pg_temp.pf('sec-m'),pg_temp.pf('org'),pg_temp.pf('sec'),'secretary','active',pg_temp.pf('unit')),
 (pg_temp.pf('outsider-m'),pg_temp.pf('org'),pg_temp.pf('outsider'),'member','active',pg_temp.pf('unit'));
insert into public.membership_unit_access(membership_id,organization_id,unit_id,access_level,include_children)
 values(pg_temp.pf('sec-m'),pg_temp.pf('org'),pg_temp.pf('unit'),'manage',false);
insert into public.people(id,organization_id,unit_id,full_name,birth_date,journey_status,status) values
 (pg_temp.pf('mae'),pg_temp.pf('org'),pg_temp.pf('unit'),'Maria Mãe','1985-03-01','Membro','active'),
 (pg_temp.pf('filho'),pg_temp.pf('org'),pg_temp.pf('unit'),'João Filho','2015-07-10','Membro','active'),
 (pg_temp.pf('pai'),pg_temp.pf('org'),pg_temp.pf('unit'),'José Pai','1983-01-01','Membro','active'),
 (pg_temp.pf('avo'),pg_temp.pf('org'),pg_temp.pf('unit'),'Ana Avó','1955-01-01','Membro','active'),
 (pg_temp.pf('tia'),pg_temp.pf('org'),pg_temp.pf('unit2'),'Teresa Tia','1980-01-01','Membro','active'),
 (pg_temp.pf('rejeitada'),pg_temp.pf('org'),pg_temp.pf('unit'),'Pessoa Reprovada','1990-01-01','Visitante','rejected');
insert into public.person_addresses(organization_id,person_id,postal_code,street,number,city,state)
 values(pg_temp.pf('org'),pg_temp.pf('mae'),'01001000','Rua das Flores','12','São Paulo','SP');

select has_table('private','person_relationships','tabela de vínculos existe');
select is(private.relation_inverse('pai_mae'),'filho','inverso de pai/mãe');
select is(private.relation_inverse('filho'),'pai_mae','inverso de filho');
select is(private.relation_inverse('avo'),'neto','inverso de avô');
select is(private.relation_inverse('tio'),'sobrinho','inverso de tio');
select is(private.relation_inverse('padrasto_madrasta'),'enteado','inverso de padrasto');
select is(private.relation_inverse('responsavel_legal'),'tutelado','inverso de responsável legal');
select is(private.relation_inverse('conjuge'),'conjuge','cônjuge é o próprio inverso');
select is(private.relation_inverse('irmao'),'irmao','irmão é o próprio inverso');
select ok(not has_table_privilege('authenticated','private.person_relationships','SELECT'),'cliente não lê a tabela direto');

set local role authenticated;
select pg_temp.actor('owner');
select lives_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('mae'),'related',pg_temp.pf('filho'),'relation','filho','same_household',true,'copy_address',true))$$,'liga mãe e filho');
reset role;
select is(pg_temp.rel('mae','filho'),'filho','na ficha da mãe, João é filho');
select is(pg_temp.rel('filho','mae'),'pai_mae','filho cria pai_mae do outro lado');
select is((select street from public.person_addresses where person_id=pg_temp.pf('filho')),'Rua das Flores','copy_address copia o endereço');
set local role authenticated;
select pg_temp.actor('owner');
select is((pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))#>>'{items,0,name}'),'Maria Mãe','lista mostra a mãe na ficha do filho');
select is((pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))#>>'{items,0,relation}'),'pai_mae','na ficha do filho, Maria aparece como pai/mãe');
select is((pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))#>>'{items,0,same_household}'),'true','mora junto aparece');

select throws_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('mae'),'related',pg_temp.pf('mae'),'relation','irmao'))$$,'23514',null,'não liga a si mesmo');
select throws_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('filho'),'related',pg_temp.pf('mae'),'relation','irmao'))$$,'23505',null,'par único');
select throws_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('mae'),'related',pg_temp.pf('pai'),'relation','primo'))$$,'22023',null,'parentesco fora da lista recusado');

-- Cônjuge com data de casamento
select lives_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('mae'),'related',pg_temp.pf('pai'),'relation','conjuge','same_household',true,'marriage_date','2010-05-20'))$$,'liga cônjuges');
reset role;
select is((select string_agg(marriage_date::text,',' order by id) from public.people where id in (pg_temp.pf('mae'),pg_temp.pf('pai'))),'2010-05-20,2010-05-20','cônjuge grava data de casamento nos dois');
select is(pg_temp.rel('pai','mae'),'conjuge','cônjuge dos dois lados');
set local role authenticated;
select pg_temp.actor('owner');

-- Trocar parentesco atualiza o inverso
select lives_ok($$select pg_temp.fam('set',jsonb_build_object('id',pg_temp.rid('mae','filho'),'version',pg_temp.ver('mae','filho'),'person',pg_temp.pf('mae'),'related',pg_temp.pf('filho'),'relation','tutelado','same_household',true))$$,'troca o parentesco');
reset role;
select is(pg_temp.rel('filho','mae'),'responsavel_legal','trocar parentesco atualiza o inverso');
select is((select count(*)::int from private.person_relationships where person_id in (pg_temp.pf('mae'),pg_temp.pf('filho')) and related_person_id in (pg_temp.pf('mae'),pg_temp.pf('filho'))),2,'sem sobra depois da troca');
set local role authenticated;
select pg_temp.actor('owner');
select throws_ok($$select pg_temp.fam('set',jsonb_build_object('id',pg_temp.rid('mae','filho'),'version',1,'person',pg_temp.pf('mae'),'related',pg_temp.pf('filho'),'relation','filho'))$$,'40001',null,'versão antiga recusada');
select lives_ok($$select pg_temp.fam('set',jsonb_build_object('id',pg_temp.rid('mae','filho'),'version',pg_temp.ver('mae','filho'),'person',pg_temp.pf('mae'),'related',pg_temp.pf('filho'),'relation','filho','same_household',true))$$,'volta para filho');

-- Sugestão para o Kids
select lives_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('avo'),'related',pg_temp.pf('filho'),'relation','neto'))$$,'liga avó e neto');
select lives_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('tia'),'related',pg_temp.pf('filho'),'relation','sobrinho'))$$,'liga tia e sobrinho (outra igreja)');
select is((select string_agg(i->>'relation',',' order by i->>'relation') from jsonb_array_elements(pg_temp.fam('suggest_guardians',jsonb_build_object('child',pg_temp.pf('filho')))->'items') i),'avo,pai_mae','sugestão traz pai_mae, avo e responsavel_legal');
select is((select i->>'unit' from jsonb_array_elements(pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))->'items') i where i->>'name'='Teresa Tia'),'Bairro família','lista mostra a igreja do familiar');

-- Cadastro rápido
select lives_ok($$select pg_temp.fam('quick_create',jsonb_build_object('person',pg_temp.pf('mae'),'name','Bebê Novo','birth_date','2025-01-02','journey','Membro','relation','filho','same_household',true))$$,'cadastro rápido');
reset role;
select is((select unit_id from public.people where organization_id=pg_temp.pf('org') and full_name='Bebê Novo'),pg_temp.pf('unit'),'cadastro rápido cria pessoa na igreja da principal');
select is((select r.relation from private.person_relationships r join public.people p on p.id=r.related_person_id where r.person_id=pg_temp.pf('mae') and p.full_name='Bebê Novo'),'filho','cadastro rápido já cria o vínculo');
set local role authenticated;

-- Permissões
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))$$,'42501',null,'sem ver, não lista');
select pg_temp.actor('sec');
select ok(jsonb_array_length(pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))->'items')>=2,'secretaria da igreja vê a família');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('filho')))->'items') i where i->>'name'='Teresa Tia'),'familiar de igreja sem acesso não aparece');
select throws_ok($$select pg_temp.fam('set',jsonb_build_object('person',pg_temp.pf('tia'),'related',pg_temp.pf('pai'),'relation','irmao'))$$,'42501',null,'sem editar uma das pessoas, recusa');
select throws_ok($$select pg_temp.fam('quick_create',jsonb_build_object('person',pg_temp.pf('tia'),'name','Sobrinho X','journey','Membro','relation','tio'))$$,'42501',null,'cadastro rápido exige editar a pessoa principal');

-- Pessoa reprovada some; remover apaga os dois lados
select pg_temp.actor('owner');
reset role;
insert into private.person_relationships(organization_id,person_id,related_person_id,relation) values
 (pg_temp.pf('org'),pg_temp.pf('pai'),pg_temp.pf('rejeitada'),'irmao'),(pg_temp.pf('org'),pg_temp.pf('rejeitada'),pg_temp.pf('pai'),'irmao');
set local role authenticated;
select pg_temp.actor('owner');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.fam('list',jsonb_build_object('person',pg_temp.pf('pai')))->'items') i where i->>'name'='Pessoa Reprovada'),'pessoa reprovada some da lista');
select lives_ok($$select pg_temp.fam('remove',jsonb_build_object('id',pg_temp.rid('filho','mae'),'version',pg_temp.ver('filho','mae')))$$,'remove o vínculo');
reset role;
select is((select count(*)::int from private.person_relationships where (person_id,related_person_id) in ((pg_temp.pf('mae'),pg_temp.pf('filho')),(pg_temp.pf('filho'),pg_temp.pf('mae')))),0,'remove apaga os dois sentidos');
delete from private.member_record_numbers where person_id=pg_temp.pf('tia');
delete from public.people where id=pg_temp.pf('tia');
select is((select count(*)::int from private.person_relationships where pg_temp.pf('tia') in (person_id,related_person_id)),0,'excluir a pessoa apaga os vínculos dela');
select ok((select count(*) from public.audit_logs where organization_id=pg_temp.pf('org') and action in ('people.family.saved','people.family.removed'))>=5,'vínculos geram auditoria');
select * from finish();
rollback;
