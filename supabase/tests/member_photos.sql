begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Fotos de perfil: membro, migração na aprovação e foto da criança pelo responsável.
create function pg_temp.mp(t text) returns uuid language sql immutable as $$select md5('member-photos-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.mp(t),'role','authenticated')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select pg_temp.mp(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'-photo@example.invalid',now(),now(),now() from unnest(array['parent','newbie','stranger'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.mp('org'),'Fotos fictício','member-photos-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.mp('a'),pg_temp.mp('org'),'Igreja A','a','headquarters');
insert into public.people(id,organization_id,unit_id,full_name,status,auth_user_id) values
 (pg_temp.mp('p-parent'),pg_temp.mp('org'),pg_temp.mp('a'),'Mãe Fictícia','active',pg_temp.mp('parent')),
 (pg_temp.mp('p-child'),pg_temp.mp('org'),pg_temp.mp('a'),'Criança Fictícia','active',null),
 (pg_temp.mp('p-new'),pg_temp.mp('org'),pg_temp.mp('a'),'Novo Membro','active',null),
 (pg_temp.mp('p-stranger'),pg_temp.mp('org'),pg_temp.mp('a'),'Outra Pessoa','active',pg_temp.mp('stranger'));
insert into private.kids_profiles(id,organization_id,unit_id,person_id,status,review_status,created_by) values(pg_temp.mp('kid'),pg_temp.mp('org'),pg_temp.mp('a'),pg_temp.mp('p-child'),'active','approved',pg_temp.mp('parent'));
insert into private.kids_guardians(id,organization_id,unit_id,profile_id,person_id,relationship,can_pickup,can_edit,status,approved_by,approved_at,created_by) values(pg_temp.mp('g'),pg_temp.mp('org'),pg_temp.mp('a'),pg_temp.mp('kid'),pg_temp.mp('p-parent'),'Mãe',true,true,'approved',pg_temp.mp('parent'),now(),pg_temp.mp('parent'));
create function pg_temp.upload(path text) returns void language sql as $$insert into storage.objects(bucket_id,name,owner) values('member-photos',path,null)$$;
select ok(not has_function_privilege('anon','public.member_photo(uuid,text,uuid)','execute'),'sem acesso anônimo');
select pg_temp.upload(pg_temp.mp('org')||'/'||pg_temp.mp('parent')||'/profile.jpg');
select pg_temp.upload(pg_temp.mp('org')||'/'||pg_temp.mp('newbie')||'/profile.jpg');
select pg_temp.upload(pg_temp.mp('org')||'/'||pg_temp.mp('parent')||'/kids/'||pg_temp.mp('kid')||'.jpg');
select pg_temp.upload(pg_temp.mp('org')||'/'||pg_temp.mp('stranger')||'/kids/'||pg_temp.mp('kid')||'.jpg');
select pg_temp.actor('parent');set local role authenticated;
select is(public.member_photo(pg_temp.mp('org'),'set')->>'path','member-photos/'||pg_temp.mp('org')||'/'||pg_temp.mp('parent')||'/profile.jpg','foto do membro gravada');
select is(public.member_photo(pg_temp.mp('org'),'get')->>'path','member-photos/'||pg_temp.mp('org')||'/'||pg_temp.mp('parent')||'/profile.jpg','foto lida de volta');
select is(public.member_photo(pg_temp.mp('org'),'child_set',pg_temp.mp('kid'))->>'ok','true','responsável grava a foto da criança');
reset role;
select is((select photo_path from public.people where id=pg_temp.mp('p-child')),'member-photos/'||pg_temp.mp('org')||'/'||pg_temp.mp('parent')||'/kids/'||pg_temp.mp('kid')||'.jpg','foto vai para o cadastro da criança');
select pg_temp.actor('stranger');set local role authenticated;
select throws_ok($$select public.member_photo(pg_temp.mp('org'),'child_set',pg_temp.mp('kid'))$$,'42501',null,'quem não é responsável não troca a foto da criança');
select throws_ok($$select public.member_photo(pg_temp.mp('org'),'set')$$,'22023',null,'sem arquivo enviado não grava');
reset role;select pg_temp.actor('newbie');set local role authenticated;
select is(public.member_photo(pg_temp.mp('org'),'set')->>'ok','true','conta ainda sem cadastro guarda a foto');
reset role;
update public.people set auth_user_id=pg_temp.mp('newbie') where id=pg_temp.mp('p-new');
select is((select photo_path from public.people where id=pg_temp.mp('p-new')),'member-photos/'||pg_temp.mp('org')||'/'||pg_temp.mp('newbie')||'/profile.jpg','ao vincular, a foto migra para o cadastro de membros');
select * from finish();
rollback;
