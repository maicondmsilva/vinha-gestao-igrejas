import test from 'node:test';
import assert from 'node:assert/strict';
import {pushBatches, sendPushBatch, processPushQueue} from '../app/lib/push-campaigns.ts';
import {pushCommand} from '../app/lib/push-command.ts';

const job = (i, project = 'p1') => ({id: '00000000-0000-4000-8000-' + String(i).padStart(12, '0'), token: 'ExpoPushToken[t' + i + ']', project, title: 'Culto', body: 'Hoje às 19h', data: {screen: 'agenda'}});

test('lotes de até 100 mensagens, sem misturar projetos da Expo', () => {
  const jobs = [...Array.from({length: 150}, (_, i) => job(i)), ...Array.from({length: 3}, (_, i) => job(200 + i, 'p2'))];
  const batches = pushBatches(jobs);
  assert.deepEqual(batches.map((b) => b.length), [100, 50, 3]);
  assert.ok(batches.every((b) => new Set(b.map((j) => j.project)).size === 1));
});

test('envio em lote mapeia cada resposta para sua mensagem', async () => {
  const batch = [job(1), job(2)];
  let body;
  const r = await sendPushBatch(batch, async (_u, o) => {
    body = JSON.parse(o.body);
    assert.equal(o.redirect, 'error');
    return Response.json({data: [{status: 'ok', id: 'ticket-1'}, {status: 'error', details: {error: 'DeviceNotRegistered'}}]});
  }, 'token');
  assert.equal(body.length, 2);
  assert.equal(body[0].title, 'Culto');
  assert.deepEqual(body[0].data, {screen: 'agenda'});
  assert.deepEqual(r, [
    {id: batch[0].id, state: 'submitted', ticket: 'ticket-1'},
    {id: batch[1].id, state: 'failed', error: 'DeviceNotRegistered'},
  ]);
});

test('limite de taxa mantém na fila; erro do servidor fica incerto (sem reenvio cego)', async () => {
  assert.deepEqual((await sendPushBatch([job(1)], async () => new Response('', {status: 429})))[0].state, 'queued');
  assert.deepEqual((await sendPushBatch([job(1)], async () => new Response('', {status: 502})))[0].state, 'uncertain');
  assert.deepEqual((await sendPushBatch([job(1)], async () => Response.json({data: []})))[0].state, 'uncertain');
  await assert.rejects(sendPushBatch([job(1), job(2, 'p2')], async () => Response.json({})));
});

test('ciclo do processador: materializa, envia em lotes e registra resultados', async () => {
  const calls = [];
  let claims = 0;
  const rpc = async (action, data) => {
    calls.push(action);
    if (action === 'materialize') return {runs: 1};
    if (action === 'receipts') return {items: []};
    if (action === 'claim') return {items: claims++ === 0 ? Array.from({length: 120}, (_, i) => job(i)) : []};
    if (action === 'settle') {
      assert.equal(data.items.length, 120);
      return {ok: true};
    }
  };
  let requests = 0;
  const summary = await processPushQueue(rpc, {
    transport: async (_u, o) => (requests++, Response.json({data: JSON.parse(o.body).map((_, i) => ({status: 'ok', id: 'k' + i}))})),
  });
  assert.equal(requests, 2);
  assert.equal(summary.submitted, 120);
  assert.deepEqual(calls, ['materialize', 'receipts', 'claim', 'settle', 'claim', 'materialize']);
});

test('validação do painel recusa comandos malformados', () => {
  const unit = '00000000-0000-4000-8000-000000000001';
  assert.ok(pushCommand({unit, action: 'list', data: {}}));
  assert.ok(pushCommand({unit, action: 'preview', data: {targets: [unit], audience: {}}}));
  assert.equal(pushCommand({unit, action: 'create', data: {title: 'Oi', body: 'Texto', targets: [unit]}}), null, 'sem request');
  assert.equal(pushCommand({unit, action: 'create', data: {title: 'x'.repeat(66), body: 'Texto', targets: [unit], request: unit}}), null);
  assert.equal(pushCommand({unit, action: 'edit', id: unit, data: {title: 'Oi', body: 'Texto', targets: [unit]}}), null, 'sem versão');
  assert.equal(pushCommand({unit, action: 'drop', data: {}}), null);
  assert.equal(pushCommand({unit, action: 'list', data: {}, extra: 1}), null);
});

test('processador usa segredo próprio (não libera os crons da Central) e o banco agenda a cada minuto', async () => {
  const {readFileSync} = await import('node:fs');
  const route = readFileSync(new URL('../app/api/push/run/route.ts', import.meta.url), 'utf8'),
    sql = readFileSync(new URL('../supabase/migrations/20261106080000_push_campanhas.sql', import.meta.url), 'utf8');
  assert.match(route, /process\.env\.PUSH_CRON_SECRET/);
  assert.doesNotMatch(route, /process\.env\.CRON_SECRET/);
  assert.match(route, /timingSafeEqual/);
  assert.match(sql, /cron\.schedule\('vinha-push-every-minute','\* \* \* \* \*'/);
  assert.match(sql, /vault\.decrypted_secrets where name='vinha_cron_secret'/);
  assert.match(sql, /grant execute on function public\.push_engine\(text,jsonb\) to service_role/);
});
