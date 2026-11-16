import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {givingAmountsFromText, givingAmountsText, givingInk, givingMoney, givingPresets, givingSuggestions} from '../shared/giving.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('valores sugeridos: texto ↔ centavos', () => {
  assert.deepEqual(givingAmountsFromText('20, 50; 100'), [2000, 5000, 10000]);
  assert.deepEqual(givingAmountsFromText('12,50'), [1250]);
  assert.deepEqual(givingAmountsFromText(''), []);
  assert.equal(givingAmountsFromText('0,5'), null);
  assert.equal(givingAmountsFromText('1 2 3 4 5 6 7'), null);
  assert.equal(givingAmountsText([2000, 1250]), '20, 12,50');
  assert.equal(givingMoney(5000), 'R$ 50');
});

test('cores da Vinha e texto legível', () => {
  for (const c of givingPresets) assert.match(c, /^#[0-9a-f]{6}$/);
  assert.equal(givingInk('#285c45'), '#ffffff');
  assert.equal(givingInk('#f5e9c8'), '#14211b');
  assert.ok(givingSuggestions.some((s) => s.title === 'Dízimo'));
});

test('banco: cartões pela conta principal, painel e app', () => {
  const sql = read('supabase/migrations/20261116150000_cartoes_contribuicao.sql');
  assert.match(sql, /r\.is_primary and r\.environment='production'/);
  assert.match(sql, /grant execute on function public\.giving_admin/);
  assert.match(sql, /'cards',coalesce/);
  assert.match(read('app/lib/finance-f1.ts'), /\['contribua','Contribua no app'\]/);
  assert.match(read('app/FinanceModule.tsx'), /<GivingCardsAdmin unit=\{one\}\/>/);
  const app = read('android-app/src/ServicesScreen.tsx');
  assert.match(app, /<GivingCards /);
  assert.match(app, /await checkout\(id,unit\)/);
  assert.match(read('android-app/src/GivingCards.tsx'), /Destaques/);
});
