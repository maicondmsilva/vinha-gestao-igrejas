begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select ('a8000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','governance-'||i||'@example.test','',now(),now(),now() from generate_series(1,7) i;
insert into public.organizations(id,name,slug,status) values
 ('b8000000-0000-4000-8000-000000000001','Governança A','governance-a','active'),
 ('b8000000-0000-4000-8000-000000000002','Governança B','governance-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','Sede','sede','headquarters'),
 ('c8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000002','Sede','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
select ('d8000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'b8000000-0000-4000-8000-000000000001',('a8000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 (case i when 1 then 'owner' when 2 then 'admin' when 3 then 'pastor' when 4 then 'leader' else 'member' end)::public.membership_role,'active','c8000000-0000-4000-8000-000000000001' from generate_series(1,5) i;
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id)
values('b8000000-0000-4000-8000-000000000002','a8000000-0000-4000-8000-000000000006','owner','active','c8000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$update public.organization_memberships set role='admin' where id='d8000000-0000-4000-8000-000000000001'$$,'42501','last_active_organization_owner','último proprietário não se rebaixa');
select throws_ok($$update public.organization_memberships set status='suspended' where id='d8000000-0000-4000-8000-000000000001'$$,'42501','last_active_organization_owner','último proprietário não é suspenso');
select throws_ok($$update public.organization_memberships set status='revoked' where id='d8000000-0000-4000-8000-000000000001'$$,'42501','last_active_organization_owner','último proprietário não é revogado');
select throws_ok($$delete from public.organization_memberships where id='d8000000-0000-4000-8000-000000000001'$$,'42501','last_active_organization_owner','último proprietário não é excluído');
select is((select count(*) from public.organization_membership_events where organization_id='b8000000-0000-4000-8000-000000000001' and operation='UPDATE'),0::bigint,'operações recusadas não produzem falso histórico de sucesso');
select lives_ok($$update public.organization_memberships set role='owner' where id='d8000000-0000-4000-8000-000000000005'$$,'proprietário nomeia sucessor');
select is((select actor_user_id from public.organization_membership_events where membership_id='d8000000-0000-4000-8000-000000000005' and operation='UPDATE' order by created_at desc limit 1),'a8000000-0000-4000-8000-000000000001'::uuid,'auditoria obtém ator autenticado');
select is((select before_state->>'role' from public.organization_membership_events where membership_id='d8000000-0000-4000-8000-000000000005' and operation='UPDATE' order by created_at desc limit 1),'member','auditoria guarda papel anterior');
select lives_ok($$update public.organization_memberships set role='admin' where id='d8000000-0000-4000-8000-000000000001'$$,'sucessão permite saída do proprietário anterior após sucessor ativo');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select throws_ok($$update public.organization_memberships set role='leader' where id='d8000000-0000-4000-8000-000000000005'$$,'42501','last_active_organization_owner','sucessor agora é o último proprietário protegido');
select lives_ok($$delete from public.organization_memberships where id='d8000000-0000-4000-8000-000000000001'$$,'novo proprietário pode remover participação antiga sem deixar ministério sem dono');
select is((select count(*) from public.organization_membership_events where membership_id='d8000000-0000-4000-8000-000000000001' and operation='DELETE'),1::bigint,'histórico permanece após excluir participação');
select throws_ok($$insert into public.organization_membership_events(organization_id,membership_id,subject_user_id,operation,execution_role) values('b8000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','UPDATE','authenticated')$$,'42501',null,'cliente não fabrica evento de governança');
select throws_ok($$update public.organization_membership_events set operation='DELETE'$$,'42501',null,'histórico não é reescrito pelo cliente');
select throws_ok($$delete from public.organization_membership_events$$,'42501',null,'histórico não é apagado pelo cliente');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select throws_ok($$update public.organization_memberships set role='owner' where id='d8000000-0000-4000-8000-000000000002'$$,'42501','membership_role_grant_denied','administrador não promove a si mesmo');
select throws_ok($$update public.organization_memberships set status='suspended' where id='d8000000-0000-4000-8000-000000000005'$$,'42501','membership_role_grant_denied','administrador não altera proprietário');
select throws_ok($$insert into public.organization_memberships(organization_id,user_id,role,status) values('b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000006','admin','active')$$,'42501','membership_role_grant_denied','administrador não nomeia pares');
select throws_ok($$insert into public.organization_memberships(organization_id,user_id,role,status) values('b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000006','owner','active')$$,'42501','membership_role_grant_denied','administrador não cria proprietário por inserção');
select lives_ok($$update public.organization_memberships set role='pastor' where id='d8000000-0000-4000-8000-000000000004'$$,'administrador pode gerir papéis inferiores');
select lives_ok($$update public.organization_memberships set default_unit_id=null where id='d8000000-0000-4000-8000-000000000002'$$,'administrador mantém preferência própria sem mudar poderes');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$update public.organization_memberships set role='admin' where id='d8000000-0000-4000-8000-000000000003'$$,'42501','membership_role_grant_denied','pastor não eleva seu papel');
select throws_ok($$update public.organization_memberships set status='suspended' where id='d8000000-0000-4000-8000-000000000002'$$,'42501','membership_role_grant_denied','pastor não suspende administrador');
select throws_ok($$update public.organization_memberships set status='suspended' where id='d8000000-0000-4000-8000-000000000004'$$,'42501','membership_role_grant_denied','pastor não gerencia pares');
select throws_ok($$insert into public.organization_memberships(organization_id,user_id,role,status) values('b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000006','pastor','active')$$,'42501','membership_role_grant_denied','pastor não cria par');
select lives_ok($$insert into public.organization_memberships(organization_id,user_id,role,status) values('b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000006','secretary','active')$$,'pastor pode criar papel inferior');
select is((select count(*) from public.organization_membership_events where organization_id='b8000000-0000-4000-8000-000000000001'),0::bigint,'pastor não recebe leitura irrestrita da auditoria');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
with changed as(update public.organization_memberships set role='owner' where organization_id='b8000000-0000-4000-8000-000000000001' and user_id=auth.uid() returning id)
select is((select count(*) from changed),0::bigint,'papel inferior não promove conta mesmo sendo proprietário em outro ministério');
select is((select count(*) from public.organization_membership_events where organization_id='b8000000-0000-4000-8000-000000000001'),0::bigint,'proprietário estrangeiro não lê auditoria');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000007","role":"authenticated"}',true);
select lives_ok($$select public.bootstrap_organization('Bootstrap governança','bootstrap-governance','Sede','Responsável')$$,'cadastro inicial mantém o primeiro proprietário legítimo');
reset role;
create function pg_temp.fail_governance_event() returns trigger language plpgsql as $$begin if current_setting('vinha.fail_membership_audit',true)='yes' then raise exception 'forced_governance_audit_failure' using errcode='23514';end if;return new;end;$$;
create trigger test_governance_audit before insert on public.organization_membership_events for each row execute function pg_temp.fail_governance_event();
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select set_config('vinha.fail_membership_audit','yes',true);
select throws_ok($$update public.organization_memberships set status='suspended' where id='d8000000-0000-4000-8000-000000000002'$$,'23514','forced_governance_audit_failure','falha de auditoria reverte alteração de acesso');
select is((select status::text from public.organization_memberships where id='d8000000-0000-4000-8000-000000000002'),'active','participação original permanece ativa após rollback');
select set_config('vinha.fail_membership_audit','no',true);
reset role;
update public.organizations set status='suspended' where id='b8000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$update public.organization_memberships set role='leader' where id='d8000000-0000-4000-8000-000000000003'$$,'42501','organization_access_denied','suspensão do ministério bloqueia mudança de acesso');
select is((select count(*) from public.organization_membership_events where organization_id='b8000000-0000-4000-8000-000000000001'),0::bigint,'ministério suspenso não expõe eventos');
select ok(not has_function_privilege('authenticated','private.guard_membership_governance()','EXECUTE'),'gatilho de proteção não é chamada direta');
select ok(not has_function_privilege('authenticated','private.audit_membership_governance()','EXECUTE'),'gatilho de auditoria não é chamada direta');
select ok(not has_function_privilege('anon','private.check_membership_governance(uuid,uuid,uuid,public.membership_role,public.membership_status,text)','EXECUTE'),'visitante não executa verificador interno');
reset role;
select * from finish();
rollback;
