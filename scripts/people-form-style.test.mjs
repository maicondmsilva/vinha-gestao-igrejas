import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = (f) => readFileSync(new URL('../' + f, import.meta.url), 'utf8');

test('formulário de pessoa usa letras legíveis', () => {
  const css = read('app/people-form.css');
  for (const m of css.matchAll(/font-size:(\d+)px/g)) assert.ok(Number(m[1]) >= 12, m[0]);
  assert.match(read('app/DashboardApp.tsx'), /className="modal member-modal pf"/);
});

test('ficha da pessoa usa o padrão', () => {
  assert.match(read('app/DashboardApp.tsx'), /className="person-profile pp"/);
  assert.match(read('app/people-form.css'), /\.pp h2\{[^}]*font-size:22px/);
});
