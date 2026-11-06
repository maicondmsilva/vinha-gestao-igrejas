import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('app oferece exclusão de conta dentro do aplicativo (App Store 5.1.1(v) / Google Play)', () => {
  const ui = read('android-app/src/AccountDeletion.tsx'),
    menu = read('android-app/src/MemberExperience.tsx');
  assert.match(menu, /<AccountDeletion palette=\{palette\}/);
  assert.match(ui, /\/api\/account\/close/);
  assert.match(ui, /Bearer ' \+ s\.data\.session\.access_token/);
  assert.match(ui, /'EXCLUIR'/);
  assert.doesNotMatch(ui, /service_role|SUPABASE_SECRET/);
});

test('rota de exclusão usa só a sessão do próprio usuário e exclusão suave', () => {
  const r = read('app/api/account/close/route.ts');
  assert.match(r, /auth\.getUser\(\)/);
  assert.match(r, /p_user: user\.id/);
  assert.match(r, /b\.confirm !== 'EXCLUIR'/);
  assert.match(r, /deleteUser\(user\.id, true\)/);
  assert.doesNotMatch(r, /p_user: b\.|body\.user|userId/);
});

test('banco bloqueia exclusão de papéis de governança e não expõe a função ao app', () => {
  const m = read('supabase/migrations/20261106050000_app_exclusao_de_conta.sql');
  assert.match(m, /role in\('owner','pastor','admin','finance'\)/);
  assert.match(m, /revoke all on function public\.account_close\(uuid,text\) from public,anon,authenticated/);
  assert.match(m, /status='revoked'/);
  assert.match(m, /member_push_devices set enabled=false/);
});

test('página web de exclusão existe para o link exigido pelo Google Play', () => {
  const p = read('app/conta/excluir/page.tsx');
  assert.match(p, /\/api\/account\/close/);
  assert.match(p, /via: 'web'/);
});

test('produção exige identificadores de loja do próprio ministério', () => {
  const c = read('android-app/app.config.ts');
  assert.match(c, /IOS_BUNDLE_IDENTIFIER/);
  assert.match(c, /ANDROID_APPLICATION_ID/);
  assert.match(c, /usesNonExemptEncryption: false/);
  assert.match(c, /runtimeVersion: \{policy: 'appVersion'\}/);
  assert.match(c, /\/\/ <ministry-imports>/);
});
