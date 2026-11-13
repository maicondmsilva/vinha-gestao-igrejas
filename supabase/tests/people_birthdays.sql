begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Pessoas · aniversariantes do dia, da semana e do mês (nascimento e casamento), respeitando quem pode ver cada pessoa.
create function pg_temp.pb(t text) returns uuid language sql immutable as $$select md5('people-birthdays-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pb(t),'role','authenticated')::text,true)$$;
create function pg_temp.bd(r text, u text default 'unit') returns jsonb language sql as $$select public.people_birthdays(pg_temp.pb('org'),pg_temp.pb(u),r)$$;
create function pg_temp.names(r text, u text default 'unit') returns text language sql as $$select coalesce(string_agg(i->>'name'||':'||(i->>'kind'),',' order by i->>'date',i->>'name'),'') from jsonb_array_elements(pg_temp.bd(r,u)->'items') i$$;
create function pg_temp.today() returns date language sql stable as $$select (now() at time zone 'America/Sao_Paulo')::date$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.pb(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'-bday@example.invalid',now(),now(),now() from unnest(array['owner','sec','outsider']) x;
insert into public.organizations(id,name,slug,status) values(pg_temp.pb('org'),'Aniversários fictício','people-birthdays-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 (pg_temp.pb('unit'),pg_temp.pb('org'),'Sede','sede','headquarters'),(pg_temp.pb('unit2'),pg_temp.pb('org'),'Bairro','bairro','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.pb('owner-m'),pg_temp.pb('org'),pg_temp.pb('owner'),'owner','active',pg_temp.pb('unit')),
 (pg_temp.pb('sec-m'),pg_temp.pb('org'),pg_temp.pb('sec'),'secretary','active',pg_temp.pb('unit')),
 (pg_temp.pb('out-m'),pg_temp.pb('org'),pg_temp.pb('outsider'),'member','active',pg_temp.pb('unit'));
insert into public.membership_unit_access(membership_id,organization_id,unit_id,access_level,include_children)
 values(pg_temp.pb('sec-m'),pg_temp.pb('org'),pg_temp.pb('unit'),'manage',false);
-- Hoje faz 30 anos; daqui a 3 dias faz 41; daqui a 20 dias; ontem; reprovada hoje; outra igreja hoje; casamento hoje (10 anos).
insert into public.people(id,organization_id,unit_id,full_name,birth_date,phone,journey_status,status,marriage_date) values
 (pg_temp.pb('hoje'),pg_temp.pb('org'),pg_temp.pb('unit'),'Ana Hoje',(pg_temp.today()-interval '30 years')::date,'(11) 98888-7777','Membro','active',null),
 (pg_temp.pb('semana'),pg_temp.pb('org'),pg_temp.pb('unit'),'Bruno Semana',(pg_temp.today()+3-interval '41 years')::date,null,'Visitante','active',null),
 (pg_temp.pb('longe'),pg_temp.pb('org'),pg_temp.pb('unit'),'Caio Longe',(pg_temp.today()+20-interval '25 years')::date,null,'Membro','active',null),
 (pg_temp.pb('ontem'),pg_temp.pb('org'),pg_temp.pb('unit'),'Duda Ontem',(pg_temp.today()-1-interval '20 years')::date,null,'Membro','active',null),
 (pg_temp.pb('reprovada'),pg_temp.pb('org'),pg_temp.pb('unit'),'Eva Reprovada',(pg_temp.today()-interval '22 years')::date,null,'Visitante','rejected',null),
 (pg_temp.pb('outra'),pg_temp.pb('org'),pg_temp.pb('unit2'),'Fábio Outra',(pg_temp.today()-interval '33 years')::date,null,'Membro','active',null),
 (pg_temp.pb('casal'),pg_temp.pb('org'),pg_temp.pb('unit'),'Gil Casado',null,null,'Membro','active',(pg_temp.today()-interval '10 years')::date);

set local role authenticated;
select pg_temp.actor('owner');
select is(pg_temp.names('today'),'Ana Hoje:birthday,Gil Casado:wedding','hoje: aniversário e casamento');
select is((pg_temp.bd('today')#>>'{items,0,years}')::int,30,'idade que completa');
select is(pg_temp.bd('today')#>>'{items,0,phone}','(11) 98888-7777','traz o celular para mandar mensagem');
select is((select (i->>'years')::int from jsonb_array_elements(pg_temp.bd('today')->'items') i where i->>'kind'='wedding'),10,'anos de casamento');
select ok(pg_temp.names('week') like '%Bruno Semana:birthday%' and pg_temp.names('week') not like '%Caio Longe%','semana: próximos 7 dias');
select ok(pg_temp.names('week') not like '%Duda Ontem%','quem fez ontem não entra na semana');
select ok(pg_temp.names('today') not like '%Eva%','pessoa reprovada não aparece');
select ok(pg_temp.names('today') not like '%Fábio%','só a igreja selecionada');
select is(pg_temp.names('today','unit2'),'Fábio Outra:birthday','outra igreja mostra os dela');
select is((pg_temp.bd('today')->>'counts')::jsonb->>'today','2','contadores de hoje');
select throws_ok($$select pg_temp.bd('year')$$,'22023',null,'período inválido recusado');
select pg_temp.actor('sec');
select is(pg_temp.names('today'),'Ana Hoje:birthday,Gil Casado:wedding','secretaria vê a igreja que tem acesso');
select throws_ok($$select pg_temp.bd('today','unit2')$$,'42501',null,'sem acesso à outra igreja');
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.bd('today')$$,'42501',null,'membro comum não vê aniversariantes');
select * from finish();
rollback;
