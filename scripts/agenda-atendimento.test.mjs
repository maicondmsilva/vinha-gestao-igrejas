// Agenda de atendimento: regras, convite com aceite, relatório com sigilo, Integração Visitante e calendário.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {careCommand, careError, privacyLabel, faithLabel, audienceLabel} from '../shared/pastoral-care.ts';
import {convertInput} from '../app/lib/people-tools.ts';
import {pastoralStaffError} from '../app/lib/pastoral-command.ts';
import {portalModules} from '../shared/portal-content.ts';

const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const sql = read('supabase/migrations/20261117120000_agenda_atendimento.sql');
const U = '11111111-1111-4111-8111-111111111111';

test('relatório: só campos conhecidos e níveis de sigilo', () => {
  assert.ok(careCommand({action: 'save', unit: U, data: {appointment: U, summary: 'Conversa boa', privacy: 'secret', topics: ['familia']}}));
  assert.equal(careCommand({action: 'save', unit: U, data: {summary: 'oi'}}), null);
  assert.equal(careCommand({action: 'save', unit: U, data: {summary: 'Conversa', privacy: 'publico'}}), null);
  assert.equal(careCommand({action: 'save', unit: U, data: {summary: 'Conversa', topics: ['politica']}}), null);
  assert.equal(careCommand({action: 'apagar', unit: U, data: {}}), null);
  assert.deepEqual(Object.keys(privacyLabel), ['team', 'restricted', 'secret']);
  assert.match(careError('22023', 'report_locked').error, /7 dias/);
});

test('sigilo pela permissão de usuário (nem o pastor lê sem permissão)', () => {
  assert.match(sql, /privacy='team' and private\.can\(r\.organization_id,r\.unit_id,'pastoral\.reports','view'\)/);
  assert.match(sql, /privacy='restricted' and private\.can\(r\.organization_id,r\.unit_id,'pastoral\.notes','view'\)/);
  assert.match(sql, /privacy='secret' and private\.can\(r\.organization_id,r\.unit_id,'pastoral\.secret','view'\)/);
  assert.doesNotMatch(sql.split('create or replace function private.report_readable')[1].split('$$;')[0], /is_pastor/);
  assert.match(sql, /pastoral_report_reads/);
  for (const c of ['pastoral.history', 'pastoral.reports', 'pastoral.secret']) assert.ok(sql.includes("'" + c + "'"));
});

test('horários respeitados e convite liberado 12 h antes', () => {
  assert.match(sql, /pastoral_outside_hours/);
  assert.match(sql, /starts_at<=now\(\)\+interval '12 hours'/);
  assert.match(sql, /ap\.person_id=a\.person_id/);
  assert.match(pastoralStaffError('22023', 'pastoral_outside_hours').error, /disponibilidade/);
  assert.deepEqual(Object.keys(audienceLabel), ['all', 'leaders', 'group', 'invite']);
});

test('Integração Visitante: decisão de fé separada da etapa', () => {
  const i = convertInput({unit: U, person: U, faith: 'other_church', previousChurch: 'Igreja Batista', next: '2026-12-01'});
  assert.equal(i.data.faith, 'other_church');
  assert.throws(() => convertInput({unit: U, person: U, faith: 'talvez'}));
  assert.throws(() => convertInput({unit: U, person: U, next: '01/12/2026'}));
  assert.ok(faithLabel.none && faithLabel.here && faithLabel.other_church);
  assert.match(read('app/PeopleDirectory.tsx'), /'Integração Visitante'/);
  assert.match(read('app/PeopleConverts.tsx'), /Registrar contato/);
});

test('painel e app ligados', () => {
  assert.match(read('app/PastoralAgenda.tsx'), /WeekCalendar/);
  assert.match(read('app/PastoralAgenda.tsx'), /Relatórios pendentes/);
  assert.match(read('app/pessoas/PersonForms.tsx'), /PastoralHistory/);
  assert.match(read('android-app/src/PastoralScreens.tsx'), /'decline'/);
  assert.match(read('android-app/src/PastoralTeamScreen.tsx'), /MyCareCalendar/);
  assert.match(read('android-app/src/MemberExperience.tsx'), /IntegrationScreen/);
  assert.doesNotMatch(read('android-app/src/PastoralTeamScreen.tsx'), /Salvar anotação sigilosa/);
});

test('Portal da Vinha atualizado (sem trocar o vídeo)', () => {
  const p = portalModules.find((m) => m.id === 'pessoas');
  for (const id of ['integracao', 'agenda', 'cargos']) assert.ok(p.sections.some((x) => x.id === id), id);
});
