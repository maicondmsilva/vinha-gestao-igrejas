begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Células com permissões concedidas na ficha do usuário (P3/P4), limitadas a células ou redes.
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a7500000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-cell-'||i||'@example.test',now(),now(),now() from generate_series(1,2)i;
insert into public.organizations(id,name,slug,status) values('b7500000-0000-4000-8000-000000000001','Células P3','p3-cell-synthetic','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values('c7500000-0000-4000-8000-000000000001','b7500000-0000-4000-8000-000000000001','Sede células','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7500000-0000-4000-8000-000000000001','b7500000-0000-4000-8000-000000000001','a7500000-0000-4000-8000-000000000001','owner','active','c7500000-0000-4000-8000-000000000001'),
 ('d7500000-0000-4000-8000-000000000002','b7500000-0000-4000-8000-000000000001','a7500000-0000-4000-8000-000000000002','member','active','c7500000-0000-4000-8000-000000000001');
-- Células: A e B na rede Norte (filha da rede Geral); C na rede Sul.
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by)
select ('f7500000-0000-4000-8000-00000000000'||i)::uuid,'b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','Célula '||chr(64+i),1,'19:00','presential','a7500000-0000-4000-8000-000000000001' from generate_series(1,3)i;
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by)
select id::uuid,'b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001',name,'active','a7500000-0000-4000-8000-000000000001' from (values('fa750000-0000-4000-8000-000000000001','Geral'),('fa750000-0000-4000-8000-000000000002','Norte'),('fa750000-0000-4000-8000-000000000003','Sul')) v(id,name);
insert into public.church_cell_network_parents(network_id,organization_id,unit_id,parent_id,updated_by)
values('fa750000-0000-4000-8000-000000000002','b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','fa750000-0000-4000-8000-000000000001','a7500000-0000-4000-8000-000000000001');
insert into public.church_cell_network_links(cell_id,organization_id,unit_id,network_id,updated_by) values
 ('f7500000-0000-4000-8000-000000000001','b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','fa750000-0000-4000-8000-000000000002','a7500000-0000-4000-8000-000000000001'),
 ('f7500000-0000-4000-8000-000000000002','b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','fa750000-0000-4000-8000-000000000002','a7500000-0000-4000-8000-000000000001'),
 ('f7500000-0000-4000-8000-000000000003','b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','fa750000-0000-4000-8000-000000000003','a7500000-0000-4000-8000-000000000001');

create function pg_temp.as_user(i integer) returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub','a7500000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true)$$;
create function pg_temp.grant(p text,acts jsonb,extra jsonb default '{}') returns jsonb language sql as $$select public.permission_admin('b7500000-0000-4000-8000-000000000001','set',jsonb_build_object('membership','d7500000-0000-4000-8000-000000000002','permission',p,'unit','c7500000-0000-4000-8000-000000000001','actions',acts,'includeChildren',false)||extra)$$;
create function pg_temp.revoke(p text) returns jsonb language sql as $$select public.permission_admin('b7500000-0000-4000-8000-000000000001','remove',jsonb_build_object('membership','d7500000-0000-4000-8000-000000000002','permission',p,'unit','c7500000-0000-4000-8000-000000000001'))$$;
create function pg_temp.cell_ok(c integer,cap text default 'read') returns boolean language sql as $$select private.cell_plus_cell('b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001',('f7500000-0000-4000-8000-00000000000'||c)::uuid,'a7500000-0000-4000-8000-000000000002'::uuid,cap)$$;
create function pg_temp.dir() returns jsonb language sql as $$select public.cell_directory_list_v2('b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001',null)$$;

select ok(has_function_privilege('authenticated','private.cell_manage_allowed(uuid,uuid,text)','execute'),'regra de gestão disponível para as leituras');
select ok(not has_function_privilege('authenticated','private.cell_plus_cell(uuid,uuid,uuid,uuid,text)','execute'),'regra de célula não é exposta');

-- Sem permissão: nada.
set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select pg_temp.dir()$$,'42501',null,'membro sem permissão não vê o cadastro de células');
reset role;
select pg_temp.as_user(2);
select ok(not pg_temp.cell_ok(1),'sem permissão não acompanha célula');

-- Limitado à rede Geral: acompanha as células das redes abaixo (Norte), não a Sul.
set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('cells.cells','["view","edit"]','{"groupKind":"network","groups":["fa750000-0000-4000-8000-000000000001"]}')$$,'concede Células limitado à rede Geral');
select pg_temp.as_user(2);
select throws_ok($$select pg_temp.dir()$$,'42501',null,'limitado a rede não abre o cadastro da igreja inteira');
select lives_ok($$select public.cell_plus_read('b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','reports',null,null,current_date-30,current_date,null)$$,'abre o acompanhamento');
select is((select jsonb_agg(x->>'name' order by x->>'name') from jsonb_array_elements(public.cell_plus_read('b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','reports',null,null,current_date-30,current_date,null)->'cells') x),'["Célula A", "Célula B"]'::jsonb,'vê só as células da rede concedida e das redes abaixo');
reset role;
select pg_temp.as_user(2);
select ok(pg_temp.cell_ok(1),'acompanha célula da rede Norte (filha da Geral)');
select ok(pg_temp.cell_ok(1,'followup'),'editar = acompanhamento');
select ok(not pg_temp.cell_ok(1,'report'),'sem Relatórios não registra relatório');
select ok(not pg_temp.cell_ok(3),'não acompanha célula da rede Sul');

-- Limitado a uma célula.
set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('cells.cells','["view"]','{"groupKind":"cell","groups":["f7500000-0000-4000-8000-000000000003"]}')$$,'troca para só a célula C');
reset role;
select pg_temp.as_user(2);
select ok(pg_temp.cell_ok(3),'acompanha a célula concedida');
select ok(not pg_temp.cell_ok(1),'não acompanha as outras');
select ok(not pg_temp.cell_ok(3,'followup'),'só ver não faz acompanhamento');

-- Sem limite: cadastro da igreja; gestão só com editar.
set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('cells.cells','["view"]')$$,'concede ver Células sem limite');
select pg_temp.as_user(2);
select is(jsonb_array_length(pg_temp.dir()->'items'),3,'vê o cadastro de células da igreja');
select is(pg_temp.dir()->>'canManage','false','só ver não gerencia');
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('cells.cells','["view","edit"]')$$,'concede editar Células');
select pg_temp.as_user(2);
select is(pg_temp.dir()->>'canManage','true','com editar, gerencia');
select lives_ok($$select public.cell_directory_save('b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001',(select version from public.church_cells where id='f7500000-0000-4000-8000-000000000001'),'{"name":"Célula A renomeada","leader_name":"","leader_person_id":null,"meeting_day":2,"meeting_time":"20:00","meeting_format":"presential","location":"","status":"active"}')$$,'edita a célula');
select throws_ok($$select public.cell_networks_save('b7500000-0000-4000-8000-000000000001','c7500000-0000-4000-8000-000000000001','network','fa750000-0000-4000-8000-000000000009',0,'{"name":"Nova rede","supervisor_name":"","supervisor_person_id":null,"status":"active"}')$$,'42501',null,'Células não cria rede');
reset role;
select * from finish();
rollback;
