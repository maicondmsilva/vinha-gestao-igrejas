import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {fromLocal, toLocalInput, offsetMinutes, timezoneValid, timezoneLabel, setPanelTimezone, panelTimezone, churchTimezones} from '../shared/timezone.ts';
import {agendaLocal, agendaDate} from '../shared/member-agenda.ts';
import {eventsOnDay, localDay} from '../shared/programming.ts';
import {staffAccessCommandSchema, staffScopes} from '../shared/contract/staff.ts';
import {validationBody} from '../shared/contract/errors.ts';

const id = '00000000-0000-4000-8000-000000000001';

test('fuso: horário local de cada igreja vira o mesmo instante que o banco calcula', () => {
  assert.equal(new Date(fromLocal('2027-03-10T19:00', 'America/Sao_Paulo')).toISOString(), '2027-03-10T22:00:00.000Z');
  assert.equal(new Date(fromLocal('2027-03-10T19:00', 'America/Manaus')).toISOString(), '2027-03-10T23:00:00.000Z');
  assert.equal(new Date(fromLocal('2027-07-04T19:00', 'America/New_York')).toISOString(), '2027-07-04T23:00:00.000Z', 'horário de verão');
  assert.equal(new Date(fromLocal('2027-01-04T19:00', 'America/New_York')).toISOString(), '2027-01-05T00:00:00.000Z');
  assert.equal(toLocalInput('2027-03-10T23:00:00Z', 'America/Manaus'), '2027-03-10T19:00');
  assert.equal(offsetMinutes(new Date('2027-03-10T12:00:00Z'), 'America/Noronha'), -120);
  assert.ok(Number.isNaN(fromLocal('ontem', 'America/Manaus')));
  assert.ok(timezoneValid('America/Rio_Branco') && !timezoneValid('Mars/Olympus') && !timezoneValid("America/Sao_Paulo'; drop"));
  for (const [z] of churchTimezones) assert.ok(timezoneValid(z), z);
  assert.equal(timezoneLabel('America/Sao_Paulo'), 'horário de Brasília');
  assert.equal(timezoneLabel('America/Porto_Velho'), 'horário de Porto Velho');
});

test('painel mostra a agenda no fuso da igreja carregada', () => {
  assert.equal(panelTimezone(), 'America/Sao_Paulo');
  assert.equal(agendaLocal('2027-03-10T23:00:00Z'), '2027-03-10T20:00');
  setPanelTimezone('America/Manaus');
  assert.equal(agendaLocal('2027-03-10T23:00:00Z'), '2027-03-10T19:00');
  assert.match(agendaDate('2027-03-10T23:00:00Z'), /19:00/);
  assert.equal(localDay('2027-03-11T03:30:00Z'), '2027-03-10');
  const ev = {starts_at: '2027-03-11T03:30:00Z', ends_at: '2027-03-11T03:50:00Z'};
  assert.equal(eventsOnDay([ev], '2027-03-10').length, 1, 'meia-noite e meia em Brasília ainda é dia 10 em Manaus');
  assert.equal(eventsOnDay([ev], '2027-03-10', 'America/Sao_Paulo').length, 0);
  setPanelTimezone('Mars/Olympus');
  assert.equal(panelTimezone(), 'America/Sao_Paulo', 'valor inválido volta para Brasília');
});

test('comandos de permissão: escopos conhecidos e campos indicados', () => {
  assert.deepEqual([...staffScopes], ['agenda', 'checkin', 'publishing', 'push']);
  assert.ok(staffAccessCommandSchema.safeParse({action: 'grant', data: {user: id, unit: id, scopes: ['agenda', 'checkin']}}).success);
  assert.ok(staffAccessCommandSchema.safeParse({action: 'grant', data: {user: id, unit: id, scopes: []}}).success, 'lista vazia revoga');
  assert.ok(staffAccessCommandSchema.safeParse({action: 'timezone', data: {timezone: 'America/Manaus'}}).success);
  assert.ok(staffAccessCommandSchema.safeParse({action: 'timezone', data: {unit: id, timezone: ''}}).success, 'vazio volta a herdar');
  const bad = validationBody(staffAccessCommandSchema.safeParse({action: 'grant', data: {user: id, unit: id, scopes: ['finance']}}).error);
  assert.match(bad.fields['data.scopes.0'], /desconhecida/);
  assert.equal(staffAccessCommandSchema.safeParse({action: 'grant', data: {user: id, unit: id, scopes: [], role: 'admin'}}).success, false);
  assert.equal(staffAccessCommandSchema.safeParse({action: 'timezone', data: {timezone: "x'; drop"}}).success, false);
  assert.equal(staffAccessCommandSchema.safeParse({action: 'drop', data: {}}).success, false);
});

function route(result) {
  const calls = [],
    src = ts
      .transpileModule(readFileSync(new URL('../app/api/staff-access/route.ts', import.meta.url), 'utf8'), {
        compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext},
      })
      .outputText.replace(/^import .*;\r?\n/gm, '')
      .replaceAll('export async function', 'async function');
  const fns = new Function('authorizeSupabaseChurch', 'db', 'boundedBody', 'validationBody', 'staffAccessCommandSchema', src + ';return{GET,POST}')(
    async () => ({access: {membership: {organization_id: 'verified-org'}}}),
    () => ({rpc: async (name, args) => (calls.push({name, args}), result)}),
    async (r) => new Uint8Array(await r.arrayBuffer()),
    validationBody,
    staffAccessCommandSchema,
  );
  return {...fns, calls};
}

test('API de permissões: ministério da sessão, erros com campo, sem vazar SQL', async () => {
  const ok = route({data: {units: []}, error: null});
  assert.equal((await ok.GET(new Request('https://vinha.test/api/staff-access?action=mine'))).status, 200);
  assert.deepEqual(ok.calls[0], {name: 'staff_access', args: {p_org: 'verified-org', p_action: 'mine', p_data: {}}});
  assert.equal((await ok.GET(new Request('https://vinha.test/api/staff-access?action=grant'))).status, 400, 'GET não grava');
  const post = (b) => new Request('https://vinha.test/api/staff-access', {method: 'POST', body: JSON.stringify(b)});
  assert.equal((await ok.POST(post({action: 'grant', data: {user: id, unit: id, scopes: ['push']}, org: id}))).status, 400, 'ministério nunca vem do corpo');
  const denied = route({data: null, error: {code: '22023', message: 'staff_access_unit secret SQL'}}),
    r = await denied.POST(post({action: 'grant', data: {user: id, unit: id, scopes: ['push']}})),
    body = await r.json();
  assert.equal(r.status, 400);
  assert.ok(body.fields.unit);
  assert.doesNotMatch(JSON.stringify(body), /secret SQL/);
  const generic = route({data: null, error: {code: 'XX000', message: 'internal detail'}});
  assert.equal((await generic.GET(new Request('https://vinha.test/api/staff-access?action=list'))).status, 503);
});

test('banco: concessões só somam acesso e regras financeiras seguem estritas', () => {
  const sql = readFileSync(new URL('../supabase/migrations/20261106120000_permissoes_finas_fuso.sql', import.meta.url), 'utf8');
  assert.match(sql, /m\.role in\('secretary','leader'\)/);
  assert.match(sql, /'commerce_receivers','commerce_receiving_purpose','event_checkout_review'/);
  assert.match(sql, /p_action not in\(''list'',''calendar'',''detail'',''attendees'',''categories'',''checkin''\) and not private\.event_manager/);
  assert.match(sql, /revoke all on private\.staff_grants from public,anon,authenticated,service_role/);
  const route = readFileSync(new URL('../app/api/programming/route.ts', import.meta.url), 'utf8');
  assert.match(route, /authorizeSupabaseChurch\(request,'units\.read'\)/);
  assert.match(
    readFileSync(new URL('../app/api/event-tickets-admin/route.ts', import.meta.url), 'utf8'),
    /b\.action!=='checkin'/,
    'entrada pelo app sem versão do evento',
  );
});
