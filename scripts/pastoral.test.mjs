import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {canCancel, durationLabel, monthGrid, monthTitle, openCount, pastoralError, shiftMonth, sortAttendants} from '../shared/pastoral.ts';
import {pastoralCommand} from '../app/lib/pastoral-command.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
test('calendário do mês começa no dia da semana certo', () => {
  const w = monthGrid('2026-11');
  assert.equal(w[0][0], '2026-11-01', 'novembro de 2026 começa num domingo');
  assert.equal(w.flat().filter(Boolean).length, 30);
  assert.equal(monthGrid('2026-12')[0].indexOf('2026-12-01'), 2, 'dezembro começa na terça');
  assert.ok(monthGrid('2026-02').every((r) => r.length === 7));
  assert.equal(shiftMonth('2026-12', 1), '2027-01');
  assert.equal(shiftMonth('2027-01', -1), '2026-12');
  assert.equal(monthTitle('2026-11'), 'Novembro de 2026');
});
test('regras do membro: cancelar até 12 h, pedidos em aberto, durações', () => {
  const now = Date.parse('2026-11-14T12:00:00Z');
  assert.equal(canCancel({status: 'confirmed', startsAt: '2026-11-15T00:00:00Z'}, now), true, '12 h antes ainda pode');
  assert.equal(canCancel({status: 'confirmed', startsAt: '2026-11-14T23:00:00Z'}, now), false, '11 h antes não pode');
  assert.equal(canCancel({status: 'done', startsAt: '2026-11-20T00:00:00Z'}, now), false);
  assert.equal(
    openCount(
      [
        {status: 'requested', endsAt: '2026-11-20T00:00:00Z'},
        {status: 'cancelled', endsAt: '2026-11-20T00:00:00Z'},
        {status: 'confirmed', endsAt: '2026-11-10T00:00:00Z'},
      ],
      now,
    ),
    1,
  );
  assert.deepEqual([30, 45, 60, 90, 120].map(durationLabel), ['30 min', '45 min', '1 hora', '1h30', '2 horas']);
  assert.match(pastoralError('pastoral_open_limit'), /2 pedidos/);
});
test('líder da célula e pastor aparecem primeiro', () => {
  const a = (name, myLeader = false, pastor = false) => ({
    id: name,
    name,
    role: '',
    about: '',
    durations: [30],
    kinds: ['conversa'],
    modes: ['presencial'],
    autoConfirm: false,
    myLeader,
    pastor,
  });
  assert.deepEqual(
    sortAttendants([a('Zé'), a('Pr. Ana', false, true), a('Bia', true)]).map((x) => x.name),
    ['Bia', 'Pr. Ana', 'Zé'],
  );
});
test('painel valida a forma do pedido', () => {
  const unit = '11111111-1111-4111-8111-111111111111';
  assert.ok(pastoralCommand({unit, action: 'decide', data: {id: unit, version: 1, decision: 'confirm', reason: '', link: ''}}));
  assert.equal(pastoralCommand({unit, action: 'drop_table', data: {}}), null);
  assert.equal(pastoralCommand({unit: 'x', action: 'decide', data: {}}), null);
  assert.equal(pastoralCommand({unit, action: 'decide', data: []}), null);
});
test('telas com identidade Vinha e privacidade', () => {
  const app = read('android-app/src/PastoralScreens.tsx') + read('shared/pastoral.ts'),
    panel = read('app/PastoralAgenda.tsx'),
    sql = read('supabase/migrations/20261114160000_agenda_pastoral.sql');
  for (const t of ['UM TEMPO PARA CONVERSAR', '3 · ESCOLHA O DIA', 'Com horários livres', 'Agenda cheia', 'Sem atendimento', 'Meus horários'.toUpperCase()])
    assert.ok(app.includes(t), t);
  for (const t of ['Confirmação automática', 'Marcar com um membro', 'Anotação sigilosa', 'Bloquear dias']) assert.ok(panel.includes(t), t);
  assert.match(sql, /exclude using gist/, 'banco impede horários sobrepostos');
  assert.match(sql, /interval '24 hours'/);
  assert.match(sql, /interval '12 hours'/);
  assert.match(sql, /open_count>=2/);
  assert.doesNotMatch(sql.slice(sql.indexOf('member_inbox_rows(p_org uuid')), /ap\.message/, 'aviso não leva o motivo');
});

test('agenda de quem atende no app', () => {
  const ui = read('android-app/src/PastoralTeamScreen.tsx'),
    exp = read('android-app/src/MemberExperience.tsx'),
    sql = read('supabase/migrations/20261114180000_agenda_pastoral_proprio.sql');
  for (const t of ['AGENDA DE ATENDIMENTO', 'PARA CONFIRMAR', 'PRÓXIMOS ATENDIMENTOS', 'Confirmação automática', 'Marcar e avisar o membro', 'Na casa do membro']) assert.ok(ui.includes(t), t);
  assert.match(exp, /!!pastoralTeam\.data&&/, 'cartão só para quem atende');
  assert.match(sql, /private\.pastoral_self\(a\.id\)/, 'só a própria pessoa muda a própria agenda');
});
