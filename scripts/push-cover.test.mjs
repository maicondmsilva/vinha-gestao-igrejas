import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {sendPushBatch} from '../app/lib/push-campaigns.ts';
import {pushCampaignSchema, pushImageUrl} from '../shared/contract/push.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const img = '11111111-2222-4333-8444-555555555555';

test('push com capa leva a imagem grande ao Expo', async () => {
  let sent;
  const transport = async (_u, init) => {
    sent = JSON.parse(init.body);
    return new Response(JSON.stringify({data: sent.map(() => ({status: 'ok', id: 'tk'}))}), {status: 200});
  };
  const job = (data) => ({id: 'a', token: 'ExpoPushToken[x]', project: 'p', title: 'Culto', body: 'Hoje', data});
  await sendPushBatch([job({screen: 'inbox', image: img})], transport);
  assert.deepEqual(sent[0].richContent, {image: pushImageUrl(img)});
  await sendPushBatch([job({screen: 'inbox'})], transport);
  assert.equal(sent[0].richContent, undefined);
  await sendPushBatch([job({screen: 'inbox', image: 'javascript:alert(1)'})], transport);
  assert.equal(sent[0].richContent, undefined, 'só id de imagem');
});

test('contrato aceita capa e agendamento', () => {
  const base = {title: 'Culto', body: 'Hoje às 19h', targets: [img], link: {screen: 'inbox', image: img}};
  assert.ok(pushCampaignSchema.safeParse({...base, mode: 'schedule', sendAt: new Date(Date.now() + 864e5).toISOString()}).success);
  assert.ok(!pushCampaignSchema.safeParse({...base, link: {screen: 'inbox', image: 'x'}}).success);
});

test('telas: capa e públicos salvos no painel e no Vinha Equipe', () => {
  const panel = read('app/PushCampaigns.tsx'),
    staff = read('staff-app/src/PushComposer.tsx');
  assert.match(panel, /<ImageLibrary\s/);
  assert.match(panel, /Salvar este público/);
  assert.match(staff, /Públicos salvos/);
  assert.match(staff, /Agendar envio/);
  assert.match(staff, /pushRoles/);
  assert.match(read('supabase/migrations/20261115140000_push_capa_publicos.sql'), /c\.status in\('scheduled','sending','sent'\)/);
});

test('evento avisa no app, avisos por grupo e salas/turmas excluíveis no painel', () => {
  const rd = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
  assert.match(rd('app/ProgrammingDetail.tsx'), /Avisar no app/);
  assert.match(rd('app/PushCampaigns.tsx'), /get\('evento'\)/);
  assert.match(rd('app/PublishingWorkspace.tsx'), /Quem vê no app/);
  assert.match(rd('app/PublishingWorkspace.tsx'), /\/api\/publishing\/audience/);
  const sql = rd('supabase/migrations/20261116120000_publicacoes_por_grupos.sql');
  assert.match(sql, /viewer_in_groups/);
  assert.match(sql, /grant execute on function public\.publishing_audience/);
  assert.match(rd('app/KidsOperations.tsx'), /removeSpace\('room'/);
  assert.match(rd('app/api/kids/setup/route.ts'), /'room_delete', 'class_delete'/);
});
