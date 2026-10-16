-- Synthetic identities only. Every mutation is rolled back; no outbound calls.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('f5000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator1@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator2@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator3@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator4@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator5@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator6@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator7@fixture.example.invalid','',now(),now(),now()),
('f5000000-0000-4000-8000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','operator8@fixture.example.invalid','',null,now(),now());
insert into public.platform_operators(user_id,email,role,full_name) values
('f5000000-0000-4000-8000-000000000001','operator1@fixture.example.invalid','owner','Owner QA'),
('f5000000-0000-4000-8000-000000000002','operator2@fixture.example.invalid','admin','Admin QA'),
('f5000000-0000-4000-8000-000000000003','operator3@fixture.example.invalid','read_only','Read QA');
insert into public.platform_operator_invites(id,email,role,invited_by,token,expires_at) values
('f6000000-0000-4000-8000-000000000001','operator4@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000001',now()+interval '1 day'),
('f6000000-0000-4000-8000-000000000002','operator5@fixture.example.invalid','owner','f5000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000002',now()+interval '1 day'),
('f6000000-0000-4000-8000-000000000003','operator6@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000003',now()-interval '1 day'),
('f6000000-0000-4000-8000-000000000004','operator7@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000004',now()+interval '1 day'),
('f6000000-0000-4000-8000-000000000005','operator8@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000005',now()+interval '1 day');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000002","email":"operator2@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$update public.platform_operator_invites set role='owner' where id='f6000000-0000-4000-8000-000000000001'$q$,'42501',null,'admin não transforma convite de suporte em proprietário');
select throws_ok($q$update public.platform_operator_invites set email='outro@fixture.example.invalid' where id='f6000000-0000-4000-8000-000000000001'$q$,'42501',null,'destinatário de convite não é reescrito');
select throws_ok($q$update public.platform_operator_invites set token=extensions.gen_random_uuid() where id='f6000000-0000-4000-8000-000000000001'$q$,'42501',null,'token existente não é reatribuído');
select throws_ok($q$update public.platform_operator_invites set accepted_at=now() where id='f6000000-0000-4000-8000-000000000001'$q$,'42501',null,'admin não simula aceite sem destinatário');
select throws_ok($q$update public.platform_operators set user_id='f5000000-0000-4000-8000-000000000008' where user_id='f5000000-0000-4000-8000-000000000002'$q$,'42501',null,'operador não transfere a própria identidade');
select throws_ok($q$update public.platform_operators set email='outro@fixture.example.invalid' where user_id='f5000000-0000-4000-8000-000000000002'$q$,'42501',null,'email do operador exige fluxo próprio verificado');
with changed as(update public.platform_operator_invites set revoked_at=now() where id='f6000000-0000-4000-8000-000000000002' returning id) select is((select count(*) from changed),0::bigint,'admin não revoga convite de proprietário');
select throws_ok($q$insert into public.platform_operator_invites(email,role,invited_by) values('newowner@fixture.example.invalid','owner','f5000000-0000-4000-8000-000000000002')$q$,'42501',null,'metadata de usuário não concede criação de proprietário');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000002","email":"operator2@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$insert into public.platform_operator_invites(email,role,invited_by) values('new@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000002')$q$,'42501',null,'MFA ausente impede convidar');
with changed as(update public.platform_operator_invites set revoked_at=now() where id='f6000000-0000-4000-8000-000000000001' returning id) select is((select count(*) from changed),0::bigint,'MFA ausente impede revogar');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000003","email":"operator3@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$insert into public.platform_operator_invites(email,role,invited_by) values('new@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000003')$q$,'42501',null,'somente leitura não convida');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000001","email":"operator1@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$insert into public.platform_operator_invites(email,role,invited_by,accepted_at) values('fake@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000001',now())$q$,'42501',null,'convite novo não nasce aceito');
select throws_ok($q$insert into public.platform_operator_invites(email,role,invited_by,expires_at) values('long@fixture.example.invalid','support','f5000000-0000-4000-8000-000000000001',now()+interval '1 year')$q$,'22023',null,'não cria convite de longa duração');
select throws_ok($q$update public.platform_operators set role='admin' where user_id='f5000000-0000-4000-8000-000000000001'$q$,'P0001',null,'não remove último proprietário ativo');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000008","email":"operator8@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000005','Unconfirmed QA')$q$,'42501',null,'aceite exige email confirmado no Auth');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000004","email":"operator5@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000002','Email forjado QA')$q$,'42501',null,'email do JWT não substitui identidade atual do Auth');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000006","email":"operator6@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000003','Expired QA')$q$,'42501',null,'convite expirado não é aceito');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000004","email":"operator4@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000001','X')$q$,'22023',null,'nome inválido não consome convite');
select lives_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000001','Support QA')$q$,'destinatário confirmado aceita convite de suporte');
select is((select role::text from public.platform_operators where user_id='f5000000-0000-4000-8000-000000000004'),'support','aceite mantém papel concedido');
select lives_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000001','Support QA')$q$,'aceite repetido retoma sem duplicar operador');
select is((select count(*) from public.platform_operators where user_id='f5000000-0000-4000-8000-000000000004'),1::bigint,'repetição não duplica operador');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000001","email":"operator1@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select lives_ok($q$update public.platform_operator_invites set revoked_at=now() where id='f6000000-0000-4000-8000-000000000002'$q$,'proprietário pode revogar seu convite pendente');
select ok((select revoked_at is not null from public.platform_operator_invites where id='f6000000-0000-4000-8000-000000000002'),'revogação é persistida');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000005","email":"operator5@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000002','Revoked QA')$q$,'42501',null,'convite revogado não é aceito');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000001","email":"operator1@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select lives_ok($q$update public.platform_operators set active=false where user_id='f5000000-0000-4000-8000-000000000002'$q$,'proprietário pode suspender outro operador');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000007","email":"operator7@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000004','Issuer suspended QA')$q$,'42501',null,'convite de emissor suspenso não concede acesso');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000001","email":"operator1@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select lives_ok($q$update public.platform_operators set active=false where user_id='f5000000-0000-4000-8000-000000000004'$q$,'destinatário já ativado pode perder acesso');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000004","email":"operator4@fixture.example.invalid","role":"authenticated","aal":"aal1","user_metadata":{"role":"owner"}}',true);
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000001','Support QA')$q$,'42501',null,'convite aceito não reativa operador suspenso');
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000007","email":"operator7@fixture.example.invalid","role":"authenticated","aal":"aal2","user_metadata":{"role":"owner"}}',true);
select is(public.chat_operator_directory(),'[]'::jsonb,'não operador não consulta diretório da equipe');
select throws_ok($q$select public.transfer_platform_chat('f6000000-0000-4000-8000-000000000099','f6000000-0000-4000-8000-000000000098',null)$q$,'42501',null,'transferência exige acesso ao setor');
select throws_ok($q$select public.request_unit_modules('f6000000-0000-4000-8000-000000000099',array['people'],10,false)$q$,'42501',null,'módulos exigem gestor da unidade');
select throws_ok($q$select public.approve_organization_hierarchy('f6000000-0000-4000-8000-000000000099','f6000000-0000-4000-8000-000000000098','approve')$q$,'42501',null,'aprovação exige vínculo autorizado');
select throws_ok($q$select public.organization_hierarchy_requests('f6000000-0000-4000-8000-000000000099')$q$,'42501',null,'hierarquia não expõe solicitações alheias');
select throws_ok($q$select public.support_chat('read','f6000000-0000-4000-8000-000000000099',null,'{}')$q$,'42501',null,'chat exige dono ou segredo válido');
select is(public.unit_module_enabled('f6000000-0000-4000-8000-000000000099','people'),false,'sem vínculo não obtém módulo');
select is(public.pending_organization_invitation(),null::jsonb,'sem convite correspondente não recebe token');
select throws_ok($q$select public.organization_invite_preview('f6000000-0000-4000-8000-000000000099')$q$,'P0002',null,'token inexistente não retorna convite');
select throws_ok($q$select public.accept_organization_invite('f6000000-0000-4000-8000-000000000099')$q$,'P0002',null,'ativação exige convite real correspondente');
reset role;
set local role anon;
select throws_ok($q$select * from public.accept_platform_operator_invite('f6000000-0000-4000-8000-000000000001','Anonymous QA')$q$,'42501',null,'anônimo não ativa operador');
reset role;
select ok(not has_table_privilege('authenticated','public.platform_operator_invites','TRUNCATE'),'clientes não truncam convites');
select ok(not has_function_privilege('authenticated','private.guard_operator_invitation()','EXECUTE'),'gatilho não é chamada direta');
select * from finish();
rollback;

