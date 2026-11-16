import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {kidsCallAnswer, kidsCallReasons, openKidsCalls} from '../shared/kids-calls.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('motivos do chamado batem com o banco', () => {
  const sql = read('supabase/migrations/20261114220000_kids_chamar_responsavel.sql');
  for (const [k] of kidsCallReasons) assert.ok(sql.includes(`'${k}'`), k);
  assert.equal(kidsCallReasons[0][0], 'pickup');
});

test('situação do chamado para a sala', () => {
  assert.equal(kidsCallAnswer({answer: 'coming', createdAt: '2026-11-14T10:00:00Z'}), 'Responsável a caminho');
  assert.equal(kidsCallAnswer({answer: 'ok', createdAt: '2026-11-14T10:00:00Z'}), 'Responsável viu o aviso');
  assert.match(kidsCallAnswer({answer: null, createdAt: '2026-11-14T10:00:00Z'}), /aguardando resposta/);
});

test('aviso no app some depois de respondido ou após 30 minutos', () => {
  const now = Date.parse('2026-11-14T10:30:00Z');
  const base = {child: 'Ana', reason: 'pickup', message: ''};
  const items = [
    {...base, id: 'a', createdAt: '2026-11-14T10:20:00Z', answer: null},
    {...base, id: 'b', createdAt: '2026-11-14T09:50:00Z', answer: null},
    {...base, id: 'c', createdAt: '2026-11-14T10:25:00Z', answer: 'coming'},
  ];
  assert.deepEqual(
    openKidsCalls(items, now).map((i) => i.id),
    ['a'],
  );
});

test('Vinha Equipe abre a Sala Kids e o app mostra o aviso', () => {
  const staff = read('staff-app/App.tsx');
  assert.match(staff, /here\?\.kids/);
  assert.match(staff, /u\.checkin \|\| u\.push \|\| u\.kids/);
  assert.match(read('staff-app/src/KidsBoard.tsx'), /'kids_call'/);
  assert.match(read('android-app/src/MemberExperience.tsx'), /<KidsCallAlert /);
  assert.match(read('android-app/src/KidsCallAlert.tsx'), /Estou indo/);
});

test('etiqueta e telão nas telas', () => {
  assert.match(read('android-app/src/KidsCallAlert.tsx'), /member_kids_present/);
  assert.match(read('android-app/src/KidsCallAlert.tsx'), /etiqueta nº/);
  const board = read('staff-app/src/KidsBoard.tsx');
  assert.match(board, /projector: hasProjector && projector/);
  assert.match(board, /Mostrar no telão/);
  assert.match(read('app/KidsOperations.tsx'), /<KidsProjector /);
  assert.match(read('app/KidsProjector.tsx'), /nunca o nome da criança/);
  const sql = read('supabase/migrations/20261114230000_kids_etiqueta_telao.sql');
  assert.match(sql, /api\.holyrics\.com\.br\/send\/SetAlert/);
  assert.match(sql, /'close_after_seconds',60/);
  assert.doesNotMatch(read('app/api/kids/projector/route.ts'), /apiKey.*json\(r\.data/);
});

test('rascunho do perfil vai para a plataforma', () => {
  const app = read('android-app/src/MprApp.tsx');
  assert.match(app, /'member_profile_draft'/);
  assert.match(app, /},1500\)/);
});

test('telão: aguarda a resposta do Holyrics e explica o resultado', () => {
  const sql = read('supabase/migrations/20261116140000_kids_telao_diagnostico.sql');
  assert.match(sql, /\/request\/SetAlert/);
  assert.match(sql, /display_ahead/);
  const ui = read('app/KidsProjector.tsx');
  assert.match(ui, /action: 'last'/);
  for (const t of ['Chegou ao Holyrics', 'SetAlert', 'acesso pela internet']) assert.ok(ui.includes(t), t);
});
