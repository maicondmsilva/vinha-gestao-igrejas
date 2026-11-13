begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Células · "Minha célula" no app do líder.
create function pg_temp.cl(t text) returns uuid language sql immutable as $$select md5('cell-leader-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.cl(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.cl(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-leader@example.invalid',now(),now(),now() from unnest(array['leader','member','other'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.cl('org'),'Líder fictício','cell-leader-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.cl('a'),pg_temp.cl('org'),'Igreja A','a','headquarters');
insert into public.saas_unit_contracts(organization_id,unit_id,payer_unit_id,plan_id,status,module_decisions) select pg_temp.cl('org'),pg_temp.cl('a'),pg_temp.cl('a'),id,'active','{"cells":true,"people":true}' from public.saas_plans where billing_cycle='monthly' limit 1;
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) select pg_temp.cl(t||'-m'),pg_temp.cl('org'),pg_temp.cl(t),pg_temp.cl('a'),'member','active' from unnest(array['leader','member','other'])t;
insert into public.people(id,organization_id,unit_id,full_name,status,auth_user_id,phone,birth_date) values
 (pg_temp.cl('p-leader'),pg_temp.cl('org'),pg_temp.cl('a'),'Líder Ana','active',pg_temp.cl('leader'),'11999990000','1990-03-10'::date),
 (pg_temp.cl('p-member'),pg_temp.cl('org'),pg_temp.cl('a'),'Bruno Membro','active',pg_temp.cl('member'),'11988887777',(current_date+3-interval '30 years')::date),
 (pg_temp.cl('p-new'),pg_temp.cl('org'),pg_temp.cl('a'),'Carla Indicada','active',null,null,null::date);
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by,leader_person_id) values
 (pg_temp.cl('cell'),pg_temp.cl('org'),pg_temp.cl('a'),'Célula Esperança',3,'20:00','presential',pg_temp.cl('leader'),pg_temp.cl('p-leader')),
 (pg_temp.cl('cell2'),pg_temp.cl('org'),pg_temp.cl('a'),'Outra célula',2,'20:00','presential',pg_temp.cl('leader'),null);
insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values
 (pg_temp.cl('cp-leader'),pg_temp.cl('org'),pg_temp.cl('a'),pg_temp.cl('cell'),pg_temp.cl('p-leader'),'active',pg_temp.cl('leader')),
 (pg_temp.cl('cp-member'),pg_temp.cl('org'),pg_temp.cl('a'),pg_temp.cl('cell'),pg_temp.cl('p-member'),'active',pg_temp.cl('leader'));
insert into private.cell_referrals(id,organization_id,unit_id,cell_id,person_id,person_name,status,created_by) values
 (pg_temp.cl('ref'),pg_temp.cl('org'),pg_temp.cl('a'),pg_temp.cl('cell'),pg_temp.cl('p-new'),'Carla Indicada','pending',pg_temp.cl('leader')),
 (pg_temp.cl('ref-manual'),pg_temp.cl('org'),pg_temp.cl('a'),pg_temp.cl('cell'),null,'Sem cadastro','pending',pg_temp.cl('leader'));
insert into private.cell_study_materials(id,organization_id,unit_id,network_id,title,body,url,status,created_by) values
 (pg_temp.cl('mat'),pg_temp.cl('org'),pg_temp.cl('a'),null,'Estudo da semana','Leia João 15','',
  'published',pg_temp.cl('leader')),(pg_temp.cl('draft'),pg_temp.cl('org'),pg_temp.cl('a'),null,'Rascunho','x','','draft',pg_temp.cl('leader'));
create function pg_temp.hub(a text,d jsonb default '{}',c text default 'cell') returns jsonb language sql as $$select public.member_cell_leader(pg_temp.cl('org'),pg_temp.cl('a'),pg_temp.cl(c),a,d)$$;

select ok(not has_function_privilege('anon','public.member_cell_leader(uuid,uuid,uuid,text,jsonb)','EXECUTE'),'sem acesso anônimo');
set local role authenticated;
select pg_temp.actor('leader');
select is((select string_agg(i->>'name',',') from jsonb_array_elements(pg_temp.hub('mine')->'items') i),'Célula Esperança','líder vê só a célula que lidera');
select is(pg_temp.hub('overview')->>'canReport','true','líder pode registrar');
select is(jsonb_array_length(pg_temp.hub('overview')->'people'),2,'participantes da célula');
select is((select i->>'phone' from jsonb_array_elements(pg_temp.hub('overview')->'people') i where i->>'name'='Bruno Membro'),'11988887777','telefone para WhatsApp');
select is((select i->>'birthday' from jsonb_array_elements(pg_temp.hub('overview')->'people') i where i->>'name'='Bruno Membro'),to_char(current_date+3,'MM-DD'),'aniversário sem o ano');
select is(jsonb_array_length(pg_temp.hub('overview')->'materials'),1,'só material publicado');
select is(jsonb_array_length(pg_temp.hub('overview')->'referrals'),2,'indicações pendentes');
select throws_ok($$select pg_temp.hub('overview','{}','cell2')$$,'42501',null,'não abre célula que não lidera');

select is(pg_temp.hub('meeting',jsonb_build_object('id',pg_temp.cl('meet'),'topic','Encontro de quarta','date',to_char(current_date-1,'YYYY-MM-DD'),'time','20:00'))->>'version','1','cria encontro');
select is(pg_temp.hub('meeting',jsonb_build_object('id',pg_temp.cl('meet'),'topic','Encontro de quarta','date',to_char(current_date-1,'YYYY-MM-DD'),'time','20:00'))->>'version','1','repetir não duplica');
select is((select (i->>'expected')::int from jsonb_array_elements(pg_temp.hub('overview')->'meetings') i where i->>'id'=pg_temp.cl('meet')::text),2,'chamada com os participantes ativos');
select throws_ok($$select pg_temp.hub('meeting',jsonb_build_object('id',pg_temp.cl('far'),'topic','Longe','date',to_char(current_date+90,'YYYY-MM-DD'),'time','20:00'))$$,'22023',null,'data muito distante recusada');

select throws_ok($$select pg_temp.hub('report',jsonb_build_object('meeting',pg_temp.cl('meet'),'version',1,'present',jsonb_build_array(pg_temp.cl('p-new')),'visitors','[]'::jsonb,'notes',''))$$,'22023',null,'não marca quem não está na chamada');
select throws_ok($$select pg_temp.hub('report',jsonb_build_object('meeting',pg_temp.cl('meet'),'version',1,'present','[]'::jsonb,'visitors',jsonb_build_array(jsonb_build_object('name','X','phone','')),'notes',''))$$,'22023',null,'nome de visitante curto recusado');
select is(pg_temp.hub('report',jsonb_build_object('meeting',pg_temp.cl('meet'),'version',1,'present',jsonb_build_array(pg_temp.cl('cp-member')),
 'visitors',jsonb_build_array(jsonb_build_object('name','Diego Visitante','phone','11977776666'),jsonb_build_object('name','Elisa','phone','')),'notes','Noite abençoada'))->>'visitors','2','relatório com visitantes');
select is((select i->>'status' from jsonb_array_elements(pg_temp.hub('overview')->'meetings') i where i->>'id'=pg_temp.cl('meet')::text),'completed','encontro concluído');
select is((select (i->>'present')::int from jsonb_array_elements(pg_temp.hub('overview')->'meetings') i where i->>'id'=pg_temp.cl('meet')::text),1,'presença registrada');
select is((select i->>'notes' from jsonb_array_elements(pg_temp.hub('overview')->'meetings') i where i->>'id'=pg_temp.cl('meet')::text),'Noite abençoada','observação do líder');
select is((select i->>'phone' from jsonb_array_elements(pg_temp.hub('overview')->'visitors') i where i->>'name'='Diego Visitante'),'11977776666','visitante com telefone');
select is((select i->'recent' from jsonb_array_elements(pg_temp.hub('overview')->'people') i where i->>'name'='Líder Ana'),'[false]'::jsonb,'histórico recente de presença');
select throws_ok($$select pg_temp.hub('report',jsonb_build_object('meeting',pg_temp.cl('meet'),'version',1,'present','[]'::jsonb,'visitors','[]'::jsonb,'notes',''))$$,'40001',null,'versão antiga recusada');
select is(pg_temp.hub('report',jsonb_build_object('meeting',pg_temp.cl('meet'),'version',2,'present','[]'::jsonb,'visitors',jsonb_build_array(jsonb_build_object('name','Diego Visitante','phone','')),'notes',''))->>'visitors','1','reenvio substitui visitantes');
select is(jsonb_array_length(pg_temp.hub('overview')->'visitors'),1,'sem visitante duplicado');

select is(pg_temp.hub('meeting',jsonb_build_object('id',pg_temp.cl('future'),'topic','Próximo','date',to_char(current_date+7,'YYYY-MM-DD'),'time','20:00'))->>'version','1','agenda encontro futuro');
select throws_ok($$select pg_temp.hub('report',jsonb_build_object('meeting',pg_temp.cl('future'),'version',1,'present','[]'::jsonb,'visitors','[]'::jsonb,'notes',''))$$,'22023',null,'relatório só depois do encontro');

select throws_ok($$select pg_temp.hub('referral',jsonb_build_object('id',pg_temp.cl('ref-manual'),'version',1,'answer','accept'))$$,'22023','link_member_before_accept','indicação sem cadastro não entra');
select is(pg_temp.hub('referral',jsonb_build_object('id',pg_temp.cl('ref'),'version',1,'answer','accept'))->>'version','2','aceita indicação');
select is(jsonb_array_length(pg_temp.hub('overview')->'people'),3,'indicado passa a participar');
select is(pg_temp.hub('referral',jsonb_build_object('id',pg_temp.cl('ref-manual'),'version',1,'answer','decline'))->>'version','2','recusa indicação');
select is(jsonb_array_length(pg_temp.hub('overview')->'referrals'),0,'sem pendências');

select pg_temp.actor('member');
select is(jsonb_array_length(pg_temp.hub('mine')->'items'),0,'participante comum não lidera');
select throws_ok($$select pg_temp.hub('overview')$$,'42501',null,'participante não abre a gestão');
select pg_temp.actor('other');
select throws_ok($$select pg_temp.hub('meeting',jsonb_build_object('id',pg_temp.cl('x'),'topic','Invasão','date',to_char(current_date,'YYYY-MM-DD'),'time','20:00'))$$,'42501',null,'outra pessoa não cria encontro');
reset role;
update public.people set status='inactive' where id=pg_temp.cl('p-leader');
set local role authenticated;
select pg_temp.actor('leader');
select throws_ok($$select pg_temp.hub('overview')$$,'42501',null,'líder inativo perde acesso');
select * from finish();
rollback;
