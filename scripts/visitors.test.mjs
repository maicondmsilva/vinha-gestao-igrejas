import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {visitorError, visitorHeard, visitorPhoneMask, visitorUrl} from '../shared/visitors.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('máscara do WhatsApp', () => {
  assert.equal(visitorPhoneMask('11988887777'), '(11) 98888-7777');
  assert.equal(visitorPhoneMask('1133334444'), '(11) 3333-4444');
  assert.equal(visitorPhoneMask('11'), '(11');
});

test('respostas aceitas pelo banco', () => {
  const sql = read('supabase/migrations/20261115120000_visitantes_qrcode.sql');
  for (const [k] of visitorHeard) assert.ok(sql.includes(`'${k}'`), k);
  assert.match(visitorError('ERROR: visitor_consent'), /autorização/);
  assert.equal(visitorUrl('abc'), 'https://app.vinhaigrejas.com.br/visitante/abc');
});

test('telas: QR no painel, página pública e Vinha Equipe', () => {
  assert.match(read('app/visitante/[unit]/page.tsx'), /'visitor_checkin'/);
  assert.match(read('app/PeopleDirectory.tsx'), /<VisitorQr /);
  assert.match(read('app/pessoas/PersonForms.tsx'), /<PersonVisits /);
  assert.match(read('app/pessoas/PersonForms.tsx'), /<PersonPhoto /);
  assert.match(read('staff-app/App.tsx'), /here\?\.visitors/);
  assert.match(read('staff-app/src/VisitorForm.tsx'), /'visitor_staff'/);
});

test('foto do cadastro só com sessão do painel e link temporário', () => {
  const route = read('app/api/people/photo/route.ts');
  assert.match(route, /authorizeSupabaseChurch\(request, 'people\.read'\)/);
  assert.match(route, /createSignedUrl\(.*, 600\)/s);
});
