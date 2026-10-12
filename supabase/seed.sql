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
