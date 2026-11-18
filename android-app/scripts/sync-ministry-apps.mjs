#!/usr/bin/env node
// Sincroniza os perfis de ministério com a Central da Vinha (Aplicativos).
// Busca a lista dos apps liberados e cria/atualiza brands/<perfil>.json, mantendo a arte própria ("icon") já definida.
// Uso: VINHA_APPS_MANIFEST_URL=https://app.vinhaigrejas.com.br/api/platform/apps/manifest VINHA_APPS_MANIFEST_TOKEN=... node scripts/sync-ministry-apps.mjs
// Saída: lista de perfis em profiles.txt (um por linha) para o robô gerar ou atualizar cada app.
import {appendFileSync, existsSync, readFileSync, writeFileSync} from 'node:fs';

const url = process.env.VINHA_APPS_MANIFEST_URL || 'https://app.vinhaigrejas.com.br/api/platform/apps/manifest';
const token = process.env.VINHA_APPS_MANIFEST_TOKEN || '';
if (token.length < 32) {
  console.error('Defina VINHA_APPS_MANIFEST_TOKEN (segredo com 32+ caracteres).');
  process.exit(1);
}
const only = process.env.VINHA_APP_ONLY || '';
const r = await fetch(url, {headers: {Authorization: 'Bearer ' + token}});
if (!r.ok) {
  console.error('Central indisponível: HTTP ' + r.status);
  process.exit(1);
}
const {apps, supabase} = await r.json();
if (!Array.isArray(apps)) {
  console.error('Resposta inválida da Central.');
  process.exit(1);
}
const slugify = (s) =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
const done = [];
for (const a of apps) {
  if (!/^[a-z][a-z0-9]{1,23}$/.test(a.profile || '') || (only && a.profile !== only)) continue;
  const file = new URL(`../brands/${a.profile}.json`, import.meta.url);
  const previous = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
  const brand = {
    ...previous,
    name: String(a.name).slice(0, 30),
    slug: previous.slug || slugify(a.name) || a.profile,
    ministryId: a.ministryId,
    ministrySlug: a.ministrySlug,
    theme: a.theme === 'light' ? 'light' : 'dark',
    previewApplicationId: previous.previewApplicationId || `com.vinha.${a.profile}.preview`,
    previewBundleIdentifier: previous.previewBundleIdentifier || `com.vinha.${a.profile}.preview`,
  };
  writeFileSync(file, JSON.stringify(brand, null, 1) + '\n');
  done.push(a.profile + (a.androidApplicationId ? '|' + a.androidApplicationId : '|') + (a.iosBundleId ? '|' + a.iosBundleId : '|') + '|' + a.status);
}
// Endereço e chave públicos do banco para o app gerado (no robô vão para o ambiente dos próximos passos).
if (supabase && /^https:\/\/[a-z0-9]+\.supabase\.co$/.test(supabase.url) && /^sb_publishable_[A-Za-z0-9_-]+$/.test(supabase.publishableKey)) {
  if (process.env.GITHUB_ENV)
    appendFileSync(process.env.GITHUB_ENV, `EXPO_PUBLIC_SUPABASE_URL=${supabase.url}\nEXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${supabase.publishableKey}\n`);
} else {
  console.error('A Central não informou o endereço público do banco.');
  process.exit(1);
}
writeFileSync(new URL('../profiles.txt', import.meta.url), done.join('\n') + (done.length ? '\n' : ''));
console.log(`${done.length} app(s) sincronizado(s): ${done.map((d) => d.split('|')[0]).join(', ') || 'nenhum'}`);
