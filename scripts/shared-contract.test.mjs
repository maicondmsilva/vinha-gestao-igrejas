import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {parsePushCommand, pushCampaignSchema} from '../shared/contract/push.ts';
import {ticketBuyerIssue} from '../shared/contract/checkout.ts';
import {fieldErrors, readApiError, ApiError} from '../shared/contract/errors.ts';
import {cpfValid} from '../shared/contract/primitives.ts';
import {compareVersions, compatFor, parseClient, clientHeaderValue, vinhaApps} from '../shared/contract/apps.ts';
import {ticketCode, isStaff} from '../shared/contract/staff.ts';
import {tokensCss, vinhaColors, contrast} from '../shared/design-tokens.ts';
import {GET as compatRoute} from '../app/api/app/compat/route.ts';

const unit = '00000000-0000-4000-8000-000000000001',
  md5id = 'c4ca4238-a0b9-2382-0dcc-509a6f75849b'; // md5-derived ids used by the database tests are not RFC versions
const campaign = (over = {}) => ({title: 'Culto', body: 'Hoje às 19h', targets: [unit], mode: 'now', recurrence: 'none', request: unit, ...over});

test('campanha: cada regra aponta o campo certo', () => {
  assert.ok(pushCampaignSchema.safeParse(campaign()).success);
  assert.ok(pushCampaignSchema.safeParse(campaign({targets: [md5id]})).success, 'aceita ids gerados pelo banco');
  const f = (over) => fieldErrors(pushCampaignSchema.safeParse(campaign(over)).error);
  assert.match(f({title: ' a '}).title, /Título/);
  assert.match(f({body: 'x'.repeat(241)}).body, /Mensagem/);
  assert.match(f({targets: []}).targets, /igreja/);
  assert.match(f({link: {screen: 'event'}})['link.id'], /item/);
  assert.match(f({audience: {ageMin: 30, ageMax: 20}})['audience.ageMax'], /máxima/);
  assert.match(f({mode: 'schedule', sendAt: ''}).sendAt, /futura/);
  assert.match(
    f({mode: 'schedule', sendAt: new Date(Date.now() + 86400000).toISOString(), recurrence: 'weekly', recurrenceUntil: new Date().toISOString()})
      .recurrenceUntil,
    /repetição/,
  );
  assert.ok(f({audience: {unknown: 1}}).audience);
});

test('comando de push mantém as regras antigas do painel', () => {
  assert.ok(parsePushCommand({unit, action: 'list', data: {}}).ok);
  assert.ok(parsePushCommand({unit, action: 'preview', data: {targets: [unit], audience: {}}}).ok);
  assert.equal(parsePushCommand({unit, action: 'create', data: campaign({request: undefined})}).ok, false, 'create exige request');
  assert.ok(parsePushCommand({unit, action: 'edit', id: unit, version: 2, data: campaign({request: undefined})}).ok);
  assert.equal(parsePushCommand({unit, action: 'edit', id: unit, data: campaign()}).ok, false, 'edit exige versão');
  assert.equal(parsePushCommand({unit, action: 'drop'}).ok, false);
  assert.equal(parsePushCommand({unit, action: 'list', extra: 1}).ok, false);
  const r = parsePushCommand({unit, action: 'create', data: campaign({title: 'x'})});
  assert.equal(r.ok, false);
  assert.equal(r.scope, 'data');
});

test('checkout sem cadastro: e-mail, CPF e nome indicados por campo', () => {
  const buyer = {
    buyerName: 'Pessoa fictícia',
    buyerEmail: 'p@example.invalid',
    emailConfirmation: 'p@example.invalid',
    coupon: '',
    intent: 'pay',
    emailConsent: false,
    items: [{type: unit, name: 'Pessoa fictícia', email: '', cpf: '', phone: '', answers: {}}],
  };
  assert.equal(ticketBuyerIssue(buyer), null);
  assert.equal(ticketBuyerIssue({...buyer, items: [{...buyer.items[0], cpf: '529.982.247-25'}]}), null);
  assert.match(ticketBuyerIssue({...buyer, buyerEmail: 'sem-arroba', emailConfirmation: 'sem-arroba'}).fields.buyerEmail, /e-mail válido/);
  assert.match(ticketBuyerIssue({...buyer, items: [{...buyer.items[0], cpf: '111.111.111-11'}]}).fields['items.0.cpf'], /CPF/);
  assert.match(ticketBuyerIssue({...buyer, items: [buyer.items[0], {...buyer.items[0], name: ''}]}).fields['items.1.name'], /nome/);
  assert.ok(ticketBuyerIssue({...buyer, amount: 1}), 'campo extra recusado');
  assert.ok(ticketBuyerIssue({...buyer, items: Array(21).fill(buyer.items[0])}));
  assert.ok(cpfValid('52998224725') && !cpfValid('12345678900'));
});

test('erro da API: campos lidos com segurança, servidor antigo ainda funciona', () => {
  assert.deepEqual(readApiError({error: 'x', fields: {title: 'y', bad: 1}}), {error: 'x', fields: {title: 'y'}});
  assert.deepEqual(readApiError(null, 'f'), {error: 'f'});
  const e = new ApiError({error: 'x', fields: {a: 'b'}}, 400);
  assert.equal(e.message, 'x');
  assert.equal(e.fields.a, 'b');
});

test('compatibilidade entre plataforma e apps', async () => {
  assert.equal(compareVersions('1.2.10', '1.2.9'), 1);
  assert.equal(compareVersions('0.1.0', '0.1.0'), 0);
  assert.deepEqual(parseClient(clientHeaderValue({app: 'staff', version: '0.1.0', platform: 'android'})), {
    app: 'staff',
    version: '0.1.0',
    platform: 'android',
  });
  assert.equal(parseClient('staff/1 (android)'), null);
  assert.equal(compatFor('staff', '0.0.1').status, 'update_required');
  assert.equal(compatFor('staff', vinhaApps.staff.latest).status, 'ok');
  const ok = await compatRoute(new Request('https://vinha.test/api/app/compat?app=staff&version=0.1.0'));
  assert.equal(ok.status, 200);
  assert.equal((await ok.json()).contract, 1);
  assert.equal((await compatRoute(new Request('https://vinha.test/api/app/compat?app=x&version=1'))).status, 400);
  // The staff app version shipped in package.json must be known to the platform.
  const staff = JSON.parse(readFileSync(new URL('../staff-app/package.json', import.meta.url), 'utf8'));
  assert.notEqual(compatFor('staff', staff.version).status, 'update_required');
});

test('equipe: QR e funções', () => {
  assert.equal(ticketCode('https://app.vinhaigrejas.com.br/t/C4CA4238-A0B9-2382-0DCC-509A6F75849B'), md5id);
  assert.equal(ticketCode('nada'), null);
  assert.ok(isStaff({role: 'secretary', status: 'active'}));
  assert.ok(!isStaff({role: 'member', status: 'active'}) && !isStaff({role: 'admin', status: 'suspended'}));
});

test('identidade visual: CSS gerado em dia e contraste AA', () => {
  assert.equal(readFileSync(new URL('../app/vinha-tokens.css', import.meta.url), 'utf8'), tokensCss(), 'rode scripts/build-tokens.mjs');
  assert.match(readFileSync(new URL('../app/globals.css', import.meta.url), 'utf8'), /^@import 'tailwindcss';\n@import '\.\/vinha-tokens\.css';/);
  const c = vinhaColors;
  for (const [fg, bg] of [
    ['ink', 'bg'],
    ['muted', 'bg'],
    ['muted', 'surface'],
    ['goldDeep', 'surface'],
    ['onBrand', 'brand'],
    ['danger', 'surface'],
    ['warn', 'surface'],
    ['ok', 'surface'],
  ])
    assert.ok(contrast(c[fg], c[bg]) >= 4.5, fg + ' sobre ' + bg);
  assert.match(readFileSync(new URL('../staff-app/src/theme.ts', import.meta.url), 'utf8'), /shared\/design-tokens/);
});

test('apps resolvem pacotes do código compartilhado na própria pasta (builds do EAS)', () => {
  for (const app of ['staff-app', 'android-app']) {
    const metro = readFileSync(new URL(`../${app}/metro.config.cjs`, import.meta.url), 'utf8');
    assert.match(metro, /watchFolders/);
    assert.match(metro, /originModulePath/);
    assert.equal(JSON.parse(readFileSync(new URL(`../${app}/package.json`, import.meta.url), 'utf8')).dependencies.zod, '4.4.3');
  }
  assert.equal(JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).dependencies.zod, '4.4.3');
});
