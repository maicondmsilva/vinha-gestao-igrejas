-- Kids › Hoje: a sessão padrão é a que importa agora (dados sintéticos, desfeitos no fim).
-- Uma sessão vazia criada depois não pode esconder a sessão preparada em Configurar.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.kh(t text) returns uuid language sql immutable as $$select md5('kids-hoje-test-'||t)::uuid$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values(pg_temp.kh('owner'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','kh-owner@example.invalid',now(),now(),now());
insert into public.organizations(id,name,slug,status) values(pg_temp.kh('org'),'Kids Hoje fictício','kids-hoje-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.kh('unit'),pg_temp.kh('org'),'Sede Hoje','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id)
values(pg_temp.kh('m'),pg_temp.kh('org'),pg_temp.kh('owner'),'owner','active',pg_temp.kh('unit'));
insert into private.kids_rooms(id,organization_id,unit_id,name,location,capacity) values(pg_temp.kh('room'),pg_temp.kh('org'),pg_temp.kh('unit'),'Sala 1','',20);
insert into private.kids_classes(id,organization_id,unit_id,name,min_months,max_months) values(pg_temp.kh('class'),pg_temp.kh('org'),pg_temp.kh('unit'),'Cordeirinhos',0,71);
-- Sessão preparada em Configurar (com sala), começa em 2h.
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,status,created_by)
values(pg_temp.kh('ready'),pg_temp.kh('org'),pg_temp.kh('unit'),'Culto da noite',now()+interval '2 hours',now()+interval '4 hours','draft',pg_temp.kh('owner'));
insert into private.kids_session_rooms(id,organization_id,unit_id,session_id,room_id,class_id,capacity,min_staff)
values(pg_temp.kh('sr'),pg_temp.kh('org'),pg_temp.kh('unit'),pg_temp.kh('ready'),pg_temp.kh('room'),pg_temp.kh('class'),20,1);
-- Sessão vazia criada depois, com início mais tarde (antes escondia a preparada).
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,status,created_by)
values(pg_temp.kh('empty'),pg_temp.kh('org'),pg_temp.kh('unit'),'Sessão vazia',now()+interval '3 hours',now()+interval '4 hours','draft',pg_temp.kh('owner'));
-- Sessão antiga já encerrada.
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,status,created_by)
values(pg_temp.kh('old'),pg_temp.kh('org'),pg_temp.kh('unit'),'Domingo passado',now()-interval '7 days',now()-interval '7 days'+interval '2 hours','closed',pg_temp.kh('owner'));

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.kh('owner'),'role','authenticated')::text,true);
create function pg_temp.page() returns jsonb language sql as $$select public.kids_operations_page(pg_temp.kh('org'),pg_temp.kh('unit'),null,null,'','all')$$;
select is(pg_temp.page()->>'sessionId',pg_temp.kh('ready')::text,'Hoje mostra a sessão preparada com salas, não a vazia criada depois');
select is(jsonb_array_length(pg_temp.page()->'groups'),1,'salas da sessão aparecem em Hoje (presentes e vagas)');
select is((pg_temp.page()->'groups'->0->>'capacity')::int,20,'vagas da sala vêm da sessão');
select is((select x->>'autoOpen' from jsonb_array_elements(pg_temp.page()->'sessions') x where x->>'id'=pg_temp.kh('ready')::text),'false','sessão avulsa informa que não abre sozinha');
reset role;
update private.kids_sessions set status='open' where id=pg_temp.kh('empty');
set local role authenticated;
select is(pg_temp.page()->>'sessionId',pg_temp.kh('empty')::text,'sessão aberta tem prioridade');
reset role;
update private.kids_sessions set status='cancelled' where id in(pg_temp.kh('empty'),pg_temp.kh('ready'));
set local role authenticated;
select is(pg_temp.page()->>'sessionId',pg_temp.kh('ready')::text,'sem sessão ativa, mostra a mais próxima não terminada');
select * from finish();
rollback;
