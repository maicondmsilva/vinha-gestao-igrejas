import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync, existsSync} from 'node:fs';
import {
  chatCommandSchema,
  chatReadSchema,
  chatError,
  chatSignal,
  chatTopic,
  mergeChatMessages,
  chatLimits,
  chatReasons,
  chatReasonLabels,
} from '../shared/contract/chat.ts';
import {communicationPages} from '../shared/dashboard-menu.ts';

const room = '00000000-0000-4000-8000-000000000001',
  id = '00000000-0000-4000-8000-000000000002';
const sql = readFileSync('supabase/migrations/20261107050000_chat_comunidade.sql', 'utf8');

test('chat: comandos validados antes do banco', () => {
  assert.ok(chatCommandSchema.safeParse({action: 'send', data: {room, body: 'Bom dia', client: id}}).success);
  assert.equal(chatCommandSchema.safeParse({action: 'send', data: {room, body: '   ', client: id}}).success, false);
  assert.equal(chatCommandSchema.safeParse({action: 'send', data: {room, body: 'a'.repeat(chatLimits.body + 1), client: id}}).success, false);
  assert.equal(chatCommandSchema.safeParse({action: 'send', data: {room, body: 'oi', client: id, extra: 1}}).success, false);
  assert.equal(chatCommandSchema.safeParse({action: 'report', data: {room, id, reason: 'chato'}}).success, false);
  assert.ok(chatCommandSchema.safeParse({action: 'mute', data: {room, user: id, minutes: 60}}).success);
  assert.equal(chatCommandSchema.safeParse({action: 'mute', data: {room, user: id, minutes: 1.5}}).success, false);
  assert.ok(chatCommandSchema.safeParse({action: 'room_save', data: {unit: room, name: 'Geral', audience: 'members', posting: 'all'}}).success);
  assert.equal(chatCommandSchema.safeParse({action: 'room_save', data: {unit: room, name: 'G', audience: 'members', posting: 'all'}}).success, false);
  assert.equal(chatCommandSchema.safeParse({action: 'settings', data: {enabled: true, blockedWords: ['a'], version: 1}}).success, false);
  assert.equal(chatCommandSchema.safeParse({action: 'drop', data: {}}).success, false);
});

test('chat: leituras aceitas pela API', () => {
  assert.ok(chatReadSchema.safeParse({action: 'rooms'}).success);
  assert.ok(chatReadSchema.safeParse({action: 'messages', room, before: '2026-11-07T10:00:00.123456+00:00'}).success);
  assert.equal(chatReadSchema.safeParse({action: 'messages', room, before: 'ontem'}).success, false);
  assert.equal(chatReadSchema.safeParse({action: 'messages'}).success, false);
});

test('chat: erros do banco viram mensagens claras', () => {
  assert.equal(chatError('chat_adult_only')?.status, 403);
  assert.equal(chatError('ERROR: chat_blocked_word')?.field, 'body');
  assert.equal(chatError('chat_slow_down')?.status, 429);
  assert.equal(chatError('outra coisa'), null);
  for (const r of chatReasons) assert.ok(chatReasonLabels[r]);
});

test('chat: sinal de tempo real só leva ids', () => {
  assert.equal(chatTopic(room), 'chat:' + room);
  assert.deepEqual(chatSignal({event: 'chat', payload: {id, room, op: 'insert'}}), {id, room, op: 'insert'});
  assert.deepEqual(chatSignal({id, room, op: 'update'}), {id, room, op: 'update'});
  assert.equal(chatSignal({payload: {id: 'x', room}}), null);
  assert.equal(chatSignal(null), null);
  assert.ok(/jsonb_build_object\('id',new\.id,'room',new\.room_id,'op',lower\(tg_op\)\)/.test(sql), 'o aviso não leva o texto');
  assert.ok(sql.includes("realtime.topic() ~ '^chat:"), 'política do canal privado');
});

test('chat: lista na tela junta mensagens novas sem repetir', () => {
  const m = (i, t, body = 'x') => ({
    id: i,
    room,
    createdAt: t,
    mine: false,
    replyTo: null,
    sender: 'Ana',
    senderId: null,
    state: 'visible',
    body,
    hiddenReason: null,
    reports: null,
  });
  const a = m('a', '2026-11-07T10:00:00+00:00'),
    b = m('b', '2026-11-07T10:01:00+00:00');
  const out = mergeChatMessages([b], [a, {...b, state: 'hidden', body: ''}]);
  assert.deepEqual(
    out.map((x) => x.id),
    ['a', 'b'],
  );
  assert.equal(out[1].state, 'hidden');
});

test('chat: regras de proteção no banco', () => {
  assert.ok(sql.includes("interval '18 years'"), 'só adultos');
  assert.ok(sql.includes('chat_slow_down') && sql.includes("interval '30 seconds'"), 'limite de envio');
  assert.ok(sql.includes('n>=3'), 'três denúncias ocultam');
  assert.ok(sql.includes("'senderId',case when moderator then m.user_id end"), 'membro não vê o id de quem enviou');
  assert.ok(sql.includes('revoke all on private.chat_rooms'), 'tabelas sem acesso direto');
});

test('chat: endereço novo, fora do chat antigo, e aba no painel', () => {
  assert.ok(existsSync('app/api/community-chat/route.ts'));
  const route = readFileSync('app/api/community-chat/route.ts', 'utf8');
  assert.ok(route.includes("rpc('chat'") && !route.includes('withLegacyContainment'));
  assert.ok(communicationPages.some(([s]) => s === 'chat'));
  assert.ok(readFileSync('app/CommunicationWorkspace.tsx', 'utf8').includes("section==='chat'"));
});
