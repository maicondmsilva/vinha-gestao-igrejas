import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {describeSeries, seriesProblem, kidsSetupError} from '../shared/kids-setup.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const base = {
  name: 'Kids domingo',
  rule: 'weekly',
  weekdays: [0],
  monthDay: null,
  monthWeek: null,
  startsTime: '09:00',
  durationMinutes: 120,
  rooms: [{roomId: 'r', classId: 'c', capacity: 10, minStaff: 1}],
};

test('descrição da repetição em português', () => {
  assert.equal(describeSeries(base), 'Todo domingo às 09:00');
  assert.equal(describeSeries({...base, weekdays: [3, 0]}), 'Toda domingo e quarta às 09:00');
  assert.equal(describeSeries({...base, rule: 'daily'}), 'Todo dia às 09:00');
  assert.equal(describeSeries({...base, rule: 'monthly_day', monthDay: 5}), 'Todo mês no dia 5 às 09:00');
  assert.equal(describeSeries({...base, rule: 'monthly_week', weekdays: [6], monthWeek: 1}), 'Todo mês no 1º sábado às 09:00');
});

test('regras para salvar a repetição', () => {
  assert.equal(seriesProblem(base), '');
  assert.match(seriesProblem({...base, weekdays: []}), /dia da semana/);
  assert.match(seriesProblem({...base, rooms: []}), /sala/);
  assert.match(seriesProblem({...base, startsTime: '9h'}), /09:00/);
  assert.match(kidsSetupError('kids_staff_identity_required'), /conta ativa/);
});

test('Vinha Equipe e painel configuram sem sessão ativa', () => {
  const app = read('staff-app/App.tsx');
  assert.match(app, /here\?\.kidsConfigure/);
  const screen = read('staff-app/src/KidsSetupScreen.tsx');
  for (const t of ['Criar sala', 'Criar turma', 'Adicionar à equipe', 'Nova sessão que se repete', 'Famílias podem reservar']) assert.ok(screen.includes(t), t);
  assert.match(read('app/KidsOperations.tsx'), /<KidsSetupPanel /);
  const sql = read('supabase/migrations/20261115170000_kids_equipe_fixa_sessoes_recorrentes.sql');
  assert.match(sql, /cron\.schedule\('kids-series-run'/);
  assert.match(sql, /bookable_from<=clock_timestamp\(\)/);
});
