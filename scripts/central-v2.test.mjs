import assert from 'node:assert/strict';
import {existsSync, readdirSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';

const read = (p) => readFileSync(p, 'utf8');
const shell = read('app/admin-vinha/CentralShell.tsx');
const layout = read('app/admin-vinha/layout.tsx');
const migration = read('supabase/migrations/20261118090000_central_aplicativos.sql');

test('Central usa um menu único, agrupado, com operador e saída no topo', () => {
  assert.match(layout, /<AdminVinhaGate>\s*<CentralShell/);
  for (const g of ['Clientes', 'Aplicativos', 'Comercial', 'Financeiro', 'Atendimento', 'Automações', 'Vinha']) assert.ok(shell.includes(`title: '${g}'`), g);
  assert.match(shell, /\/admin-vinha\/aplicativos/);
  assert.match(shell, /\/api\/platform\/session/);
  assert.match(shell, /central-vinha\/login/);
  assert.match(shell, /aria-current=\{i\.href === current \? 'page'/);
  for (const f of ['ChatNavigation.tsx', 'TrialNavigation.tsx', 'financeiro-integracoes/FinancialNavigation.tsx'])
    assert.equal(existsSync(join('app/admin-vinha', f)), false, f);
});

test('cada link do menu aponta para uma página que existe', () => {
  const hrefs = [...shell.matchAll(/href: '(\/admin-vinha[^']*)'/g)].map((m) => m[1]);
  assert.ok(hrefs.length >= 25);
  for (const h of hrefs) assert.ok(existsSync(join('app', h, 'page.tsx')), h);
});

test('páginas da Central não montam mais menu lateral próprio', () => {
  const pages = [];
  const walk = (d) => {
    for (const e of readdirSync(d, {withFileTypes: true})) {
      const p = join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name === 'page.tsx') pages.push(p);
    }
  };
  walk('app/admin-vinha');
  for (const p of pages) assert.doesNotMatch(read(p), /Administração SaaS/, p);
});

test('aplicativos: rotas exigem operador e a lista de build exige token forte', () => {
  const route = read('app/api/platform/apps/route.ts');
  assert.match(route, /export const GET = centralRoute/);
  assert.match(route, /export const PATCH = centralRoute/);
  assert.match(route, /origin/);
  assert.match(route, /boundedBody\(request, 6000\)/);
  const manifest = read('app/api/platform/apps/manifest/route.ts');
  assert.match(manifest, /VINHA_APPS_MANIFEST_TOKEN/);
  assert.match(manifest, /timingSafeEqual/);
  assert.match(manifest, /length\s*<\s*32|\.length >= 32|32/);
});

test('aplicativos: banco valida operador, segundo fator, conflito e tema', () => {
  assert.match(migration, /private\.has_aal2\(\)/);
  assert.match(migration, /array\['owner','admin'\]::public\.platform_operator_role\[\]/);
  assert.match(migration, /platform_apps_conflict/);
  assert.match(migration, /th not in\('light','dark'\)/);
  assert.match(migration, /update public\.organizations set app_theme=th/);
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all on function public\.platform_apps\(text,uuid,jsonb\) from public,anon/);
  const page = read('app/admin-vinha/aplicativos/page.tsx');
  assert.match(page, /method: 'PATCH'/);
  assert.match(page, /version: selected\.version/);
  assert.match(page, /disabled=\{!canEdit\}/);
});

test('app único: perfis vêm de brands/ e cada ministério tem seu canal de atualização', () => {
  const cfg = read('android-app/app.config.ts');
  assert.match(cfg, /readdirSync\(brandsDir\)/);
  assert.match(cfg, /slug: 'vinha-app'/);
  assert.match(cfg, /'expo-channel-name'/);
  assert.match(cfg, /userInterfaceStyle/);
  const brand = JSON.parse(read('android-app/brands/mpr.json'));
  assert.equal(brand.theme, 'dark');
  // O canal vem do app.config (production-<perfil>); um canal fixo no eas.json misturaria os ministérios.
  const eas = JSON.parse(read('android-app/eas.json'));
  for (const k of ['preview', 'production']) assert.equal(eas.build[k].channel, undefined, k);
  const wf = read('.github/workflows/apps-release.yml');
  assert.match(wf, /workflow_dispatch/);
  assert.match(wf, /production-\$perfil/);
  assert.match(wf, /VINHA_APP_ONLY: \$\{\{ inputs\.perfil \}\}/);
  assert.doesNotMatch(wf, /run:[^\n]*\$\{\{ inputs\./);
  assert.match(read('android-app/scripts/sync-ministry-apps.mjs'), /VINHA_APPS_MANIFEST_TOKEN/);
  // Servidores do Expo recebem perfil, projeto e banco público pelo eas.json do robô; nunca chave secreta.
  const envScript = read('android-app/scripts/eas-build-env.mjs');
  assert.match(envScript, /VINHA_APP_PROFILE: perfil/);
  assert.match(envScript, /sb_publishable_/);
  assert.match(wf, /node scripts\/eas-build-env\.mjs "\$perfil"/);
  const manifest = read('app/api/platform/apps/manifest/route.ts');
  assert.match(manifest, /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(manifest, /SECRET|SERVICE_ROLE/);
});

test('identidade do app só pela Central: painel e cadastro inicial apenas mostram', () => {
  const route = read('app/api/platform/apps/identity/route.ts');
  assert.match(route, /export const (GET|POST|PATCH) = centralRoute/);
  assert.match(route, /createSignedUploadUrl/);
  assert.match(route, /iconOk\(/);
  assert.match(read('app/lib/app-icon.ts'), /getUint32\(16\) === 1024/);
  const ui = read('app/admin-vinha/aplicativos/AppIdentity.tsx');
  for (const a of ["'identity'", "'logo'", "'opening'", "'icon'"]) assert.ok(ui.includes(a), a);
  assert.match(read('app/admin-vinha/aplicativos/page.tsx'), /<AppIdentity /);
  const settings = read('app/OrganizationSettings.tsx');
  assert.doesNotMatch(settings, /name="primaryColor"|name="accentColor"/);
  assert.match(settings, /institutional\.filter/);
  assert.match(settings, /AppIdentityView/);
  assert.match(read('app/api/organization-settings/route.ts'), /'appName','primaryColor','accentColor'/);
  const onboarding = read('app/onboarding/page.tsx');
  assert.doesNotMatch(onboarding, /name="appName"|name="primaryColor"|LogoField/);
  assert.doesNotMatch(read('app/MinistryMediaAdmin.tsx'), /Personalizar abertura/);
  assert.doesNotMatch(read('app/ConfigurationCenter.tsx'), /function Brand\(/);
  const m = read('supabase/migrations/20261118120000_central_identidade_app.sql');
  for (const k of ['identity_managed_by_vinha', 'opening_managed_by_vinha', 'platform_app_identity', 'vinha-app-assets']) assert.ok(m.includes(k), k);
  assert.match(read('android-app/scripts/sync-ministry-apps.mjs'), /a\.iconUrl/);
  assert.match(read('android-app/app.config.ts'), /profile\.icon\s*\?/);
});
