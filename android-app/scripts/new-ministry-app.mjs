#!/usr/bin/env node
// Creates a ministry app profile: brands/<perfil>.json + registration in app.config.ts.
// Usage: node scripts/new-ministry-app.mjs --perfil ipb --nome "IPB Igreja" --ministerio <uuid> --slug <slug-do-ministério>
// Store identifiers (ANDROID_APPLICATION_ID / IOS_BUNDLE_IDENTIFIER) come from the ministry's own store accounts
// and are set as EAS environment variables, never in this repository.
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const root = new URL('..', import.meta.url);
const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, value, i, all) => (value.startsWith('--') ? [...pairs, [value.slice(2), all[i + 1]]] : pairs), []),
);
const fail = (message) => {
  console.error(message);
  process.exit(1);
};
const perfil = String(args.perfil || ''),
  nome = String(args.nome || '').trim(),
  ministerio = String(args.ministerio || ''),
  slug = String(args.slug || '');
if (!/^[a-z][a-z0-9]{1,23}$/.test(perfil)) fail('--perfil: 2 a 24 letras minúsculas/números, começando por letra (ex.: ipb).');
if (nome.length < 2 || nome.length > 30) fail('--nome: nome exibido na tela do celular, até 30 caracteres.');
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(ministerio)) fail('--ministerio: UUID do ministério na Central Vinha.');
if (!/^[a-z0-9-]{3,120}$/.test(slug)) fail('--slug: identificador público do ministério (member_app_config).');
const brandFile = new URL(`brands/${perfil}.json`, root);
if (existsSync(brandFile)) fail(`O perfil ${perfil} já existe.`);
const configFile = new URL('app.config.ts', root);
let config = readFileSync(configFile, 'utf8');
for (const marker of ['// </ministry-imports>', '  // </ministry-profiles>'])
  if (!config.includes(marker)) fail('Marcadores de ministério não encontrados em app.config.ts.');
const appSlug = nome.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
writeFileSync(
  brandFile,
  JSON.stringify(
    {
      name: nome,
      slug: appSlug,
      ministryId: ministerio,
      ministrySlug: slug,
      previewApplicationId: `com.vinha.${perfil}.preview`,
      previewBundleIdentifier: `com.vinha.${perfil}.preview`,
    },
    null,
    1,
  ) + '\n',
);
config = config
  .replace('// </ministry-imports>', `import ${perfil} from './brands/${perfil}.json';\n// </ministry-imports>`)
  .replace('  // </ministry-profiles>', `  ${perfil},\n  // </ministry-profiles>`);
writeFileSync(configFile, config);
console.log(`Perfil ${perfil} criado em ${fileURLToPath(brandFile)}.
Próximos passos:
  1. Ícones do ministério em assets/${perfil}/ e "icon" no JSON, se houver arte própria.
  2. No EAS: VINHA_APP_PROFILE=${perfil}, ANDROID_APPLICATION_ID e IOS_BUNDLE_IDENTIFIER das contas do ministério.
  3. eas build --profile preview --platform all   (teste interno)
  4. eas build --profile production --platform all && eas submit --profile production --platform all`);
