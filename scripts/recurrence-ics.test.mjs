import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {occurrences, recurrenceCount, recurrenceValid, maxOccurrences} from '../shared/recurrence.ts';
import {icsCalendar, icsFold, icsText, icsFileName} from '../shared/ics.ts';
import {programmingCommand} from '../app/lib/programming-command.ts';

test('recorrência: mesmas contas do banco', () => {
  assert.deepEqual(recurrenceCount({startsLocal: '2030-03-01T19:00', repeat: 'weekly', ends: 'until', until: '2030-03-31'}), {count: 5});
  assert.deepEqual(recurrenceCount({startsLocal: '2030-01-31T19:00', repeat: 'monthly', ends: 'never'}), {count: 12});
  assert.deepEqual(recurrenceCount({startsLocal: '2030-01-01T19:00', repeat: 'daily', ends: 'never'}), {count: maxOccurrences});
  assert.deepEqual(recurrenceCount({startsLocal: '2030-06-10T19:00', repeat: 'yearly', ends: 'until', until: '2034-12-31'}), {count: 5});
  assert.equal(recurrenceCount({startsLocal: '2030-01-01T19:00', repeat: 'daily', ends: 'until', until: '2031-01-01'}).field, 'until');
  assert.equal(recurrenceCount({startsLocal: '2030-01-01T19:00', repeat: 'weekly', ends: 'until', until: '2029-12-01'}).field, 'until');
  assert.equal(recurrenceCount({startsLocal: '2030-01-01T19:00', repeat: 'weekly', ends: 'count', count: 200}).field, 'count');
  assert.deepEqual(occurrences('2030-01-31T19:00', 'monthly', 3), ['2030-01-31T19:00', '2030-02-28T19:00', '2030-03-31T19:00']);
  assert.deepEqual(occurrences('2032-02-29T09:00', 'yearly', 2), ['2032-02-29T09:00', '2033-02-28T09:00']);
});

test('recorrência: formato aceito pela API', () => {
  assert.ok(recurrenceValid({repeat: 'none', count: 1}));
  assert.ok(recurrenceValid({repeat: 'weekly', count: 10}));
  assert.ok(recurrenceValid({repeat: 'yearly', ends: 'until', until: '2034-01-01'}));
  assert.ok(recurrenceValid({repeat: 'monthly', ends: 'never'}));
  assert.ok(!recurrenceValid({repeat: 'monthly', ends: 'never', count: 3}));
  assert.ok(!recurrenceValid({repeat: 'monthly', ends: 'until'}));
  assert.ok(!recurrenceValid({repeat: 'hourly', count: 2}));
  assert.ok(!recurrenceValid({repeat: 'weekly', count: 121}));
  assert.ok(!recurrenceValid({repeat: 'none', ends: 'never'}));
  assert.equal(typeof programmingCommand, 'function');
});

test('calendário .ics: texto escapado, linhas dobradas, cancelado e UTC', () => {
  const body = icsCalendar({
    name: 'Igreja; fictícia, sede',
    timezone: 'America/Manaus',
    host: 'vinha.test',
    now: new Date('2030-01-01T00:00:00Z'),
    events: [
      {
        id: 'e1',
        title: 'Culto, louvor; oração',
        description: 'Linha 1\nLinha 2 ' + 'á'.repeat(80),
        starts_at: '2030-03-10T23:00:00Z',
        ends_at: '2030-03-11T01:00:00Z',
        location: 'Templo',
        address: 'Rua A',
        version: 3,
        url: 'https://vinha.test/eventos/e1',
      },
      {id: 'e2', title: 'Retiro', starts_at: '2030-04-01T12:00:00Z', ends_at: '2030-04-02T12:00:00Z', status: 'cancelled'},
      {id: 'e3', title: 'Data ruim', starts_at: 'x', ends_at: 'y'},
    ],
  });
  assert.match(body, /^BEGIN:VCALENDAR\r\n/);
  assert.ok(body.includes('X-WR-CALNAME:Igreja\\; fictícia\\, sede\r\n'));
  assert.match(body, /DTSTART:20300310T230000Z\r\nDTEND:20300311T010000Z/);
  assert.ok(body.includes('SUMMARY:Culto\\, louvor\\; oração'));
  assert.match(body, /UID:e1@vinha\.test/);
  assert.match(body, /SEQUENCE:3/);
  assert.match(body, /UID:e2@vinha\.test[\s\S]*STATUS:CANCELLED/);
  assert.doesNotMatch(body, /Data ruim/);
  for (const line of body.split('\r\n')) assert.ok(new TextEncoder().encode(line).length <= 75, line);
  assert.equal(icsText('a\\b'), 'a\\\\b');
  assert.equal(icsFold('x'.repeat(80)), 'x'.repeat(75) + '\r\n ' + 'x'.repeat(5));
  assert.equal(icsFileName('Culto de Ação de Graças!'), 'culto-de-acao-de-gracas.ics');
});

function route(path, names, deps) {
  const src = ts
    .transpileModule(readFileSync(new URL(path, import.meta.url), 'utf8'), {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext}})
    .outputText.replace(/^import .*;\r?\n/gm, '')
    .replaceAll('export async function', 'async function');
  return new Function(...names, src + ';return{GET:typeof GET==="function"?GET:null,POST:typeof POST==="function"?POST:null}')(...deps);
}

test('assinatura: link secreto, sem vazar erro do banco', async () => {
  const calls = [];
  const feed = (data, error = null) =>
    route('../app/api/agenda/feed/route.ts', ['db', 'icsCalendar'], [() => ({rpc: async (n, a) => (calls.push([n, a]), {data, error})}), icsCalendar]);
  const tok = 'a'.repeat(40);
  assert.equal((await feed(null).GET(new Request('https://vinha.test/api/agenda/feed?t=curto'))).status, 404);
  assert.equal(calls.length, 0, 'formato inválido nem chega ao banco');
  assert.equal((await feed(null).GET(new Request('https://vinha.test/api/agenda/feed?t=' + tok))).status, 404);
  const ok = await feed({
    church: 'Igreja',
    unit: 'Sede',
    timezone: 'America/Sao_Paulo',
    events: [{id: 'e1', title: 'Culto', starts_at: '2030-01-01T22:00:00Z', ends_at: '2030-01-01T23:00:00Z'}],
  }).GET(new Request('https://vinha.test/api/agenda/feed?t=' + tok));
  assert.equal(ok.headers.get('content-type'), 'text/calendar; charset=utf-8');
  assert.match(await ok.text(), /URL:https:\/\/vinha\.test\/eventos\/e1/);
  const err = await feed(null, {message: 'secret SQL'}).GET(new Request('https://vinha.test/api/agenda/feed?t=' + tok));
  assert.equal(err.status, 503);
  assert.doesNotMatch(await err.text(), /secret/);
});

test('telas: recorrência completa, assinatura e calendário na página pública', () => {
  const editors = readFileSync(new URL('../app/ProgrammingEditors.tsx', import.meta.url), 'utf8');
  assert.match(editors, /<option value="yearly">Anual<\/option>/);
  assert.match(editors, /<option value="never">Sem término<\/option>/);
  assert.match(editors, /recurrenceCount\(/);
  assert.match(readFileSync(new URL('../app/EventsWorkspace.tsx', import.meta.url), 'utf8'), /<AgendaSubscription key=\{unitId\} unit=\{unitId\}\/>/);
  const pub = readFileSync(new URL('../app/PublicCanonicalEvent.tsx', import.meta.url), 'utf8');
  assert.match(pub, /\/api\/agenda\/event\?id=/);
  assert.match(pub, /timezoneLabel\(tz\)/);
  assert.doesNotMatch(pub, /· Brasília/);
});
