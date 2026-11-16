-- Portal da Vinha: só a Central grava o vídeo de cada módulo; qualquer usuário conectado lê. Tudo é desfeito no fim.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
 ('f9000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','op@portal.example.invalid','',now(),now(),now()),
 ('f9000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','membro@portal.example.invalid','',now(),now(),now());
insert into public.platform_operators(user_id,role,full_name,email) values('f9000000-0000-4000-8000-000000000001','owner','Operador do portal','op@portal.example.invalid');

select set_config('request.jwt.claims',jsonb_build_object('sub','f9000000-0000-4000-8000-000000000001','role','authenticated','aal','aal2')::text,true);
set local role authenticated;
select lives_ok($$select public.save_portal_video('pessoas','https://youtu.be/abcdefghijk')$$,'a Central grava o vídeo do módulo');
select is((select url from public.vinha_portal_videos where module='pessoas'),'https://youtu.be/abcdefghijk','o link fica salvo');
select throws_like($$select public.save_portal_video('pessoas','https://exemplo.com/video')$$,'%YouTube%','aceita só YouTube ou Vimeo');
select lives_ok($$select public.save_portal_video('kids','https://www.youtube.com/watch?v=abcdefghijk')$$,'outro módulo');
select lives_ok($$select public.save_portal_video('kids','')$$,'link vazio retira o vídeo');

select set_config('request.jwt.claims',jsonb_build_object('sub','f9000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1')::text,true);
select is((select count(*)::int from public.vinha_portal_videos),1,'usuário comum vê os vídeos publicados');
select throws_ok($$select public.save_portal_video('pessoas','https://youtu.be/zzzzzzzzzzz')$$,null,'usuário comum não altera');
select * from finish();
rollback;
