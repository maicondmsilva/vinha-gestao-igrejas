begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- App do membro · imagens: feed com tipo e capa da Comunicação, janela de exibição, banner do evento na agenda e no ticket.
create function pg_temp.ai(t text) returns uuid language sql immutable as $$select md5('app-images-'||t)::uuid$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.ai(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-ai@example.invalid',now(),now(),now() from unnest(array['owner','member'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.ai('org'),'Imagens fictício','app-images-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.ai('unit'),pg_temp.ai('org'),'Sede','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status) values
 (pg_temp.ai('owner-m'),pg_temp.ai('org'),pg_temp.ai('owner'),pg_temp.ai('unit'),'owner','active'),
 (pg_temp.ai('member-m'),pg_temp.ai('org'),pg_temp.ai('member'),pg_temp.ai('unit'),'member','active');
insert into private.publishing_items(id,organization_id,owner_unit,kind,title,body,source,poster,scope,targets,status,created_by,starts_at,ends_at) values
 (pg_temp.ai('notice'),pg_temp.ai('org'),pg_temp.ai('unit'),'notice','Aviso com imagem','Texto','','/api/publishing-images/'||pg_temp.ai('img1'),'local',array[pg_temp.ai('unit')],'published',pg_temp.ai('owner'),null,null),
 (pg_temp.ai('banner'),pg_temp.ai('org'),pg_temp.ai('unit'),'banner','Banner do retiro','','https://exemplo.invalid/retiro','/api/publishing-images/'||pg_temp.ai('img2'),'local',array[pg_temp.ai('unit')],'published',pg_temp.ai('owner'),null,null),
 (pg_temp.ai('expired'),pg_temp.ai('org'),pg_temp.ai('unit'),'banner','Banner vencido','','','','local',array[pg_temp.ai('unit')],'published',pg_temp.ai('owner'),now()-interval '10 days',now()-interval '1 day'),
 (pg_temp.ai('future'),pg_temp.ai('org'),pg_temp.ai('unit'),'notice','Aviso futuro','Texto','','','local',array[pg_temp.ai('unit')],'published',pg_temp.ai('owner'),now()+interval '2 days',null);
insert into private.member_publications(organization_id,unit_id,kind,title,body,url,published) values(pg_temp.ai('org'),pg_temp.ai('unit'),'notice','Aviso antigo','Sem capa','',true);
insert into private.church_app_events(id,organization_id,unit_id,title,kind,starts_at,ends_at,capacity,status,cover_url) values
 (pg_temp.ai('event'),pg_temp.ai('org'),pg_temp.ai('unit'),'Retiro','event',now()+interval '2 days',now()+interval '3 days',50,'published','/api/event-images/'||pg_temp.ai('cover'));
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,status) values(pg_temp.ai('person'),pg_temp.ai('org'),pg_temp.ai('unit'),pg_temp.ai('member'),'Membro fictício','active');
insert into private.church_app_registrations(id,organization_id,unit_id,event_id,user_id,person_id,name,status)
 values(pg_temp.ai('reg'),pg_temp.ai('org'),pg_temp.ai('unit'),pg_temp.ai('event'),pg_temp.ai('member'),pg_temp.ai('person'),'Membro fictício','confirmed');

create function pg_temp.feed() returns jsonb language sql as $$select public.member_public_feed(pg_temp.ai('org'),pg_temp.ai('unit'))->'items'$$;
create function pg_temp.item(t text) returns jsonb language sql as $$select i from jsonb_array_elements(pg_temp.feed()) i where i->>'title'=t$$;
set local role anon;
select is(pg_temp.item('Aviso com imagem')->>'image','/api/publishing-images/'||pg_temp.ai('img1'),'aviso traz a capa');
select is(pg_temp.item('Aviso com imagem')->>'kind','notice','aviso continua aviso');
select is(pg_temp.item('Banner do retiro')->>'kind','banner','banner mantém o tipo');
select is(pg_temp.item('Banner do retiro')->>'url','https://exemplo.invalid/retiro','banner leva ao destino');
select ok(pg_temp.item('Banner vencido') is null,'banner vencido some');
select ok(pg_temp.item('Aviso futuro') is null,'aviso agendado ainda não aparece');
select is(pg_temp.item('Aviso antigo')->>'image','','publicação antiga sem capa continua aparecendo');
select is(public.member_agenda(pg_temp.ai('org'),pg_temp.ai('unit'))#>>'{items,0,cover}','/api/event-images/'||pg_temp.ai('cover'),'agenda traz o banner do evento');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ai('member'),'role','authenticated','email','member-ai@example.invalid')::text,true);
set local role authenticated;
select is(public.member_agenda_self(pg_temp.ai('org'),'tickets',null,null,'{}')#>>'{items,0,cover}','/api/event-images/'||pg_temp.ai('cover'),'ticket traz o banner do evento');
select * from finish();
rollback;
