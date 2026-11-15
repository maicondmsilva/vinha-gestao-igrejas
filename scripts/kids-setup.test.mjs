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

test('melhorias: disponibilidade, revezamento, aviso, lembretes, abertura e relatório', async () => {
  const {occupancy, rotationLetter} = await import('../shared/kids-setup.ts');
  assert.equal(rotationLetter(2), 'B');
  assert.equal(occupancy({children: 6, capacity: 8}), 75);
  const sql = read('supabase/migrations/20261115190000_kids_melhorias_escala.sql');
  assert.match(sql, /kids_team_unavailable u where u\.team_id=t\.id and u\.day=d/, 'indisponível não é escalado');
  assert.match(sql, /select private\.kids_series_run\(\); select private\.kids_series_autoopen\(\)/);
  for (const k of ['kids-serve:', 'kids-open:', 'kids-today:']) assert.ok(sql.includes(k), k);
  const vol = read('android-app/src/KidsVolunteerScreen.tsx');
  for (const t of ['Confirmo', 'Não posso', 'DIAS EM QUE NÃO POSSO']) assert.ok(vol.includes(t), t);
  assert.match(read('android-app/src/MemberExperience.tsx'), /Minha escala no Kids/);
  assert.match(read('staff-app/src/KidsSetupScreen.tsx'), /Ver relatório das sessões/);
  assert.match(read('app/KidsSetupPanel.tsx'), /Relatório das repetições/);
});

test('recepção Kids no Vinha Equipe: comprovante e conferência', async () => {
  const {receiptCode, receptionError} = await import('../shared/kids-reception.ts');
  const code = receiptCode(new Uint8Array(32).fill(171));
  assert.match(code, /^[a-f0-9]{64}$/);
  assert.throws(() => receiptCode(new Uint8Array(8)));
  assert.match(receptionError('kids_guardian_required'), /não está autorizado/);
  const ui = read('staff-app/src/KidsReception.tsx');
  for (const t of ['Registrar entrada', 'Registrar saída', 'Conferi a identidade', 'Ler QR Code do comprovante', 'Enviar comprovante'])
    assert.ok(ui.includes(t), t);
  assert.match(ui, /'kids_pickup_guardians'/);
  assert.match(read('staff-app/App.tsx'), /Recepção Kids/);
});

test('QR da reserva, foto da criança e responsável temporário', async () => {
  const {kidsPassCode} = await import('../shared/kids-reception.ts');
  const c = 'a'.repeat(64);
  assert.equal(kidsPassCode('https://x/y?c=' + c.toUpperCase()), c);
  assert.equal(kidsPassCode('curto'), '');
  const sql = read('supabase/migrations/20261115210000_kids_qr_reserva_temporario.sql');
  assert.match(sql, /gen_random_bytes\(32\)/);
  assert.match(sql, /days not between 1 and 30/);
  const app = read('android-app/src/FamilyScreens.tsx');
  assert.match(app, /<ReservationPass /);
  assert.match(app, /<KidsGuardians /);
  assert.match(read('android-app/src/KidsGuardians.tsx'), /Autorizar outra pessoa a buscar/);
  const flow = read('staff-app/src/KidsPassFlow.tsx');
  assert.match(flow, /'kids_pass'/);
  assert.match(flow, /receiptSecret: code/, 'o mesmo QR vale como comprovante');
  assert.match(read('staff-app/src/KidsReception.tsx'), /<KidsPassFlow/);
  assert.match(read('app/KidsOperations.tsx'), /<KidsChildPhoto /);
  assert.match(read('app/api/kids/photo/route.ts'), /createSignedUrl\(.*600\)/s);
});
