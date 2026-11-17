import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync, statSync} from 'node:fs';
import {join} from 'node:path';

// Contrato entre os apps e o banco: cada chamada .rpc('funcao', {p_...}) usa parâmetros que existem na
// definição mais recente da função pública nas migrações. Um nome errado (p_org em vez de p_organization)
// faz o servidor não encontrar a função e a tela falha sem explicação.
const root = new URL('..', import.meta.url).pathname;
const migrations = readdirSync(join(root, 'supabase/migrations'))
  .filter((f) => f.endsWith('.sql'))
  .sort();
const sigs = new Map();
for (const f of migrations) {
  const sql = readFileSync(join(root, 'supabase/migrations', f), 'utf8');
  for (const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\(([^)]*)\)/gi)) {
    const names = [...m[2].matchAll(/(?:^|,)\s*(p_\w+)\s/g)].map((x) => x[1]);
    const key = m[1] + '/' + m[2].split(',').filter((x) => x.trim()).length;
    const all = sigs.get(m[1]) || new Map();
    all.set(key, new Set(names));
    sigs.set(m[1], all);
  }
  for (const m of sql.matchAll(/drop\s+function\s+(?:if\s+exists\s+)?public\.(\w+)\s*\(([^)]*)\)/gi)) {
    const all = sigs.get(m[1]);
    if (all) all.delete(m[1] + '/' + m[2].split(',').filter((x) => x.trim()).length);
  }
}
function files(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    if (n === 'node_modules' || n.startsWith('.') || n === 'android' || n === 'ios') return [];
    return statSync(p).isDirectory() ? files(p) : /\.(ts|tsx)$/.test(n) && !n.startsWith('ZzPreview') ? [p] : [];
  });
}
/** Chaves do objeto literal no nível de cima (ignora objetos aninhados em p_data). */
function topKeys(src, start) {
  const keys = [];
  let depth = 0,
    i = start,
    token = '';
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === '{' || c === '[' || c === '(') depth++;
    else if (c === '}' || c === ']' || c === ')') {
      depth--;
      if (depth === 0) break;
    } else if (depth === 1) {
      if (/[\w$]/.test(c)) token += c;
      else {
        if ((c === ':' || c === ',') && /^p_\w+$/.test(token)) keys.push(token);
        if (!/\s/.test(c)) token = '';
      }
    }
  }
  if (/^p_\w+$/.test(token)) keys.push(token);
  return keys;
}

test('chamadas ao banco usam os nomes de parâmetro das funções', () => {
  const problems = [];
  let checked = 0;
  for (const f of [
    ...files(join(root, 'app')),
    ...files(join(root, 'shared')),
    ...files(join(root, 'staff-app/src')),
    ...files(join(root, 'android-app/src')),
  ]) {
    const src = readFileSync(f, 'utf8');
    for (const m of src.matchAll(/\.rpc\(\s*'(\w+)'\s*,\s*\{/g)) {
      const fn = m[1],
        all = sigs.get(fn);
      if (!all || !all.size) continue; // função de outro esquema ou criada fora das migrações públicas
      const keys = topKeys(src, m.index + m[0].length - 1);
      checked++;
      if (![...all.values()].some((names) => keys.every((k) => names.has(k))))
        problems.push(`${f.replace(root, '')}: ${fn}(${keys.join(', ')}) — esperado ${[...all.values()].map((s) => [...s].join(', ')).join(' | ')}`);
    }
  }
  assert.ok(checked > 100, 'chamadas conferidas: ' + checked);
  assert.deepEqual(problems, []);
});
