begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Escalas · calendário: cada culto da lista traz as equipes escaladas (para as cores por equipe).
create function pg_temp.ct(t text) returns uuid language sql immutable as $$select md5('scale-cal-teams-'||t)::uuid$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values(pg_temp.ct('owner'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-cal@example.invalid',now(),now(),now());
insert into public.organizations(id,name,slug,status) values(pg_temp.ct('org'),'Calendário fictício','scale-cal-teams','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ct('unit'),pg_temp.ct('org'),'Sede','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(pg_temp.ct('org'),pg_temp.ct('owner'),'owner','active',pg_temp.ct('unit'));
insert into private.scale_teams(id,organization_id,unit_id,name) values(pg_temp.ct('t1'),pg_temp.ct('org'),pg_temp.ct('unit'),'Recepção'),(pg_temp.ct('t2'),pg_temp.ct('org'),pg_temp.ct('unit'),'Louvor');
insert into private.scale_roles(id,organization_id,unit_id,team_id,name) values(pg_temp.ct('r1'),pg_temp.ct('org'),pg_temp.ct('unit'),pg_temp.ct('t1'),'Porta'),(pg_temp.ct('r2'),pg_temp.ct('org'),pg_temp.ct('unit'),pg_temp.ct('t2'),'Vocal');
insert into private.scale_services(id,organization_id,unit_id,series_id,title,arrival_at,starts_at,ends_at,timezone,created_by)
values(pg_temp.ct('s1'),pg_temp.ct('org'),pg_temp.ct('unit'),pg_temp.ct('s1'),'Culto com duas equipes',date_trunc('day',now())+interval '3 days 21 hours',date_trunc('day',now())+interval '3 days 22 hours',date_trunc('day',now())+interval '3 days 23 hours','America/Sao_Paulo',pg_temp.ct('owner'));
insert into private.scale_positions(service_id,organization_id,unit_id,team_id,role_id,ordinal) values
 (pg_temp.ct('s1'),pg_temp.ct('org'),pg_temp.ct('unit'),pg_temp.ct('t1'),pg_temp.ct('r1'),1),(pg_temp.ct('s1'),pg_temp.ct('org'),pg_temp.ct('unit'),pg_temp.ct('t2'),pg_temp.ct('r2'),1);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ct('owner'),'role','authenticated','email','owner-cal@example.invalid')::text,true);
select is((public.scale_planning(pg_temp.ct('org'),pg_temp.ct('unit'),'list',jsonb_build_object('from',current_date::text,'to',(current_date+10)::text,'status','all','search','','page',1))#>'{items,0,teams}'),
 jsonb_build_array(jsonb_build_object('id',pg_temp.ct('t2'),'name','Louvor'),jsonb_build_object('id',pg_temp.ct('t1'),'name','Recepção')),'culto traz as equipes em ordem de nome');
select * from finish();
rollback;
