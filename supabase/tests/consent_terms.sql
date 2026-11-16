begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Termos de consentimento: assinatura no app, código, SHA-256, verificação pública, revogação e vínculo ao cadastro.
create function pg_temp.ct(t text) returns uuid language sql immutable as $$select md5('consent-terms-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ct(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.ct(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-consent@example.invalid',now(),now(),now() from unnest(array['owner','parent','other','newbie'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.ct('org'),'Termos fictício','consent-terms-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ct('a'),pg_temp.ct('org'),'Igreja Esperança','a','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values(pg_temp.ct('owner-m'),pg_temp.ct('org'),pg_temp.ct('owner'),pg_temp.ct('a'),'owner','active');
insert into public.people(id,organization_id,unit_id,full_name,status,auth_user_id) values
 (pg_temp.ct('p-parent'),pg_temp.ct('org'),pg_temp.ct('a'),'Ana Lúcia Prado','active',pg_temp.ct('parent')),
 (pg_temp.ct('p-child'),pg_temp.ct('org'),pg_temp.ct('a'),'Davi Prado','active',null),
 (pg_temp.ct('p-other'),pg_temp.ct('org'),pg_temp.ct('a'),'Outra Pessoa','active',pg_temp.ct('other')),
 (pg_temp.ct('p-new'),pg_temp.ct('org'),pg_temp.ct('a'),'Novo Membro','active',null);
insert into private.kids_profiles(id,organization_id,unit_id,person_id,status,review_status,created_by) values(pg_temp.ct('kid'),pg_temp.ct('org'),pg_temp.ct('a'),pg_temp.ct('p-child'),'active','approved',pg_temp.ct('parent'));
insert into private.kids_guardians(id,organization_id,unit_id,profile_id,person_id,relationship,can_pickup,can_edit,status,approved_by,approved_at,created_by) values(pg_temp.ct('g'),pg_temp.ct('org'),pg_temp.ct('a'),pg_temp.ct('kid'),pg_temp.ct('p-parent'),'Mãe',true,true,'approved',pg_temp.ct('owner'),now(),pg_temp.ct('owner'));
create function pg_temp.sign(id text,kind text,child text default null,choices jsonb default '{}') returns jsonb language sql as $$select public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'sign',jsonb_build_object('id',pg_temp.ct(id),'kind',kind,'signerName','Ana Lúcia Prado','device','Android','choices',choices)||case when child is null then '{}'::jsonb else jsonb_build_object('child',pg_temp.ct(child)) end)$$;

select ok(not has_function_privilege('anon','public.member_consent(uuid,uuid,text,jsonb)','execute'),'assinatura exige conta');
select ok(has_function_privilege('anon','public.consent_verify(text)','execute'),'verificação é pública');
select ok(not has_table_privilege('authenticated','private.consent_records','select'),'registros sem leitura direta');
select pg_temp.actor('parent');set local role authenticated;
select is((public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'list')->'templates'->'kids_image'->>'title'),'Termo de autorização de uso de imagem da criança','texto padrão disponível');
select matches(pg_temp.sign('c1','adult_data')->'item'->>'code','^VNH-[A-Z2-9]{4}-[A-Z2-9]{4}$','código de verificação gerado');
select is(pg_temp.sign('c1','adult_data')->'item'->>'id',pg_temp.ct('c1')::text,'reenvio devolve o mesmo termo');
select is(pg_temp.sign('k1','kids_image','kid',jsonb_build_object('photos',true,'videos',false,'social',true,'live',false))->'item'->'choices'->>'social','true','escolhas de imagem da criança gravadas');
select is(pg_temp.sign('k2','kids_guardian','kid')->'item'->>'subjectName','Davi Prado','termo do responsável aponta a criança');
select throws_ok($$select public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'sign',jsonb_build_object('id',pg_temp.ct('bad'),'kind','adult_data','signerName','Ana','device',''))$$,'22023',null,'assinatura exige nome e sobrenome');
reset role;
select is((select encode(extensions.digest(private.consent_canonical(c),'sha256'),'hex')=c.sha256 from private.consent_records c where id=pg_temp.ct('c1')),true,'impressão digital confere com o texto assinado');
select is((select subject_person from private.consent_records where id=pg_temp.ct('c1')),pg_temp.ct('p-parent'),'termo do adulto vinculado ao cadastro');
create temp table codes as select case id when pg_temp.ct('c1') then 'c1' when pg_temp.ct('k1') then 'k1' end k,code from private.consent_records;grant select on codes to anon,authenticated;
set local role anon;
select is(public.consent_verify((select code from codes where k='c1'))->>'intact','true','verificação pública confirma o documento');
select is(public.consent_verify((select code from codes where k='c1'))->>'signer','Ana P.','verificação mostra só iniciais');
select ok(public.consent_verify((select code from codes where k='k1'))::text not like '%Prado%','criança não é exposta na verificação');
select is(public.consent_verify('VNH-AAAA-BBBB')->>'found','false','código inexistente');
reset role;
-- adulterar o texto quebra a verificação
update private.consent_records set body=body||' alterado' where id=pg_temp.ct('c1');
select is(public.consent_verify((select code from codes where k='c1'))->>'intact','false','texto alterado é detectado');
update private.consent_records set body=replace(body,' alterado','') where id=pg_temp.ct('c1');
select pg_temp.actor('parent');set local role authenticated;
select lives_ok($$select pg_temp.sign('k3','kids_image','kid',jsonb_build_object('photos',false,'videos',false,'social',false,'live',false))$$,'novo termo de imagem');
reset role;
select ok((select revoked_reason like 'Substituído por VNH-%' from private.consent_records where id=pg_temp.ct('k1')),'novo aceite substitui o anterior');
select pg_temp.actor('parent');set local role authenticated;
select is(public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'revoke',jsonb_build_object('id',pg_temp.ct('k3')))->>'ok','true','responsável revoga');
select ok(public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'link',jsonb_build_object('id',pg_temp.ct('c1')))->>'token' is not null,'link de uso único para o PDF');
select is(public.consent_document((select code from codes where k='c1'))->>'intact','true','quem assinou abre o documento');
reset role;select pg_temp.actor('other');set local role authenticated;
select throws_ok($$select pg_temp.sign('x','kids_image','kid')$$,'42501',null,'quem não é responsável não assina pela criança');
select throws_ok($$select public.consent_document((select code from codes where k='c1'))$$,'42501',null,'outra pessoa não abre o documento');
select throws_ok($$select public.consent_document(null,gen_random_uuid())$$,'42501',null,'token só pelo servidor');
reset role;select pg_temp.actor('owner');set local role authenticated;
select is(jsonb_array_length(public.people_consents(pg_temp.ct('org'),pg_temp.ct('p-child'))->'items'),3,'ficha da criança mostra os termos');
select is(public.consent_templates_admin(pg_temp.ct('org'),'save',jsonb_build_object('kind','adult_image','title','Uso de imagem — Igreja Esperança','body','Texto próprio da igreja para uso de imagem e voz.'))->>'version','1','igreja publica texto próprio');
select is((select x->>'title' from jsonb_array_elements(public.consent_templates_admin(pg_temp.ct('org'),'list')->'items') x where x->>'kind'='adult_image'),'Uso de imagem — Igreja Esperança','texto próprio passa a valer');
-- Termos criados pela igreja.
select lives_ok($$select public.consent_templates_admin(pg_temp.ct('org'),'save',jsonb_build_object('kind','custom_retiro2026','audience','adult','title','Autorização para o retiro','body','Autorizo minha participação no retiro e as regras do acampamento.'))$$,'igreja cria termo novo');
select lives_ok($$select public.consent_templates_admin(pg_temp.ct('org'),'save',jsonb_build_object('kind','custom_passeiokids','audience','kids','title','Passeio das crianças','body','Autorizo a criança a participar do passeio do Kids com a equipe.'))$$,'igreja cria termo para crianças');
select throws_ok($$select public.consent_templates_admin(pg_temp.ct('org'),'save',jsonb_build_object('kind','qualquer','title','Termo','body','Texto com tamanho suficiente para passar.'))$$,'22023',null,'tipo inválido recusado');
select is(jsonb_array_length(public.consent_templates_admin(pg_temp.ct('org'),'list')->'custom'),2,'painel lista os termos criados');
reset role;select pg_temp.actor('parent');set local role authenticated;
select is((select x->>'audience' from jsonb_array_elements(public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'list')->'custom') x where x->>'kind'='custom_passeiokids'),'kids','app recebe o termo e para quem é');
select lives_ok($$select pg_temp.sign('cu1','custom_retiro2026')$$,'membro assina termo da igreja');
select lives_ok($$select pg_temp.sign('cu2','custom_passeiokids','kid')$$,'responsável assina termo da igreja pela criança');
select throws_ok($$select pg_temp.sign('cu3','custom_passeiokids')$$,'42501',null,'termo de criança exige a criança');
reset role;select pg_temp.actor('owner');set local role authenticated;
select lives_ok($$select public.consent_templates_admin(pg_temp.ct('org'),'archive',jsonb_build_object('kind','custom_retiro2026'))$$,'igreja retira o termo do app');
select is(jsonb_array_length(public.consent_templates_admin(pg_temp.ct('org'),'list')->'custom'),1,'termo retirado sai da lista');
select throws_ok($$select public.consent_templates_admin(pg_temp.ct('org'),'archive',jsonb_build_object('kind','adult_data'))$$,'22023',null,'termos padrão não saem');
reset role;select pg_temp.actor('newbie');set local role authenticated;
select lives_ok($$select public.member_consent(pg_temp.ct('org'),pg_temp.ct('a'),'sign',jsonb_build_object('id',pg_temp.ct('n1'),'kind','adult_data','signerName','Novo Membro','device','Android'))$$,'conta ainda sem cadastro assina');
reset role;
update public.people set auth_user_id=pg_temp.ct('newbie') where id=pg_temp.ct('p-new');
select is((select subject_person from private.consent_records where id=pg_temp.ct('n1')),pg_temp.ct('p-new'),'termo vincula ao cadastro quando a igreja aprova');
select * from finish();
rollback;
