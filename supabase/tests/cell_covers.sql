begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('a8000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','net-owner@example.test',now(),now(),now()),
('a8000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','net-reader@example.test',now(),now(),now());
insert into public.organizations(id,name,slug,status) values('b8000000-0000-4000-8000-000000000001','Redes fictícias A','network-test-a','active'),('b8000000-0000-4000-8000-000000000002','Redes fictícias B','network-test-b','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
('c8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','Sede fictícia A','sede','headquarters'),
('c8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','Campus fictício A','campus','campus'),
('c8000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000002','Sede fictícia B','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
('e8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','owner','active','c8000000-0000-4000-8000-000000000001'),
('e8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000002','secretary','active','c8000000-0000-4000-8000-000000000001');
insert into public.membership_unit_access(membership_id,unit_id,access_level) values('e8000000-0000-4000-8000-000000000002','c8000000-0000-4000-8000-000000000001','read');
insert into public.people(id,organization_id,unit_id,full_name,status) values
('d8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','Supervisor fictício canônico','active'),
('d8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000002','Supervisor de outro campus','active');
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by) values
('f8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001','Grupo fictício A',1,'19:00','presential','a8000000-0000-4000-8000-000000000001');
create function pg_temp.nsave(kind text,id uuid,v integer,d jsonb) returns jsonb language sql as $$select public.cell_networks_save('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001',kind,id,v,d)$$;
create function pg_temp.cover(kind text,id uuid,action text,d jsonb default '{}') returns jsonb language sql as $$select public.cell_cover('b8000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000001',kind,id,action,d)$$;
select ok(not has_function_privilege('anon','public.cell_cover(uuid,uuid,text,uuid,text,jsonb)','EXECUTE'),'capa não anônima');
select ok(not has_table_privilege('authenticated','private.cell_covers','SELECT'),'capas sem leitura direta');
select ok((select not public from storage.buckets where id='vinha-cell-covers'),'bucket de capas privado');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('test.path',pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','prepare','{"ext":"jpg"}')->>'path',true);
select ok(current_setting('test.path') like 'b8000000-0000-4000-8000-000000000001/c8000000-0000-4000-8000-000000000001/cell/f8000000-0000-4000-8000-000000000001/%.jpg','caminho dentro da igreja e da célula');
select is(pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','list')->'covers','{}'::jsonb,'capa pendente não aparece');
select throws_ok($$select pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','finish','{"path":"outro/caminho/qualquer.jpg"}')$$,'22023',null,'conclusão só com o caminho preparado');
select is(pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','finish',jsonb_build_object('path',current_setting('test.path')))->>'version','1','capa salva');
select is(pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','list')->'covers'->>'cell:f8000000-0000-4000-8000-000000000001','1','lista mostra a versão da capa');
select throws_ok($$select pg_temp.cover('cell','f8000000-0000-4000-8000-000000000099','prepare','{"ext":"jpg"}')$$,'P0002',null,'célula de outra igreja ou inexistente');
select throws_ok($$select pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','prepare','{"ext":"svg"}')$$,'22023',null,'só JPEG, PNG ou WebP');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is(pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','read')->>'version','1','secretaria com leitura vê a capa');
select throws_ok($$select pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','remove')$$,'42501',null,'sem permissão de edição não remove');
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is(pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','remove')->>'old',current_setting('test.path'),'remover devolve o arquivo para apagar');
select is(pg_temp.cover('cell','f8000000-0000-4000-8000-000000000001','list')->'covers','{}'::jsonb,'capa removida');
select * from finish();
rollback;
