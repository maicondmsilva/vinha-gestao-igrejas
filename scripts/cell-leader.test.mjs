import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {
  attendanceRate,
  daysToBirthday,
  initials,
  leaderError,
  needsCare,
  pendingMeetings,
  phoneDigits,
  upcomingBirthdays,
  whatsappLink,
} from '../shared/cell-leader.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const person = (name, birthday = '', recent = []) => ({participantId: name, name, phone: '', birthday, since: '2026-01-01', recent});
const meeting = (id, date, status, present = 0, expected = 0) => ({
  id,
  topic: id,
  date,
  time: '20:00',
  status,
  version: 1,
  notes: '',
  expected,
  present,
  visitors: 0,
  roster: [],
});
test('WhatsApp aceita número com máscara e põe o 55 em números do Brasil', () => {
  assert.equal(phoneDigits('(11) 98888-7777'), '11988887777');
  assert.equal(phoneDigits('123'), '', 'curto demais não vira link');
  assert.equal(whatsappLink('(11) 98888-7777', 'Oi, Ana!'), 'https://wa.me/5511988887777?text=Oi%2C%20Ana!');
  assert.equal(whatsappLink('+351 912 345 678'), 'https://wa.me/351912345678', 'internacional fica como está');
  assert.equal(whatsappLink(''), '');
});
test('aniversários: hoje, virada de ano e 29 de fevereiro', () => {
  assert.equal(daysToBirthday('11-13', '2026-11-13'), 0);
  assert.equal(daysToBirthday('01-02', '2026-12-30'), 3);
  assert.equal(daysToBirthday('02-29', '2026-02-20'), 8, 'ano sem 29/02 usa 28/02');
  assert.equal(daysToBirthday('', '2026-01-01'), -1);
  const list = upcomingBirthdays([person('Bia', '11-20'), person('Ana', '11-13'), person('Caio', '03-01'), person('Sem data')], '2026-11-13', 30);
  assert.deepEqual(
    list.map((p) => [p.name, p.inDays]),
    [
      ['Ana', 0],
      ['Bia', 7],
    ],
  );
});
test('cuidado, frequência e encontros esperando relato', () => {
  assert.equal(needsCare(person('A', '', [false, false, true])), true);
  assert.equal(needsCare(person('B', '', [false, true])), false);
  assert.equal(needsCare(person('C', '', [false])), false, 'um encontro só não basta');
  assert.equal(
    attendanceRate([meeting('a', '2026-11-01', 'completed', 3, 4), meeting('b', '2026-10-25', 'completed', 1, 4), meeting('c', '2026-11-20', 'scheduled')]),
    50,
  );
  assert.equal(attendanceRate([]), null);
  assert.deepEqual(
    pendingMeetings(
      [
        meeting('x', '2026-11-13', 'scheduled'),
        meeting('y', '2026-11-20', 'scheduled'),
        meeting('z', '2026-11-01', 'completed'),
        meeting('w', '2026-11-06', 'scheduled'),
      ],
      '2026-11-13',
    ).map((m) => m.id),
    ['w', 'x'],
  );
  assert.equal(initials('ana maria souza'), 'AM');
  assert.match(leaderError('cell_version_conflict'), /atualizou/);
});
test('tela do líder: identidade Vinha e só para quem lidera', () => {
  const ui = read('android-app/src/CellLeaderScreen.tsx'),
    exp = read('android-app/src/MemberExperience.tsx'),
    sql = read('supabase/migrations/20261113220000_lider_celula_app.sql');
  for (const t of ['MINHA CÉLULA', 'RELATO DO ENCONTRO', 'Quem esteve', 'Quem visitou', 'Como foi', 'SENTIMOS FALTA', 'CHEGANDO NO GRUPO', 'ANIVERSARIANTES'])
    assert.ok(ui.includes(t), t);
  assert.match(exp, /leaderCells\.length>0&&/, 'entrada aparece só para líderes');
  assert.match(sql, /revoke all on function public\.member_cell_leader\(uuid,uuid,uuid,text,jsonb\) from public,anon/);
  assert.match(sql, /case when can_report then coalesce\(p\.phone,''\) else '' end/, 'telefone só para quem cuida do grupo');
});
