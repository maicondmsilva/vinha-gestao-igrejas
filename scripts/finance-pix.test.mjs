import test from 'node:test';
import assert from 'node:assert/strict';
import {createDigitalPix} from '../app/lib/digital-checkout.ts';
import {sealReceiver, receiverContext} from '../app/lib/receiver-vault.ts';

const id = 'af500000-0000-4000-8000-000000000001',
  order = 'af500000-0000-4000-8000-000000000003',
  receiver = 'af500000-0000-4000-8000-000000000002';
process.env.FINANCE_RECEIVER_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
const connection = {
  org: id,
  unit: id,
  provider: 'mercado_pago',
  environment: 'sandbox',
  externalId: '123',
  beneficiaries: [id],
  sealed: sealReceiver({access_token: 'synthetic-only-not-real', user_id: '123'}, receiverContext(id, id, 'mercado_pago', 'sandbox')),
};
const now = Date.parse('2026-11-06T12:00:00Z');
const reservation = {
  id,
  order,
  receiver,
  gross: '10001',
  title: 'Livro fictício',
  name: 'Pessoa Fictícia da Silva',
  email: 'pix@example.test',
  expiresAt: new Date(now + 24 * 3600000).toISOString(),
  state: 'ready',
  methods: ['pix', 'card'],
};
const qr = '00020126580014br.gov.bcb.pix0136synthetic-key-only-for-tests5204000053039865406100.01';
const reply = (over = {}) => ({
  id: 987654321,
  collector_id: 123,
  external_reference: order,
  payment_method_id: 'pix',
  currency_id: 'BRL',
  transaction_amount: 100.01,
  status: 'pending',
  date_of_expiration: '2026-11-07T12:00:00.000+00:00',
  point_of_interaction: {transaction_data: {qr_code: qr, qr_code_base64: 'iVBORw0KGgoAAAANSUhEUg==', ticket_url: 'https://www.mercadopago.com.br/payments/987654321/ticket'}},
  ...over,
});
const origin = 'https://teste.vinhaigrejas.com.br';

test('Pix usa chave de idempotência do pedido, valor em centavos e o webhook do recebedor', async () => {
  let calls = 0;
  const result = await createDigitalPix(connection, reservation, origin, async (url, opts) => {
    calls++;
    assert.equal(url, 'https://api.mercadopago.com/v1/payments');
    assert.equal(opts.redirect, 'error');
    assert.equal(opts.headers['X-Idempotency-Key'], 'vinha-pix-' + order);
    const body = JSON.parse(opts.body);
    assert.equal(body.payment_method_id, 'pix');
    assert.equal(body.transaction_amount, 100.01);
    assert.equal(body.external_reference, order);
    assert.equal(body.notification_url, origin + '/api/finance-digital/webhook/' + receiver + '?environment=sandbox');
    assert.equal(body.payer.email, 'pix@example.test');
    assert.equal(Date.parse(body.date_of_expiration), Date.parse(reservation.expiresAt));
    return Response.json(reply());
  }, now);
  assert.equal(calls, 1);
  assert.equal(result.paymentId, '987654321');
  assert.equal(result.qrCode, qr);
  assert.match(result.qrImage, /^data:image\/png;base64,/);
  assert.equal(result.ticketUrl, 'https://www.mercadopago.com.br/payments/987654321/ticket');
});

test('Pix repetido gera exatamente a mesma chave (sem segunda cobrança)', async () => {
  const keys = [];
  const transport = async (_url, opts) => (keys.push(opts.headers['X-Idempotency-Key']), Response.json(reply()));
  await createDigitalPix(connection, reservation, origin, transport, now);
  await createDigitalPix(connection, reservation, origin, transport, now + 60000);
  assert.equal(keys.length, 2);
  assert.equal(keys[0], keys[1]);
});

test('Pix não é criado quando o pedido ou o recebedor não aceitam Pix', async () => {
  const never = async () => assert.fail('nenhuma chamada ao provedor');
  await assert.rejects(createDigitalPix(connection, {...reservation, methods: ['card']}, origin, never, now));
  await assert.rejects(createDigitalPix({...connection, methods: ['card']}, reservation, origin, never, now));
});

test('Pix respeita os limites de 30 minutos a 30 dias do provedor', async () => {
  const never = async () => assert.fail('nenhuma chamada ao provedor');
  await assert.rejects(createDigitalPix(connection, {...reservation, expiresAt: new Date(now + 20 * 60000).toISOString()}, origin, never, now));
  let expiration = '';
  await createDigitalPix(connection, {...reservation, expiresAt: new Date(now + 90 * 24 * 3600000).toISOString()}, origin, async (_u, opts) => {
    expiration = JSON.parse(opts.body).date_of_expiration;
    return Response.json(reply());
  }, now);
  assert.ok(Date.parse(expiration) - now <= 29 * 24 * 3600000);
});

test('Pix recusa resposta divergente do provedor', async () => {
  for (const over of [
    {collector_id: 999},
    {external_reference: id},
    {transaction_amount: 1},
    {payment_method_id: 'visa'},
    {currency_id: 'USD'},
    {status: 'rejected'},
    {point_of_interaction: {transaction_data: {qr_code: 'curto', qr_code_base64: 'abc'}}},
    {point_of_interaction: {transaction_data: {qr_code: qr, qr_code_base64: '<script>'}}},
  ])
    await assert.rejects(createDigitalPix(connection, reservation, origin, async () => Response.json(reply(over)), now));
});

test('Pix descarta link de pagamento fora do domínio do Mercado Pago', async () => {
  const result = await createDigitalPix(connection, reservation, origin, async () =>
    Response.json(reply({point_of_interaction: {transaction_data: {qr_code: qr, qr_code_base64: 'iVBORw0KGgo=', ticket_url: 'https://evil.example/pay'}}})), now);
  assert.equal(result.ticketUrl, '');
});

test('Pix diferencia recusa definitiva de resultado ambíguo', async () => {
  for (const [status, retry] of [[400, true], [401, true], [500, false]]) {
    try {
      await createDigitalPix(connection, reservation, origin, async () => Response.json({error: 'x'}, {status}), now);
      assert.fail('deveria recusar');
    } catch (e) {
      assert.equal(e.notSent, retry);
    }
  }
});
