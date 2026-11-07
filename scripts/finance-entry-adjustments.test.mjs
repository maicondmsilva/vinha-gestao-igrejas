import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../app/FinanceModule.tsx', import.meta.url), 'utf8');

test('lançamento com juros, multa ou taxa nasce previsto e é baixado pela regra de Receber/Pagar', () => {
  assert.match(source, /withAdjust=adjustable&&adjCents\.interest\+adjCents\.fine\+adjCents\.fee>BigInt\(0\),paid=withAdjust\?'':paidDate/);
  assert.match(source, /if\(created&&withAdjust\)await settleWithAdjustments\(/);
  assert.match(source, /action:'settle'/);
  assert.match(source, /feeCategory:adjCents\.fee>BigInt\(0\)\?o\.feeCategory:''/);
});

test('ajustes só aparecem em lançamento avulso já pago ou recebido, fora do extrato', () => {
  assert.match(source, /const adjustable=\['income','expense'\]\.includes\(entryKind\)&&entryFrequency==='single'&&realized&&!ofxDraft;/);
});

test('competência, centro de custo e frequência ficam visíveis (sem "Mais opções")', () => {
  assert.doesNotMatch(source, /f1-more-options/);
  assert.match(source, /className="f2-frequency"/);
});
