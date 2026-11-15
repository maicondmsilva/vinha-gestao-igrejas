begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.pc(t text) returns uuid language sql immutable as $$select md5('push-cover-test-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pc(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
 select pg_temp.pc(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-pcov@example.invalid',now(),now(),now()
 from unnest(array['admin','young','adult','cellmate','deceased','plain'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.pc('org'),'Ministério fictício push','push-cover-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.pc('a'),pg_temp.pc('org'),'Sede fictícia','a','headquarters'),(pg_temp.pc('b'),pg_temp.pc('org'),'Filial fictícia','b','campus');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status)
 select pg_temp.pc(t||'-m'),pg_temp.pc('org'),pg_temp.pc(t),pg_temp.pc('a'),case when t='admin' then 'admin'::public.membership_role else 'member'::public.membership_role end,'active'
 from unnest(array['admin','young','adult','cellmate','deceased','plain'])t;
insert into public.people(id,organization_id,unit_id,auth_user_id,full_name,status,birth_date) values
 (pg_temp.pc('young-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('young'),'Jovem fictício','active',current_date-interval '16 years'),
 (pg_temp.pc('adult-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('adult'),'Adulto fictício','active',current_date-interval '40 years'),
 (pg_temp.pc('cellmate-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('cellmate'),'Celular fictício','active',current_date-interval '30 years'),
 (pg_temp.pc('deceased-p'),pg_temp.pc('org'),pg_temp.pc('a'),pg_temp.pc('deceased'),'Falecido fictício','deceased',current_date-interval '70 years');
insert into private.member_push_apps values(pg_temp.pc('org'),pg_temp.pc('project'),'com.vinha.pushtest',true,now());
insert into auth.sessions(id,user_id) select pg_temp.pc(t||'-s'),pg_temp.pc(t) from unnest(array['young','adult','cellmate','deceased','plain'])t;
-- Devices are registered from the member's own session (member_push_session_guard reads session_id from the JWT).
create function pg_temp.device(t text) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pc(t),'role','authenticated','session_id',pg_temp.pc(t||'-s'))::text,true);
 insert into private.member_push_devices(id,organization_id,user_id,unit_id,token,enabled)
  values(pg_temp.pc(t||'-d'),pg_temp.pc('org'),pg_temp.pc(t),pg_temp.pc('a'),'ExpoPushToken['||t||'abcdefghijk]',true);
end $$;
select pg_temp.device(t) from unnest(array['young','adult','cellmate','deceased','plain'])t;

create function pg_temp.adm(a text,d jsonb default '{}',id uuid default null,v int default null) returns jsonb language sql as $$select public.push_admin(md5('push-cover-test-org')::uuid,md5('push-cover-test-a')::uuid,a,id,v,d)$$;
create function pg_temp.body(extra jsonb default '{}') returns jsonb language sql as $$select jsonb_build_object('title','Culto de domingo','body','Hoje às 19h, traga sua família!','targets',jsonb_build_array(md5('push-cover-test-a')::uuid),'link',jsonb_build_object('screen','agenda'),'audience','{}'::jsonb)||extra$$;
insert into private.publishing_images(id,organization_id,unit_id,path,mime,bytes,name,ready) values
 (pg_temp.pc('img'),pg_temp.pc('org'),pg_temp.pc('a'),'org/img-cover.jpg','image/jpeg',1000,'Capa',true),
 (pg_temp.pc('raw'),pg_temp.pc('org'),pg_temp.pc('a'),'org/img-raw.jpg','image/jpeg',1000,'Rascunho',false);
set local role authenticated;
select pg_temp.actor('admin');
select is(pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','draft','request',pg_temp.pc('r1'),'link',jsonb_build_object('screen','agenda','image',pg_temp.pc('img')))))->'campaign'->'link'->>'image',pg_temp.pc('img')::text,'campanha com imagem de capa');
select throws_ok($$select pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','draft','request',pg_temp.pc('r2'),'link',jsonb_build_object('screen','agenda','image',pg_temp.pc('raw')))))$$,'22023','invalid_push_image','imagem não pronta é recusada');
select throws_ok($$select pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','draft','request',pg_temp.pc('r3'),'link',jsonb_build_object('screen','agenda','image','x'))))$$,'22023',null,'imagem inválida é recusada');
reset role;
select is(private.publishing_image_file(pg_temp.pc('img'))->>'public','false','rascunho ainda não deixa a capa pública');
set local role authenticated;
select pg_temp.actor('admin');
select is(pg_temp.adm('create',pg_temp.body(jsonb_build_object('mode','schedule','sendAt',now()+interval '2 days','request',pg_temp.pc('r4'),'link',jsonb_build_object('screen','agenda','image',pg_temp.pc('img')))))->'campaign'->>'status','scheduled','agenda push com capa');
reset role;
select is(private.publishing_image_file(pg_temp.pc('img'))->>'public','true','capa de campanha agendada fica pública');
set local role authenticated;
select pg_temp.actor('admin');
select is(public.push_segments(pg_temp.pc('org'),pg_temp.pc('a'),'save','{"name":"Pastores","audience":{"roles":["pastor"]}}')->>'ok','true','salva público Pastores');
select is(public.push_segments(pg_temp.pc('org'),pg_temp.pc('a'),'save','{"name":"pastores","audience":{"roles":["pastor","admin"]}}')->>'ok','true','mesmo nome atualiza');
select is(jsonb_array_length(public.push_segments(pg_temp.pc('org'),pg_temp.pc('a'),'list')->'items'),1,'um público salvo');
select is(public.push_segments(pg_temp.pc('org'),pg_temp.pc('a'),'list')->'items'->0->'audience'->'roles','["pastor","admin"]'::jsonb,'filtro atualizado');
select throws_ok($$select public.push_segments(pg_temp.pc('org'),pg_temp.pc('a'),'save','{"name":"Hack","audience":{"sql":"x"}}')$$,'22023','invalid_push_segment','filtro desconhecido recusado');
select pg_temp.actor('plain');
select throws_ok($$select public.push_segments(pg_temp.pc('org'),pg_temp.pc('a'),'list')$$,'42501','push_denied','membro comum não vê públicos');
select * from finish();
rollback;
