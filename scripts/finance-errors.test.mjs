import test from 'node:test';
import assert from 'node:assert/strict';
import {financeReason} from '../app/lib/finance-errors.ts';

test('motivos conhecidos do banco viram mensagens claras', () => {
  assert.match(financeReason('period_closed'), /mês já foi fechado/);
  assert.match(financeReason('invalid_account'), /conta escolhida/);
  assert.match(financeReason('opening_already_exists'), /saldo inicial/);
  assert.match(financeReason(' entry_changed '), /Atualize/);
});

test('motivos desconhecidos ou internos não vazam para a tela', () => {
  for (const x of ['', null, undefined, 'unexpected_f1_definition', 'constructor', 'toString', '__proto__', 'duplicate key value violates unique constraint "x"']) assert.equal(financeReason(x), null);
});

test('rotas do financeiro usam a tradução antes da mensagem genérica', async () => {
  const {readFileSync} = await import('node:fs');
  for (const name of ['finance-f1', 'finance-f2', 'finance-digital', 'finance-revision']) {
    const source = readFileSync(new URL(`../app/api/${name}/route.ts`, import.meta.url), 'utf8');
    assert.match(source, /financeReason\([a-z.]*\)\|\|\(/, name);
  }
});
