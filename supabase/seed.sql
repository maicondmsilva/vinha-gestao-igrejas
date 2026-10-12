-- Dados exclusivamente fictícios para desenvolvimento e testes locais.
-- Não incluir dados reais de igrejas, membros, crianças, pagamentos ou consentimentos.

insert into public.organizations (
  id,
  name,
  slug,
  legal_name,
  tax_id,
  status,
  primary_color
)
values (
  '10000000-0000-4000-8000-000000000001',
  'Ministério Vinha Demonstração',
  'vinha-demonstracao',
  'Organização Religiosa Demonstração',
  null,
  'trial',
  '#166534'
)
on conflict (id) do nothing;
insert into public.organization_units (
  id,
  organization_id,
  parent_unit_id,
  name,
  slug,
  unit_type,
  status,
  address
)
values
  (
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    null,
    'Igreja Sede Demonstração',
    'sede-demonstracao',
    'headquarters',
    'active',
    '{"city":"Cidade Demonstração","state":"SP","country":"BR"}'::jsonb
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'Campus Norte Demonstração',
    'campus-norte-demonstracao',
    'campus',
    'active',
    '{"city":"Cidade Demonstração","state":"SP","country":"BR"}'::jsonb
  ),
  (
    '20000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'Congregação Sul Demonstração',
    'congregacao-sul-demonstracao',
    'congregation',
    'active',
    '{"city":"Cidade Demonstração","state":"SP","country":"BR"}'::jsonb
  )
on conflict (id) do nothing;

insert into public.people (
  id,
  organization_id,
  unit_id,
  full_name,
  birth_date,
  email,
  phone,
  journey_status,
  joined_at,
  baptized,
  tags,
  status
)
values
  (
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'Ana Demonstração',
    '1990-05-12',
    'ana.demonstracao@example.test',
    '+55 11 90000-0001',
    'Membro',
    now() - interval '3 years',
    true,
    array['voluntária', 'recepção'],
    'active'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'Bruno Demonstração',
    '1995-09-21',
    'bruno.demonstracao@example.test',
    '+55 11 90000-0002',
    'Em integração',
    now() - interval '2 months',
    false,
    array['louvor'],
    'active'
  )
on conflict (id) do nothing;

insert into public.person_addresses (
  id,
  organization_id,
  person_id,
  postal_code,
  street,
  number,
  district,
  city,
  state
)
values
  (
    '40000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '00000-001',
    'Rua Demonstração',
    '100',
    'Centro',
    'Cidade Demonstração',
    'SP'
  )
on conflict (id) do nothing;

insert into public.emergency_contacts (
  id,
  organization_id,
  person_id,
  name,
  relationship,
  phone
)
values (
  '50000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  'Contato Demonstração',
  'Familiar',
  '+55 11 90000-0099'
)
on conflict (id) do nothing;
