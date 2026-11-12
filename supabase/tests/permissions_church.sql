begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Igreja (igrejas/filiais e configurações) com permissões concedidas na ficha do usuário (P3).
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select ('a7700000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-church-'||i||'@example.test',now(),now(),now() from generate_series(1,2)i;
insert into public.organizations(id,name,slug,status) values('b7700000-0000-4000-8000-000000000001','Igreja P3','p3-church-synthetic','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 ('c7700000-0000-4000-8000-000000000001','b7700000-0000-4000-8000-000000000001','Sede igreja','sede','headquarters'),
 ('c7700000-0000-4000-8000-000000000002','b7700000-0000-4000-8000-000000000001','Outra igreja','outra','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 ('d7700000-0000-4000-8000-000000000001','b7700000-0000-4000-8000-000000000001','a7700000-0000-4000-8000-000000000001','owner','active','c7700000-0000-4000-8000-000000000001'),
 ('d7700000-0000-4000-8000-000000000002','b7700000-0000-4000-8000-000000000001','a7700000-0000-4000-8000-000000000002','member','active','c7700000-0000-4000-8000-000000000001');
create function pg_temp.as_user(i integer) returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub','a7700000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true)$$;
create function pg_temp.grant(p text,acts jsonb,u text default 'c7700000-0000-4000-8000-000000000001') returns jsonb language sql as $$select public.permission_admin('b7700000-0000-4000-8000-000000000001','set',jsonb_build_object('membership','d7700000-0000-4000-8000-000000000002','permission',p,'unit',u,'actions',acts,'includeChildren',true))$$;
create function pg_temp.payload() returns jsonb language sql as $$select jsonb_build_object('updatedAt',o.updated_at,'name','Ministério novo','appName','App','seniorPastorName','Pastor fictício','legalName','','taxId','','primaryColor','#285c45','accentColor','#d8b769') from public.organizations o where id='b7700000-0000-4000-8000-000000000001'$$;

set local role authenticated;
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('church.units','["view","create","edit"]')$$,'concede Igrejas na sede e filhas');
select lives_ok($$select pg_temp.grant('church.settings','["view","edit"]')$$,'concede Configurações só na sede');
select pg_temp.as_user(2);
update public.organization_units set name='Sede renomeada' where id='c7700000-0000-4000-8000-000000000001';
select is((select name from public.organization_units where id='c7700000-0000-4000-8000-000000000001'),'Sede renomeada','edita a igreja concedida');
update public.organization_units set name='Outra renomeada' where id='c7700000-0000-4000-8000-000000000002';
select is((select count(*)::integer from public.organization_units where name='Outra renomeada'),0,'não edita igreja fora da permissão');
select lives_ok($$insert into public.organization_units(id,organization_id,parent_unit_id,name,slug,unit_type) values('c7700000-0000-4000-8000-000000000003','b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000001','Filial nova','filial-nova','campus')$$,'cria filial abaixo da igreja concedida');
select throws_ok($$insert into public.organization_units(organization_id,parent_unit_id,name,slug,unit_type) values('b7700000-0000-4000-8000-000000000001','c7700000-0000-4000-8000-000000000002','Filial indevida','filial-indevida','campus')$$,'42501',null,'não cria filial fora da permissão');
select throws_ok($$select public.organization_settings_save('b7700000-0000-4000-8000-000000000001',null,pg_temp.payload())$$,'42501',null,'configuração do ministério exige permissão para todo o ministério');
select pg_temp.as_user(1);
select lives_ok($$select pg_temp.grant('church.settings','["view","edit"]','')$$,'concede Configurações para todo o ministério');
select pg_temp.as_user(2);
select lives_ok($$select public.organization_settings_save('b7700000-0000-4000-8000-000000000001',null,pg_temp.payload())$$,'com permissão do ministério, salva a identidade');
reset role;
select * from finish();
rollback;
