import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {permissionCommand, roleForType, userType, userTypeName, userTypes} from '../app/lib/permissions.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const m = 'ab900000-0000-4000-8000-000000000001',
  t = 'ab900000-0000-4000-8000-000000000002',
  u = 'ab900000-0000-4000-8000-000000000003';

test('quatro tipos de usuário e Equipe automática', () => {
  assert.deepEqual(
    userTypes.map(([k]) => k),
    ['admin', 'pastor', 'team', 'member'],
  );
  assert.equal(userType('member', true), 'team');
  assert.equal(userType('member', false), 'member');
  assert.equal(userType('secretary', false), 'team', 'papéis antigos aparecem como Equipe');
  assert.equal(userTypeName('owner', false), 'Dono do ministério');
  assert.equal(roleForType('team', 'leader'), 'leader', 'Equipe mantém o papel antigo');
  assert.equal(roleForType('team', 'member'), 'member');
  assert.equal(roleForType('pastor', 'member'), 'pastor');
});

test('modelos personalizados: comandos validados', () => {
  const ok = permissionCommand({
    action: 'save_custom_template',
    data: {name: ' Recepção ', description: '', items: {'people.visitors': ['view', 'create', 'view']}},
  });
  assert.equal(ok.data.name, 'Recepção');
  assert.deepEqual(ok.data.items['people.visitors'], ['view', 'create']);
  assert.throws(() => permissionCommand({action: 'save_custom_template', data: {name: 'X', items: {}}}));
  assert.throws(() => permissionCommand({action: 'save_custom_template', data: {name: 'Mídia', items: {'people.visitors': ['voar']}}}));
  assert.deepEqual(permissionCommand({action: 'apply_custom_template', data: {membership: m, template: t, units: [u, u]}}).data.units, [u]);
});

test('tela: várias igrejas por seção, selecionar todos e salvar tolerante', () => {
  const ui = read('app/UserPermissions.tsx');
  assert.match(ui, /Selecionar todas as seções e ações/);
  assert.match(ui, /Selecionar todos/);
  assert.match(ui, /Salvar seleção como modelo/);
  assert.match(ui, /<UnitChips /);
  assert.match(ui, /r\.actions\.filter\(a=>s\.actions\.includes\(a\)\)/, 'só ações da seção');
  assert.match(ui, /firstAction\(s\)/, 'ação inicial existente na seção');
  assert.match(read('app/OrganizationSettings.tsx'), /\['grupos','Grupos'\]/);
  assert.match(read('app/UserSheet.tsx'), /<PersonGroups /);
  assert.match(read('app/PushCampaigns.tsx'), /Grupos \(Configurações › Grupos\)/);
  assert.match(read('staff-app/src/PushComposer.tsx'), /Somente estes grupos/);
});
