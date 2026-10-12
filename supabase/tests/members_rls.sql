begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('a0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin-a@example.test', '', now(), now(), now()),
  ('a0000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'leader-a@example.test', '', now(), now(), now()),
  ('a0000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member-b@example.test', '', now(), now(), now());

insert into public.organizations (id, name, slug, status)
values
  ('b0000000-0000-4000-8000-000000000001', 'Organização Teste A', 'organizacao-teste-a', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'Organização Teste B', 'organizacao-teste-b', 'active');

insert into public.organization_units (id, organization_id, name, slug, unit_type)
values
  ('c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'Sede A', 'sede-a', 'headquarters'),
  ('c0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'Campus A', 'campus-a', 'campus'),
  ('c0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 'Sede B', 'sede-b', 'headquarters');

insert into public.organization_memberships (id, organization_id, user_id, default_unit_id, role, status)
values
  ('d0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('d0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000002', 'leader', 'active'),
  ('d0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000003', 'member', 'active');

insert into public.membership_unit_access (membership_id, unit_id, access_level)
values ('d0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000002', 'read');

insert into public.people (id, organization_id, unit_id, auth_user_id, full_name, email)
values
  ('e0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', null, 'Pessoa Sede A', 'sede-a@example.test'),
  ('e0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000002', null, 'Pessoa Campus A', 'campus-a@example.test'),
  ('e0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Pessoa Sede B', 'sede-b@example.test');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(
  (select count(*) from public.people),
  2::bigint,
  'administrador visualiza somente os membros da própria organização'
);

select throws_ok(
  $$insert into public.people (organization_id, unit_id, full_name) values ('b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'Inserção indevida')$$,
  '42501',
  'new row violates row-level security policy for table "people"',
  'administrador não insere membro em outra organização'
);

select set_config('request.jwt.claims', '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(*) from public.people),
  1::bigint,
  'líder visualiza somente a unidade concedida'
);

select set_config('request.jwt.claims', '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from public.people),
  1::bigint,
  'membro visualiza o próprio cadastro vinculado'
);

select * from finish();
rollback;
