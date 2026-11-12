begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Cadastro pelo app nasce ativo; reprovação (total ou parcial) avisa no app e coloca o e-mail na fila.
create function pg_temp.mr(t text) returns uuid language sql immutable as $$select md5('member-review-notice-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.mr(t),'role','authenticated','email',t||'-notice@example.invalid')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.mr(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-notice@example.invalid',now(),now(),now() from unnest(array['owner','ana','bia','caio']) t;
insert into public.organizations(id,name,slug,status) values(pg_temp.mr('org'),'Igreja aviso','member-review-notice','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.mr('unit'),pg_temp.mr('org'),'Sede aviso','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(pg_temp.mr('org'),pg_temp.mr('owner'),pg_temp.mr('unit'),'owner','active');
create function pg_temp.submit(d jsonb) returns jsonb language sql as $$select public.member_self_service(pg_temp.mr('org'),'submit',pg_temp.mr('unit'),d)$$;
create function pg_temp.req(u text) returns uuid language sql security definer as $$select id from private.member_profile_requests where organization_id=pg_temp.mr('org') and user_id=pg_temp.mr(u) order by created_at desc limit 1$$;
create function pg_temp.review(u text, f text[], reason text) returns jsonb language sql as $$select public.member_profile_review2(pg_temp.mr('org'),'review',pg_temp.req(u),jsonb_build_object('fields',to_jsonb(f),'reason',reason))$$;
create function pg_temp.inbox(u text) returns setof jsonb language sql security definer as $$select to_jsonb(x) from private.member_inbox_rows(pg_temp.mr('org'),pg_temp.mr('unit')) x where x.message_key like 'profile-review:%'$$;

set local role authenticated;
select pg_temp.actor('ana');
select lives_ok($$select pg_temp.submit('{"full_name":"Ana Aviso","phone":"11988887777","cpf":"12345678901"}')$$,'ana se cadastra pelo app');
select is(public.member_self_service(pg_temp.mr('org'),'profile')->>'membershipStatus','active','cadastro pelo app nasce ativo');
select pg_temp.actor('bia');
select lives_ok($$select pg_temp.submit('{"full_name":"Bia Aviso","phone":"11977776666"}')$$,'bia se cadastra pelo app');
select pg_temp.actor('caio');
select lives_ok($$select pg_temp.submit('{"full_name":"Caio Aviso"}')$$,'caio se cadastra pelo app');
reset role;
select is((select kind from private.member_profile_requests where id=pg_temp.req('ana')),'registration','cadastro novo continua sendo análise de cadastro');
select is((select count(*)::int from public.organization_memberships where organization_id=pg_temp.mr('org') and status='active' and role='member'),3,'os três usuários do app têm acesso');
set local role authenticated;

select pg_temp.actor('owner');
select lives_ok($$select pg_temp.review('ana','{}','CPF não confere com o documento enviado')$$,'reprovação total');
select lives_ok($$select pg_temp.review('bia','{full_name}','O celular informado não recebe mensagens')$$,'reprovação parcial');
select lives_ok($$select pg_temp.review('caio','{full_name}','Tudo certo com o cadastro')$$,'aprovação total');

select pg_temp.actor('ana');
select is((select count(*)::int from pg_temp.inbox('ana')),1,'reprovação gera alerta no app');
select ok((select i->>'body' from pg_temp.inbox('ana') i) like '%Nome%' and (select i->>'body' from pg_temp.inbox('ana') i) like '%CPF%' and (select i->>'body' from pg_temp.inbox('ana') i) like '%CPF não confere%','alerta traz os campos e o motivo');
select is((select i->>'target' from pg_temp.inbox('ana') i),'profile','alerta leva para corrigir o cadastro');
select pg_temp.actor('bia');
select ok((select i->>'body' from pg_temp.inbox('bia') i) like '%Celular%' and (select i->>'body' from pg_temp.inbox('bia') i) not like '%Nome%','reprovação parcial lista só os campos não aprovados');
select pg_temp.actor('caio');
select is((select count(*)::int from pg_temp.inbox('caio')),0,'aprovação total não gera aviso de ajuste');
select is(public.member_self_service(pg_temp.mr('org'),'profile')->>'membershipStatus','active','aprovado continua ativo');

-- Corrigir e reenviar tira o alerta antigo da caixa.
select pg_temp.actor('ana');
select lives_ok($$select pg_temp.submit('{"full_name":"Ana Aviso","cpf":"98765432100"}')$$,'ana corrige e reenvia');
select is((select count(*)::int from pg_temp.inbox('ana')),0,'reenvio tira o alerta antigo');

reset role;
select is((select count(*)::int from private.member_review_emails where organization_id=pg_temp.mr('org')),2,'reprovação coloca e-mail na fila (total e parcial)');
select is((select recipient from private.member_review_emails where user_id=pg_temp.mr('bia')),'bia-notice@example.invalid','e-mail vai para o login da pessoa');
select is((select items from private.member_review_emails where user_id=pg_temp.mr('bia')),'["Celular"]'::jsonb,'e-mail lista os campos não aprovados');
select is((select status from private.member_review_emails where user_id=pg_temp.mr('ana')),'pending','e-mail entra pendente');
select ok(not has_function_privilege('authenticated','public.member_review_email_mark(uuid,boolean,text)','EXECUTE'),'só o servidor marca o envio');
select ok(not has_function_privilege('authenticated','public.member_review_email_batch(integer)','EXECUTE'),'só o servidor reserva a fila');

-- Fila: reserva e nova tentativa.
select set_config('t.ana_mail',(select id::text from private.member_review_emails where user_id=pg_temp.mr('ana')),true);
select set_config('t.bia_mail',(select id::text from private.member_review_emails where user_id=pg_temp.mr('bia')),true);
set local role service_role;
select is((select count(*)::int from public.member_review_email_batch(10)),2,'servidor reserva os pendentes');
select is((select count(*)::int from public.member_review_email_batch(10)),0,'item reservado não sai duas vezes');
select lives_ok($$select public.member_review_email_mark(current_setting('t.ana_mail')::uuid,false,'SMTP fora do ar')$$,'falha no envio registrada');
select lives_ok($$select public.member_review_email_mark(current_setting('t.bia_mail')::uuid,true,null)$$,'envio registrado');
reset role;
select is((select status||'/'||attempts from private.member_review_emails where user_id=pg_temp.mr('ana')),'pending/1','falha volta para a fila com nova tentativa');
select ok((select next_at>now() from private.member_review_emails where user_id=pg_temp.mr('ana')),'nova tentativa fica para depois');
select is((select status from private.member_review_emails where user_id=pg_temp.mr('bia')),'sent','enviado fica marcado');
select * from finish();
rollback;
