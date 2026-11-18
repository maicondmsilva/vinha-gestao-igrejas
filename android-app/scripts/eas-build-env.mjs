#!/usr/bin/env node
// O app é gerado nos servidores do Expo, que não recebem o ambiente do robô. Este passo grava no eas.json
// (só na cópia do robô, nunca no repositório) o perfil do ministério, o projeto e o endereço público do banco.
// Uso: node scripts/eas-build-env.mjs <perfil> [androidId] [iosId]
import {readFileSync, writeFileSync} from 'node:fs';

const [perfil, android = '', ios = ''] = process.argv.slice(2);
if (!/^[a-z][a-z0-9]{1,23}$/.test(perfil || '')) throw Error('Perfil inválido.');
const need = ['EXPO_PROJECT_ID', 'EXPO_PUBLIC_SUPABASE_URL', 'EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY'];
for (const k of need) if (!process.env[k]) throw Error(`Falta ${k} no ambiente do robô.`);
if (!/^sb_publishable_/.test(process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY)) throw Error('Use somente a chave pública.');
const file = new URL('../eas.json', import.meta.url);
const eas = JSON.parse(readFileSync(file, 'utf8'));
const env = {VINHA_APP_PROFILE: perfil, ...Object.fromEntries(need.map((k) => [k, process.env[k]]))};
for (const p of ['preview', 'production']) {
  eas.build[p].env = {...(eas.build[p].env || {}), ...env, ...(android ? {ANDROID_APPLICATION_ID: android} : {}), ...(ios ? {IOS_BUNDLE_IDENTIFIER: ios} : {})};
}
writeFileSync(file, JSON.stringify(eas, null, 2) + '\n');
console.log(`Ambiente do app ${perfil} preparado.`);
