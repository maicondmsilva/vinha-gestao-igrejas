import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('Configurações sem Serviços e segurança; funções movidas para os módulos', async () => {
  assert.doesNotMatch(read('app/OrganizationSettings.tsx'), /servicos|Serviços e segurança/);
  assert.doesNotMatch(read('app/DashboardNavigation.tsx'), /servicos/);
  const {communicationPages} = await import('../shared/dashboard-menu.ts');
  for (const id of ['abertura', 'comunidade', 'jornadas'])
    assert.ok(
      communicationPages.some(([k]) => k === id),
      id,
    );
  assert.match(read('app/CommunicationWorkspace.tsx'), /MinistryMediaAdmin[\s\S]*MemberCommunityAdmin[\s\S]*MemberLearningAdmin/);
  assert.match(read('app/FinanceModule.tsx'), /<MemberServicesAdmin mode="giving"/);
  assert.match(read('app/PeopleDirectory.tsx'), /<MemberServicesAdmin mode="cards"/);
  assert.match(read('app/CellIntegrated.tsx'), /<MemberFamilyAdmin unitId=\{unitId\} cellsOnly\/>/);
  assert.doesNotMatch(read('app/MemberServicesAdmin.tsx'), /Preço do ingresso/, 'ingresso fica no evento');
});

test('CEP automático em igrejas e células; membros já buscavam', () => {
  assert.match(read('app/OrganizationSettings.tsx'), /useCepAutofill\(\{zip:'address\.postal_code'/);
  assert.match(read('app/CellDirectory.tsx'), /<CellAddressHelper/);
  assert.match(read('app/useRegistrationFormatting.ts'), /lookupPostalAddress/);
});

test('células e redes em cartões com capa protegida', () => {
  const sql = read('supabase/migrations/20261117210000_celulas_capas.sql');
  assert.match(sql, /'vinha-cell-covers','vinha-cell-covers',false/);
  assert.match(sql, /cell_manage_allowed\(p_org,p_unit,case when p_kind='cell' then 'cells\.cells' else 'cells\.networks' end\)/);
  const route = read('app/api/cell-covers/route.ts');
  assert.match(route, /boundedBody\(request, 3145728\)/);
  assert.match(route, /imageMime/);
  assert.match(read('app/CellDirectory.tsx'), /<CellCover unit=\{unitId\} kind="cell"/);
  assert.match(read('app/CellNetworks.tsx'), /<CellCover unit=\{unitId\} kind="network"/);
});

test('barra lateral, chat, Portal e igreja inicial', () => {
  const app = read('app/DashboardApp.tsx');
  assert.doesNotMatch(app, /Precisa de ajuda/);
  assert.match(app, /className="side-user"/);
  assert.match(app, /localStorage\.setItem\('vinha\.nav'/);
  assert.match(app, /onMouseEnter=\{\(\)=>navCollapsed&&setNavPeek\(true\)\}/);
  assert.match(app, /className="portal-link"[^>]*target="_blank" rel="noopener"/);
  assert.match(app, /d\.homeUnitId/);
  assert.match(read('app/api/units/route.ts'), /homeUnitId/);
  assert.match(read('app/api/session/route.ts'), /member_photo/);
  assert.match(read('app/SupportChat.tsx'), /<VinhaChatIcon\/>/);
});
