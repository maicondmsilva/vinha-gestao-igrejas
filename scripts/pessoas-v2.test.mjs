// Pessoas v2: idade, termos da igreja, grau do responsável, Portal da Vinha e padrões de tela.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {personAge, personAgeLabel, brDate} from '../shared/person-age.ts';
import {isCustomConsent, newConsentKind} from '../shared/consent-terms.ts';
import {guardianRelations, isKinship} from '../shared/kids-relations.ts';
import {portalEmbed, portalModules} from '../shared/portal-content.ts';

const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('idade a partir do nascimento', () => {
  const today = new Date(2026, 10, 16);
  assert.equal(personAge('1990-05-04', today), 36);
  assert.equal(personAge('1990-11-17', today), 35);
  assert.equal(personAge('1990-11-16', today), 36);
  assert.equal(personAge('', today), null);
  assert.equal(personAge('2030-01-01', today), null);
  assert.equal(personAgeLabel('2025-11-16', today), '1 ano');
  assert.equal(personAgeLabel('2026-03-20', today), '7 meses');
  assert.equal(personAgeLabel('2026-10-16', today), '1 mês');
  assert.equal(brDate('2020-03-10'), '10/03/2020');
  assert.equal(brDate('x'), '');
});

test('termos criados pela igreja usam o padrão aceito pelo banco', () => {
  for (let i = 0; i < 20; i++) {
    const k = newConsentKind();
    assert.match(k, /^custom_[a-z0-9]{6,40}$/);
    assert.ok(isCustomConsent(k));
  }
  assert.equal(isCustomConsent('personal_data'), false);
});

test('só parentesco liga a criança à família', () => {
  assert.ok(isKinship('pai_mae'));
  assert.ok(isKinship('avo'));
  assert.equal(isKinship('outro'), false);
  assert.equal(isKinship('qualquer'), false);
  const sql = read('supabase/migrations/20261116170000_pessoas_crianca_familia_termos.sql');
  for (const [k] of guardianRelations) assert.ok(sql.includes("'" + k + "'"), 'grau sem tratamento no banco: ' + k);
});

test('Portal da Vinha: módulos e vídeos', () => {
  const ids = portalModules.map((m) => m.id);
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ids) assert.match(id, /^[a-z]{2,30}$/);
  const pessoas = portalModules.find((m) => m.id === 'pessoas');
  assert.equal(pessoas.status, 'pronto');
  assert.ok(pessoas.sections.length >= 8);
  assert.equal(portalEmbed('https://youtu.be/abcdefghijk'), 'https://www.youtube-nocookie.com/embed/abcdefghijk');
  assert.equal(portalEmbed('https://www.youtube.com/watch?v=abcdefghijk&t=3'), 'https://www.youtube-nocookie.com/embed/abcdefghijk');
  assert.equal(portalEmbed('https://vimeo.com/123456'), 'https://player.vimeo.com/video/123456');
  assert.equal(portalEmbed('https://exemplo.com/v'), '');
  const page = read('app/portal-vinha/page.tsx');
  assert.match(page, /vinha_portal_videos/);
  const admin = read('app/admin-vinha/portal/page.tsx');
  assert.match(admin, /\/api\/platform\/portal-videos/);
  assert.match(read('app/admin-vinha/layout.tsx'), /\/admin-vinha\/portal/);
  const route = read('app/api/platform/portal-videos/route.ts');
  assert.match(route, /centralRoute/);
  assert.match(route, /origin/);
  assert.match(read('supabase/migrations/20261116180000_portal_videos.sql'), /require_platform_manager/);
  assert.match(read('app/DashboardApp.tsx'), /portal-link/);
});

test('ficha e cadastro: criança marcada, idade, abas e salvar em qualquer etapa', () => {
  const forms = read('app/pessoas/PersonForms.tsx');
  assert.match(forms, /pa-kid/);
  assert.match(forms, /pp-facts/);
  assert.match(forms, /pp-nav/);
  assert.match(forms, /wa\.me/);
  assert.match(forms, /role="tab"/);
  assert.match(forms, /pf-save-now/);
  assert.match(forms, /birthAge/);
  const dir = read('app/PeopleDirectory.tsx');
  assert.match(dir, /'Criança','Crianças'/);
  const css = read('app/people-directory.css');
  assert.match(css, /-webkit-line-clamp/);
});

test('app: assinatura usa o cadastro de quem consente e o grau é obrigatório', () => {
  const consent = read('android-app/src/ConsentScreens.tsx');
  assert.match(consent, /ASSINANDO COMO/);
  assert.match(read('android-app/src/KidsFamily.tsx'), /relation/);
  assert.match(read('android-app/src/KidsGuardians.tsx'), /relation/);
});
