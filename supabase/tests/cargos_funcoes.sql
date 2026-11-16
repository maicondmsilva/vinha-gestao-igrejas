-- Grupos, Cargos e Funções: catálogo, vários cargos, "Pastor", sincronização com células/redes/ministérios,
-- acesso proposto (só com confirmação), liderança no app com telefone autorizado e mensagens. Tudo desfeito no fim.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a7700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','cargos-'||n||'@example.test',now(),now(),now() from generate_series(1,5)n;
insert into public.organizations(id,name,slug,status) values('b7700000-0000-4000-8000-000000000001','Igreja dos cargos','cargos-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values('c7700000-0000-4000-8000-000000000001','b7700000-0000-4000-8000-000000000001','Sede','sede','headquarters');
-- 1 dono, 2 líder (usuário da equipe), 3 membro do app, 4 membro do app, 5 secretaria
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
select ('e7700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b7700000-0000-4000-8000-000000000001',('a7700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 (case n when 1 then 'owner' when 2 then 'leader' when 5 then 'secretary' else 'member' end)::public.membership_role,'active','c7700000-0000-4000-8000-000000000001' from generate_series(1,5)n;
insert into public.people(id,organization_id,unit_id,full_name,gender,phone,status,auth_user_id)
select ('d7700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001',
 (array['Davi Dono','Ana Líder','Bruno Membro','Carla Membro','Sara Secretaria'])[n],(array['Masculino','Feminino','Masculino','Feminino','Feminino'])[n],'(11) 9000'||n||'-0000','active',
 ('a7700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,5)n;
insert into public.people(id,organization_id,unit_id,full_name,status,group_name) values
 ('d7700000-0000-4000-8000-000000000009','b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','Texto Antigo','active','  célula esperança '),
 ('d7700000-0000-4000-8000-000000000010','b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','Grupo Inexistente','active','Min. Qualquer');
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by)
values('f7700000-0000-4000-8000-000000000001','b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','Célula Esperança',2,'20:00','presential','a7700000-0000-4000-8000-000000000001');
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by)
values('fa770000-0000-4000-8000-000000000001','b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','Rede Jovens','active','a7700000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000001","role":"authenticated","email":"cargos-1@example.test","aal":"aal2"}',true);

-- Catálogo com padrões
select is(jsonb_array_length(public.church_roles('b7700000-0000-4000-8000-000000000001','catalog')->'positions'),7,'sete cargos sugeridos');
select is(public.church_roles('b7700000-0000-4000-8000-000000000001','catalog')->>'label','Cargo','nome padrão do conceito');
select ok(jsonb_array_length(public.church_roles('b7700000-0000-4000-8000-000000000001','catalog')->'functions')>=12,'funções sugeridas por tipo');
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','position.save','{"name":"Apóstolo","nameFemale":"Apóstola","pastoral":true}')$$,'igreja cria cargo');
select throws_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','position.save','{"name":"apóstolo"}')$$,'23505',null,'sem cargo repetido');

reset role;
create temp table ids(k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids select 'pastor',id from private.church_positions where organization_id='b7700000-0000-4000-8000-000000000001' and system_key='pastor';
insert into ids select 'missio',id from private.church_positions where organization_id='b7700000-0000-4000-8000-000000000001' and system_key='missionario';
insert into ids select 'cell_leader',id from private.group_functions where organization_id='b7700000-0000-4000-8000-000000000001' and kind='cell' and system_key='leader';
insert into ids select 'cell_host',id from private.group_functions where organization_id='b7700000-0000-4000-8000-000000000001' and kind='cell' and system_key='host';
insert into ids select 'min_leader',id from private.group_functions where organization_id='b7700000-0000-4000-8000-000000000001' and kind='ministry' and system_key='leader';
set local role authenticated;

-- Vários cargos ao mesmo tempo, nome feminino, e "Pastor" sincronizado
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','person.position.add',jsonb_build_object('person','d7700000-0000-4000-8000-000000000002','position',(select v from ids where k='pastor'),'since','2015-03-01'))$$,'cargo Pastora');
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','person.position.add',jsonb_build_object('person','d7700000-0000-4000-8000-000000000002','position',(select v from ids where k='missio')))$$,'e Missionária');
select is((select string_agg(x->>'name',', ' order by x->>'name') from jsonb_array_elements(public.church_roles('b7700000-0000-4000-8000-000000000001','person','{"person":"d7700000-0000-4000-8000-000000000002"}')->'positions') x),'Missionária, Pastora','dois cargos no feminino');
reset role;
select ok((select is_pastor from public.people where id='d7700000-0000-4000-8000-000000000002'),'cargo pastoral marca a pessoa como pastor (Agenda pastoral)');
update public.people set is_pastor=true where id='d7700000-0000-4000-8000-000000000003';
select is((select count(*)::int from private.person_positions where person_id='d7700000-0000-4000-8000-000000000003' and until is null),1,'marcar Pastor na ficha do usuário cria o cargo');
update public.people set is_pastor=false where id='d7700000-0000-4000-8000-000000000003';
select is((select count(*)::int from private.person_positions where person_id='d7700000-0000-4000-8000-000000000003' and until is null),0,'desmarcar encerra o cargo');
set local role authenticated;

-- Função de liderança na célula: célula atualiza e o acesso é só proposto
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','assign',jsonb_build_object('person','d7700000-0000-4000-8000-000000000002','kind','cell','group','f7700000-0000-4000-8000-000000000001','function',(select v from ids where k='cell_leader')))$$,'Ana vira líder da célula');
reset role;
select is((select leader_person_id from public.church_cells where id='f7700000-0000-4000-8000-000000000001'),'d7700000-0000-4000-8000-000000000002'::uuid,'a célula passa a ter a Ana como líder');
select ok(exists(select 1 from public.church_cell_participants where cell_id='f7700000-0000-4000-8000-000000000001' and person_id='d7700000-0000-4000-8000-000000000002' and status='active'),'líder entra como participante');
select is((select group_name from public.people where id='d7700000-0000-4000-8000-000000000002'),'Célula Esperança','"Grupo" da lista vem da função');
select is((select count(*)::int from private.permission_grants g where g.membership_id='e7700000-0000-4000-8000-000000000002'),0,'nenhum acesso sem confirmação');
select is((select count(*)::int from private.access_proposals where person_id='d7700000-0000-4000-8000-000000000002' and status='pending' and action='grant'),1,'acesso proposto');
set local role authenticated;

-- Secretaria não aprova acesso; dono aprova com um clique
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000005","role":"authenticated","email":"cargos-5@example.test","aal":"aal2"}',true);
select throws_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','access.list')$$,'42501',null,'secretaria não decide acessos');
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000001","role":"authenticated","email":"cargos-1@example.test","aal":"aal2"}',true);
select is(jsonb_array_length(public.church_roles('b7700000-0000-4000-8000-000000000001','access.list')->'items'),1,'dono vê a proposta');
reset role;
insert into ids select 'prop',id from private.access_proposals where person_id='d7700000-0000-4000-8000-000000000002' and status='pending';
set local role authenticated;
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','access.approve',jsonb_build_object('id',(select v from ids where k='prop')))$$,'dono confirma');
reset role;
select is((select group_kind||':'||array_to_string(group_ids,',') from private.permission_grants where membership_id='e7700000-0000-4000-8000-000000000002' and permission='cells.reports'),'cell:f7700000-0000-4000-8000-000000000001','acesso só à própria célula');
set local role authenticated;

-- Saiu da função: retirada também é proposta
reset role;
insert into ids select 'asg',id from private.group_assignments where person_id='d7700000-0000-4000-8000-000000000002' and kind='cell' and until is null;
set local role authenticated;
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','unassign',jsonb_build_object('id',(select v from ids where k='asg')))$$,'Ana deixa a liderança');
reset role;
select is((select leader_person_id from public.church_cells where id='f7700000-0000-4000-8000-000000000001'),null,'célula fica sem líder');
select is((select count(*)::int from private.permission_grants where membership_id='e7700000-0000-4000-8000-000000000002'),2,'acesso continua até confirmarem a retirada');
insert into ids select 'rev',id from private.access_proposals where person_id='d7700000-0000-4000-8000-000000000002' and status='pending' and action='revoke';
set local role authenticated;
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','access.approve',jsonb_build_object('id',(select v from ids where k='rev')))$$,'dono confirma a retirada');
reset role;
select is((select count(*)::int from private.permission_grants where membership_id='e7700000-0000-4000-8000-000000000002'),0,'acesso retirado');

-- Líder pelo módulo Células também vira função
update public.church_cells set leader_person_id='d7700000-0000-4000-8000-000000000004' where id='f7700000-0000-4000-8000-000000000001';
select ok(exists(select 1 from private.group_assignments a where a.person_id='d7700000-0000-4000-8000-000000000004' and a.kind='cell' and a.until is null),'líder definido em Células aparece como função');
update public.church_cell_networks set supervisor_person_id='d7700000-0000-4000-8000-000000000003' where id='fa770000-0000-4000-8000-000000000001';
select ok(exists(select 1 from private.group_assignments a join private.group_functions f on f.id=a.function_id where a.person_id='d7700000-0000-4000-8000-000000000003' and a.kind='network' and f.system_key='supervisor' and a.until is null),'supervisor da rede aparece como função');
set local role authenticated;

-- Conferência do texto antigo de "Grupo"
select is(jsonb_array_length(public.church_roles('b7700000-0000-4000-8000-000000000001','review.list')->'items'),2,'dois cadastros com texto antigo para conferir');
select is((select x->'match'->>'name' from jsonb_array_elements(public.church_roles('b7700000-0000-4000-8000-000000000001','review.list')->'items') x where x->>'person'='d7700000-0000-4000-8000-000000000009'),'Célula Esperança','sugere o grupo com o mesmo nome');
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','review.link','{"person":"d7700000-0000-4000-8000-000000000009","kind":"cell","group":"f7700000-0000-4000-8000-000000000001"}')$$,'vincula');
select lives_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','review.clear','{"person":"d7700000-0000-4000-8000-000000000010"}')$$,'limpa o que não bate');
select is(jsonb_array_length(public.church_roles('b7700000-0000-4000-8000-000000000001','review.list')->'items'),0,'nada para conferir');

-- Filtros da lista
select is(jsonb_array_length(public.people_search('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001',jsonb_build_object('position',(select v from ids where k='missio')),1,25)->'ids'),1,'filtro por cargo');
select ok(jsonb_array_length(public.people_search('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','{"leaders":true}',1,25)->'ids')>=2,'filtro de liderança');

-- Membro comum não gerencia
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','position.save','{"name":"Bispo"}')$$,'42501',null,'membro não cria cargo');
select throws_ok($$select public.church_roles('b7700000-0000-4000-8000-000000000001','assign',jsonb_build_object('person','d7700000-0000-4000-8000-000000000003','kind','cell','group','f7700000-0000-4000-8000-000000000001','function',(select v from ids where k='cell_host')))$$,'42501',null,'membro não se dá função');

-- App: minhas funções, liderança com telefone autorizado, mensagens
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(jsonb_array_length(public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','mine')->'positions'),2,'Ana vê os dois cargos no app');
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is((select x->>'phone' from jsonb_array_elements(public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','leadership')->'items') x where x->>'person'='d7700000-0000-4000-8000-000000000002'),'','telefone escondido sem autorização');
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select lives_ok($$select public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','privacy','{"showPhone":true}')$$,'Ana autoriza o telefone');
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select is((select x->>'phone' from jsonb_array_elements(public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','leadership')->'items') x where x->>'person'='d7700000-0000-4000-8000-000000000002'),'(11) 90002-0000','telefone aparece depois de autorizado');
select lives_ok($$select public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','send','{"to":"d7700000-0000-4000-8000-000000000002","body":"Pastora, posso conversar?"}')$$,'membro envia mensagem à liderança');
select throws_ok($$select public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','send','{"to":"d7700000-0000-4000-8000-000000000005","body":"Oi"}')$$,'42501',null,'não envia para quem não é liderança');
select set_config('request.jwt.claims','{"sub":"a7700000-0000-4000-8000-000000000002","role":"authenticated"}',true);
reset role;
select ok(exists(select 1 from private.member_inbox_rows('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001') where target='leadership'),'mensagem chega na caixa de notificações');
set local role authenticated;
select lives_ok($$select public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','send','{"to":"d7700000-0000-4000-8000-000000000003","body":"Claro, amanhã às 19h."}')$$,'líder responde');
select is(jsonb_array_length(public.member_roles('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','messages')->'items'),2,'conversa com as duas mensagens');

select * from finish();
rollback;
