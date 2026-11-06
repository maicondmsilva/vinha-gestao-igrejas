import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {kidsStationCommand, kidsStationOnline, kidsStationHeartbeatMs} from '../shared/contract/kids.ts';
import {kidsOperationCommand} from '../app/lib/kids-operations.ts';

const unit = '00000000-0000-4000-8000-000000000001',
  id = 'c4ca4238-a0b9-2382-0dcc-509a6f75849b';

test('contrato de estação: nome, aparelho e ids', () => {
  assert.deepEqual(kidsStationCommand({action: 'register', data: {name: '  Tablet da recepção ', platform: 'android'}}), {
    action: 'register',
    data: {name: 'Tablet da recepção', platform: 'android'},
  });
  assert.deepEqual(kidsStationCommand({action: 'revoke', id}), {action: 'revoke', id});
  for (const bad of [
    {action: 'register', data: {name: 'x', platform: 'android'}},
    {action: 'register', data: {name: 'Tablet', platform: 'windows'}},
    {action: 'register', data: {name: 'Tablet', platform: 'android', user: id}},
    {action: 'heartbeat', id: 'nope'},
    {action: 'revoke', id, unit},
    {action: 'list'},
  ])
    assert.throws(() => kidsStationCommand(bad), JSON.stringify(bad));
  assert.equal(typeof kidsOperationCommand, 'function', 'contrato Kids continua exportado pelo painel');
});

test('estação aparece em uso só enquanto responde', () => {
  const now = Date.parse('2026-11-06T12:00:00Z');
  assert.ok(kidsStationOnline({lastSeenAt: new Date(now - kidsStationHeartbeatMs).toISOString(), revokedAt: null}, now));
  assert.ok(!kidsStationOnline({lastSeenAt: new Date(now - kidsStationHeartbeatMs * 3).toISOString(), revokedAt: null}, now));
  assert.ok(!kidsStationOnline({lastSeenAt: new Date(now).toISOString(), revokedAt: new Date(now).toISOString()}, now));
});

function route({error = null, data = {ok: true, items: []}, units = [{id: unit}]} = {}) {
  const calls = [],
    src = ts
      .transpileModule(readFileSync(new URL('../app/api/kids-station/route.ts', import.meta.url), 'utf8'), {
        compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext},
      })
      .outputText.replace(/^import .*;\r?\n/gm, '')
      .replaceAll('export async function', 'async function');
  const fns = new Function('authorizeSupabaseChurch', 'db', 'boundedBody', 'uuidPattern', 'kidsStationCommand', src + ';return{GET,POST}')(
    async () => ({access: {membership: {organization_id: 'verified-org', units}}}),
    () => ({rpc: async (name, args) => (calls.push({name, args}), {data, error})}),
    async (r) => new Uint8Array(await r.arrayBuffer()),
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    kidsStationCommand,
  );
  return {...fns, calls};
}
const post = (body) => new Request('https://vinha.test/api/kids-station?unit=' + unit, {method: 'POST', body: JSON.stringify(body)});

test('API de estações: igreja da sessão, ministério nunca do corpo, desativada responde 423', async () => {
  const ok = route();
  assert.equal((await ok.GET(new Request('https://vinha.test/api/kids-station?unit=' + unit))).status, 200);
  assert.deepEqual(ok.calls[0], {name: 'kids_station', args: {p_org: 'verified-org', p_unit: unit, p_action: 'list', p_id: null, p_data: {}}});
  await ok.POST(post({action: 'register', data: {name: 'Tablet', platform: 'ios'}}));
  assert.deepEqual(ok.calls[1].args.p_data, {name: 'Tablet', platform: 'ios'});
  assert.equal((await route({units: []}).GET(new Request('https://vinha.test/api/kids-station?unit=' + unit))).status, 403, 'igreja fora do acesso');
  assert.equal((await ok.POST(post({action: 'register', data: {name: 'Tablet', platform: 'ios'}, org: id}))).status, 400);
  const revoked = route({data: null, error: {code: '42501', message: 'kids_station_revoked internal'}}),
    r = await revoked.POST(post({action: 'heartbeat', id}));
  assert.equal(r.status, 423);
  assert.doesNotMatch(JSON.stringify(await r.json()), /internal/);
});

test('banco: desativar encerra o login e o Kids recusa sessão encerrada', () => {
  const sql = readFileSync(new URL('../supabase/migrations/20261106140000_kids_estacoes_fuso.sql', import.meta.url), 'utf8');
  assert.match(sql, /delete from auth\.sessions where id=st\.session_id and user_id=st\.user_id/);
  assert.match(
    sql,
    /kids_op_allowed\(uuid,uuid,uuid,text,uuid\)'::regprocedure,' select auth\.uid\(\) is not null',' select auth\.uid\(\) is not null and private\.session_alive\(\)'/,
  );
  assert.match(sql, /revoke all on private\.kids_stations from public,anon,authenticated,service_role/);
  const ops = readFileSync(new URL('../app/KidsOperations.tsx', import.meta.url), 'utf8');
  assert.doesNotMatch(ops, /America\/Sao_Paulo|Horário local do dispositivo/, 'Kids mostra e edita no fuso da igreja');
  assert.match(readFileSync(new URL('../app/KidsDesk.tsx', import.meta.url), 'utf8'), /setPanelTimezone\(d\.timezone\)/);
});
