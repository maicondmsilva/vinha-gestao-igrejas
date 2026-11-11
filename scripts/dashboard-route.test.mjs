import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync, existsSync} from 'node:fs';
import {canonicalDashboardUrl, dashboardQuery, dashboardUrl} from '../shared/dashboard-route.ts';
import {programmingHref} from '../shared/programming.ts';
import {dashboardHref, programmingPages, communicationPages} from '../shared/dashboard-menu.ts';

test('Programação e Comunicação têm endereços próprios; outros módulos seguem com ?pagina=', () => {
  assert.equal(
    dashboardUrl('eventos', 'agenda', '?tenant=mpr&unidade=1&pagina=celulas&secao=redes&celula=x'),
    '/painel/programacao/agenda?tenant=mpr&unidade=1',
  );
  assert.equal(dashboardUrl('comunicacao', 'push', ''), '/painel/comunicacao/push');
  assert.equal(dashboardUrl('comunicacao', null, '?tenant=mpr'), '/painel/comunicacao?tenant=mpr');
  assert.equal(dashboardUrl('financeiro', 'geral', '?tenant=mpr'), '/painel?tenant=mpr&pagina=financeiro&secao=geral');
  assert.equal(dashboardUrl('eventos', '../admin', ''), '/painel/programacao', 'seção inválida não entra no caminho');
  assert.equal(programmingHref('vendas', '?unidade=1'), '/painel/programacao/vendas?unidade=1');
  assert.equal(dashboardHref('?unidade=1', 'kids', 'reports'), '/painel?unidade=1&pagina=kids&secao=reports');
});

test('o painel lê o módulo do caminho e aceita links antigos', () => {
  const q = dashboardQuery('/painel/programacao/agenda', '?unidade=1');
  assert.equal(q.get('pagina'), 'eventos');
  assert.equal(q.get('secao'), 'agenda');
  assert.equal(q.get('unidade'), '1');
  assert.equal(dashboardQuery('/painel/comunicacao', '').get('pagina'), 'comunicacao');
  assert.equal(dashboardQuery('/painel/comunicacao/push', '?pagina=financeiro').get('pagina'), 'financeiro', 'link interno de outro módulo vence');
  assert.equal(dashboardQuery('/painel/desconhecido/x', '').get('pagina'), null);
  assert.equal(canonicalDashboardUrl('/painel', '?pagina=eventos&secao=agenda&unidade=1'), '/painel/programacao/agenda?unidade=1');
  assert.equal(canonicalDashboardUrl('/painel/programacao/agenda', '?unidade=1'), null);
  assert.equal(canonicalDashboardUrl('/painel', '?pagina=financeiro'), null);
});

test('rotas existem e cada aba do topo é um endereço real', () => {
  for (const m of ['programacao', 'comunicacao']) {
    assert.ok(existsSync(new URL(`../app/painel/${m}/page.tsx`, import.meta.url)));
    assert.ok(existsSync(new URL(`../app/painel/${m}/[secao]/page.tsx`, import.meta.url)));
  }
  assert.ok(programmingPages.length >= 5 && !communicationPages.some(([id]) => id === 'equipe'), 'Equipe fica em Configurações › Usuários e permissões');
  const tabs = readFileSync(new URL('../app/ModuleTabs.tsx', import.meta.url), 'utf8');
  assert.match(tabs, /href=\{dashboardUrl\(page, id, search\)\}/);
  assert.match(tabs, /aria-current=\{current \? 'page' : undefined\}/);
  const app = readFileSync(new URL('../app/DashboardApp.tsx', import.meta.url), 'utf8');
  assert.match(app, /canonicalDashboardUrl\(location\.pathname,location\.search\)/);
  assert.match(app, /dashboardUrl\(viewSlug\[label\]\|\|'inicio',section,location\.search\)/);
});

test('identidade Vinha: cores do painel vêm dos tokens', () => {
  const css = readFileSync(new URL('../app/globals.css', import.meta.url), 'utf8');
  assert.match(css, /--green:var\(--color-vinha-brand\);--ink:var\(--color-vinha-ink\);--muted:var\(--color-vinha-muted\)/);
  for (const f of ['programming.css', 'publishing.css', 'event-module-layout.css'])
    assert.doesNotMatch(readFileSync(new URL('../app/' + f, import.meta.url), 'utf8'), /#285c45|#5f6f64|#dce6df/i, f);
});
