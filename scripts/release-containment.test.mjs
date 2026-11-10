import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, relative, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
import { pilotViewAllowed, releaseCatalog, withLegacyContainment } from '../app/lib/release-availability.ts';

const root = new URL('../', import.meta.url);
const rootPath = fileURLToPath(root);
function files(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? files(join(dir, entry.name)) : [join(dir, entry.name)]);
}

test('catalog fails closed for unknown views and distinguishes pilot from completed product', () => {
  assert.equal(new Set(releaseCatalog.map(x => x.id)).size, releaseCatalog.length);
  for (const id of ['inicio', 'pessoas', 'igrejas', 'configuracoes','usuarios','financeiro','eventos','comunicacao','transmissoes']) assert.equal(pilotViewAllowed(id), true);
  for (const id of ['louvor', 'missing', '']) assert.equal(pilotViewAllowed(id), false);
  assert.equal(pilotViewAllowed('kids'),true);
  assert.equal(releaseCatalog.find(x=>x.id==='kids').status,'validation');
  assert.equal(releaseCatalog.find(x=>x.id==='financeiro').status,'validation');
  assert.deepEqual(releaseCatalog.filter(x => x.status === 'ready').map(x=>x.id), ['celulas']);
  assert.equal(pilotViewAllowed('celulas'),true);
});

test('containment never executes legacy code, parses a body or requires credentials', async () => {
  let calls = 0;
  const guarded = withLegacyContainment(() => { calls++; throw new Error('must not execute'); });
  for (const method of ['GET', 'POST', 'PATCH', 'DELETE', 'PUT']) {
    const request = new Request('https://example.invalid/api/events', {
      method, ...(method === 'GET' ? {} : { body: 'not even json' }),
    });
    const response = await guarded(request, { params: Promise.resolve({ slug: 'unknown' }) });
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('x-vinha-availability'), 'development');
    assert.equal((await response.json()).code, 'FEATURE_NOT_RELEASED');
    assert.equal(request.bodyUsed, false);
  }
  assert.equal(calls, 0);
});

test('remaining legacy-only endpoints have guarded exports; reviewed migrations have no legacy path', () => {
  const exceptions = new Set(['app/api/people/route.ts', 'app/api/units/route.ts']);
  const apiFiles = files(join(rootPath, 'app/api')).filter(p => p.endsWith('route.ts'));
  let routes = 0, methods = 0;
  for (const path of apiFiles) {
    const content = readFileSync(path, 'utf8');
    if (!content.includes('env.DB')) continue;
    const name = relative(rootPath, path).replaceAll('\\', '/');
    if (exceptions.has(name)) {
      assert.match(content, /supabase/i, name + ': core adapter missing');
      assert.doesNotMatch(content, /withLegacyContainment/, name + ': core unexpectedly blocked');
      continue;
    }
    routes++;
    const source = ts.createSourceFile(path, content, ts.ScriptTarget.Latest, true);
    const imported = source.statements.find(node => ts.isImportDeclaration(node) &&
      node.moduleSpecifier.text.endsWith('lib/release-availability'));
    assert.ok(imported, name + ': missing containment import');
    assert.equal(resolve(dirname(path), imported.moduleSpecifier.text + '.ts'),
      resolve(rootPath, 'app/lib/release-availability.ts'), name + ': invalid import path');
    let exported = 0;
    for (const node of source.statements) {
      if (!node.modifiers?.some(m => m.kind === ts.SyntaxKind.ExportKeyword)) continue;
      // Any unreviewed export (including re-exports) must fail this release check.
      assert.ok(ts.isVariableStatement(node), name + ': unguarded export');
      for (const decl of node.declarationList.declarations) {
        assert.match(decl.name.getText(source), /^(GET|POST|PATCH|DELETE|PUT|HEAD|OPTIONS)$/);
        assert.ok(decl.initializer && ts.isCallExpression(decl.initializer), name);
        assert.equal(decl.initializer.expression.getText(source), 'withLegacyContainment', name);
        assert.equal(decl.initializer.arguments.length, 1, name);
        assert.equal(decl.initializer.arguments[0].getText(source), 'legacy' + decl.name.getText(source), name);
        exported++; methods++;
      }
    }
    assert.ok(exported > 0, name + ': no guarded method');
  }
  assert.equal(routes, 44);
  assert.equal(methods, 80);
  for(const route of ['onboarding/members-import','hierarchy/overview'])assert.doesNotMatch(readFileSync(join(rootPath,'app/api',route,'route.ts'),'utf8'),/env\.DB|withLegacyContainment/);
});

test('legacy page entrypoints are contained and the dashboard gates mounting', () => {
  const events=readFileSync(join(rootPath,'app/eventos/layout.tsx'),'utf8');assert.match(events,/canonicalEventPath\(location.pathname\)/);assert.match(events,/if\(!allowed\)return <UnavailableFeature/);
  for (const path of ['app-chat', 'app-notificacoes', 'app-voluntario', 'escalas', 'configuracoes/notificacoes', 'configuracoes/equipe-inicial']) {
    const content = readFileSync(join(rootPath, 'app', path, 'layout.tsx'), 'utf8');
    assert.match(content, /return <UnavailableFeature/);
    assert.doesNotMatch(content, /\{children\}/);
  }
  for(const path of ['vinculos','onboarding/importar-membros'])assert.doesNotMatch(readFileSync(join(rootPath,'app',path,'layout.tsx'),'utf8'),/UnavailableFeature/);
  assert.match(readFileSync(join(rootPath,'app/vinculos/permissoes/layout.tsx'),'utf8'),/UnavailableFeature/);
  const dashboard = readFileSync(join(rootPath, 'app/DashboardApp.tsx'), 'utf8');
  assert.match(dashboard, /<PilotModuleBoundary view=\{viewSlug\[active\]/);
  assert.match(dashboard, /<\/PilotModuleBoundary>/);
  assert.equal(existsSync(join(rootPath, 'app/teste/layout.tsx')), false, 'public trial terms must remain accessible');
  assert.match(readFileSync(join(rootPath, 'app/teste/termos/page.tsx'), 'utf8'), /Condições do período de teste/);
  const landing = readFileSync(join(rootPath, 'app/page.tsx'), 'utf8');
  assert.doesNotMatch(landing, /next\/link|<Link/);
  assert.match(landing, /<a className="site-login" href="\/login">Entrar<\/a>/);
});
