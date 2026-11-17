import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {describeSeries, seriesProblem, kidsSetupError, sessionTimes} from '../shared/kids-setup.ts';
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
  for (const t of ['Criar sala', 'Criar turma', '<KidsSessionEditor']) assert.ok(screen.includes(t), t);
  const editor = read('staff-app/src/KidsSessionEditor.tsx');
  for (const t of ['+ Nova sessão', 'Não repete', 'Toda semana', 'Responsáveis da sala']) assert.ok(editor.includes(t), t);
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
  assert.match(read('app/KidsSetupPanel.tsx'), /Relatório das sessões/);
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
  assert.match(read('staff-app/App.tsx'), /<KidsHub /);
  assert.match(read('staff-app/src/KidsHub.tsx'), /'Recepção'/);
});

test('QR da reserva, foto da criança e responsável temporário', async () => {
  const {kidsPassCode} = await import('../shared/kids-reception.ts');
  const c = 'a'.repeat(64);
  assert.equal(kidsPassCode('https://x/y?c=' + c.toUpperCase()), c);
  assert.equal(kidsPassCode('curto'), '');
  const sql = read('supabase/migrations/20261115210000_kids_qr_reserva_temporario.sql');
  assert.match(sql, /gen_random_bytes\(32\)/);
  assert.match(sql, /days not between 1 and 30/);
  const app = read('android-app/src/FamilyScreens.tsx') + read('android-app/src/KidsFamily.tsx');
  assert.match(app, /<ReservationPass /);
  assert.match(app, /<KidsGuardians /);
  assert.match(read('android-app/src/KidsGuardians.tsx'), /Adicionar responsável/);
  const flow = read('staff-app/src/KidsPassFlow.tsx');
  assert.match(flow, /'kids_pass'/);
  assert.match(flow, /receiptSecret: code/, 'o mesmo QR vale como comprovante');
  assert.match(read('staff-app/src/KidsReception.tsx'), /<KidsPassFlow/);
  assert.match(read('app/kids/KidsTabs.tsx'), /<KidsChildPhoto /);
  assert.match(read('app/api/kids/photo/route.ts'), /createSignedUrl\(.*600\)/s);
});

test('Área Kids da família: idade e reserva da vez', async () => {
  const {childAge, childNextBooking} = await import('../shared/kids-family.ts');
  assert.equal(childAge('2020-05-10', new Date('2026-11-15T12:00:00')), '6 anos');
  assert.equal(childAge('2026-03-20', new Date('2026-11-15T12:00:00')), '7 meses');
  const base = {status: 'reserved', ends_at: '2026-11-15T13:00:00Z'};
  const list = [
    {...base, id: 'a', profile_id: 'c', starts_at: '2026-11-22T12:00:00Z', ends_at: '2026-11-22T13:00:00Z', attendance: null},
    {...base, id: 'b', profile_id: 'c', starts_at: '2026-11-15T11:00:00Z', attendance: 'present'},
  ];
  assert.equal(childNextBooking(list, 'c', Date.parse('2026-11-15T12:00:00Z'))?.id, 'b', 'na sala vem antes');
  const ui = read('android-app/src/KidsFamily.tsx');
  for (const t of ['Reservar vaga', 'Detalhes', 'Histórico', '+ Cadastrar criança']) assert.ok(ui.includes(t), t);
});

test('painel Kids em 4 seções e Vinha Equipe com uma entrada', async () => {
  const {kidsPages, kidsSections, kidsSectionOf} = await import('../shared/dashboard-menu.ts');
  assert.deepEqual(
    kidsSections.map(([, l]) => l),
    ['Hoje', 'Crianças', 'Configurar', 'Relatórios'],
  );
  for (const [id] of kidsPages)
    assert.ok(
      kidsSections.some(([, , pages]) => pages.includes(id)),
      'página sem seção: ' + id,
    );
  assert.equal(kidsSectionOf('attendance'), 'today');
  assert.equal(kidsSectionOf('setup'), 'plan');
  assert.match(read('app/DashboardNavigation.tsx'), /kidsSections\.map/);
  const app = read('staff-app/App.tsx');
  assert.equal((app.match(/<Action title="Kids"/g) || []).length, 1, 'uma entrada Kids');
});

test('editar e excluir sem perder histórico', () => {
  const t = sessionTimes('16/11/2026', '09:00', '10:30');
  assert.ok(t && Date.parse(t.endsAt) - Date.parse(t.startsAt) === 90 * 60000);
  assert.equal(sessionTimes('31/02/2026', '09:00', '10:00'), null);
  assert.equal(sessionTimes('16/11/2026', '10:00', '09:00'), null);
  assert.match(kidsSetupError('kids_has_records'), /desative/);
  const screen = read('staff-app/src/KidsSetupScreen.tsx');
  for (const a of ['room_delete', 'class_delete', 'session_delete']) assert.match(screen, new RegExp(a));
  assert.match(screen, /locked/);
  const sql = read('supabase/migrations/20261115240000_kids_editar_excluir.sql');
  assert.match(sql, /kids_has_records/);
  assert.match(sql, /skip_dates/);
});

test('sessão única: não repete ou toda semana, com responsáveis por sala', async () => {
  const {blankSessionForm, sessionFormProblem, sessionPayload, sessionFormFrom, describeSession} = await import('../shared/kids-setup.ts');
  const today = new Date(2026, 10, 16);
  const f = {...blankSessionForm('x', today), name: 'Kids domingo', weekdays: [0, 3], rooms: [{roomId: 'r', classId: 'c', staff: ['t1']}]};
  assert.equal(sessionFormProblem(f, today), '');
  assert.equal(describeSession(f), 'Toda semana: Dom e Qua às 09:00');
  const p = sessionPayload(f, () => 12, today);
  assert.equal(p.rule, 'weekly');
  assert.deepEqual(p.rooms[0], {roomId: 'r', classId: 'c', capacity: 12, minStaff: 1, staff: ['t1']});
  assert.equal(p.autoTeam, false);
  const once = {...f, repeat: 'once', date: '22/11/2026'};
  const q = sessionPayload(once, () => 10, today);
  assert.equal(q.validFrom, '2026-11-22');
  assert.equal(q.validUntil, '2026-11-22');
  assert.deepEqual(q.weekdays, [0]);
  assert.equal(sessionFormFrom({...q, next: [], version: 1, monthDay: null, monthWeek: null}).repeat, 'once');
  assert.match(sessionFormProblem({...once, date: '01/11/2026'}, today), /passou/);
  assert.match(sessionFormProblem({...f, weekdays: []}, today), /dia da semana/);
  assert.match(sessionFormProblem({...f, rooms: []}, today), /sala/);
});
