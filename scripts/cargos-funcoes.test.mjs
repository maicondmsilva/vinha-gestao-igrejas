// Grupos, Cargos e Funções: contrato do painel, do app e do banco.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {rolesActions, rolesError, sinceLabel, groupKindLabel} from '../shared/church-roles.ts';
import {portalModules} from '../shared/portal-content.ts';
import {memberFormPayload} from '../app/lib/member-write.ts';
import {peopleFilters} from '../app/lib/people-tools.ts';

const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const sql = read('supabase/migrations/20261117090000_cargos_funcoes.sql');

test('ações do painel batem com o banco', () => {
  for (const a of rolesActions) assert.ok(sql.includes("'" + a + "'"), 'ação sem tratamento no banco: ' + a);
  assert.match(read('app/api/church-roles/route.ts'), /rolesActions\.includes/);
});

test('mensagens de erro claras', () => {
  assert.match(rolesError('42501', 'roles_denied').message, /permissão/);
  assert.match(rolesError('22023', 'roles_no_user').message, /usuário/);
  assert.equal(rolesError('40001', '').status, 409);
  assert.equal(sinceLabel('2015-03-01'), 'desde 2015');
  assert.equal(sinceLabel(null), '');
  assert.equal(groupKindLabel.network, 'Rede');
});

test('acesso pela função só com confirmação', () => {
  assert.match(sql, /access_proposals/);
  assert.match(sql, /'access\.approve'[\s\S]*has_organization_role\(p_org,array\['owner','admin'\]/);
  assert.doesNotMatch(sql.split('create or replace function private.assignment_after')[1].split('$$;')[0], /insert into private\.permission_grants/);
});

test('cadastro não grava mais o texto livre de grupo', () => {
  const p = memberFormPayload({name: 'Ana Souza', group: 'Louvor'}, null, []);
  assert.equal('group' in p, false);
  assert.doesNotMatch(read('app/pessoas/PersonForms.tsx'), /Grupo \/ ministério \(texto livre\)/);
  assert.match(read('app/pessoas/PersonForms.tsx'), /<PersonRoles/);
});

test('filtros por cargo, ministério e liderança', () => {
  const f = peopleFilters(new URLSearchParams({position: '11111111-1111-4111-8111-111111111111', leaders: '1'}));
  assert.equal(f.position, '11111111-1111-4111-8111-111111111111');
  assert.equal(f.leaders, true);
  assert.throws(() => peopleFilters(new URLSearchParams({ministry: 'x'})));
});

test('nome do conceito personalizável', () => {
  assert.match(read('app/lib/ministry-language.ts'), /'pessoas\.cargo':'Cargo'/);
  assert.match(sql, /'pessoas\.cargo'',''pessoas\.cargos''/);
});

test('app: liderança com telefone só autorizado e mensagens', () => {
  const app = read('android-app/src/LeadershipScreens.tsx');
  assert.match(app, /member_roles/);
  assert.match(app, /Mostrar meu telefone/);
  assert.match(read('android-app/src/MemberExperience.tsx'), /'leadership'/);
  assert.match(read('android-app/src/ServicesScreen.tsx'), /roleLine/);
  assert.match(sql, /false\) then coalesce\(p\.phone,''\) else '' end/);
});

test('Configurações e Portal', () => {
  assert.match(read('app/OrganizationSettings.tsx'), /RolesSettings/);
  assert.ok(portalModules.find((m) => m.id === 'pessoas').sections.some((x) => x.id === 'cargos'));
});
