import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {localSupabaseConfig} from './local-supabase-config.mjs';
const cwd=fileURLToPath(new URL('../',import.meta.url));
const config=localSupabaseConfig();
if(config.API_URL!=='http://127.0.0.1:54321'||!(config.PUBLISHABLE_KEY||config.ANON_KEY))throw Error('Recusado: configuração não é o Supabase local esperado.');
// Keys stay in process memory. Never write .env files or print credentials.
const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:config.API_URL,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:config.PUBLISHABLE_KEY||config.ANON_KEY,SUPABASE_SECRET_KEY:config.SECRET_KEY,SUPABASE_SERVICE_ROLE_KEY:config.SERVICE_ROLE_KEY,NEXT_PUBLIC_VINHA_ENV:'local',VINHA_LEDGER_PILOT:'true',VINHA_PROVIDER_MODE:'sandbox',NODE_ENV:'development',VERCEL:'1'};
delete env.VERCEL_ENV;
console.log('Vinha local: http://127.0.0.1:4100 — banco Docker, sem publicação.');
const child=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','4100','--strictPort'],{cwd,env,stdio:'inherit'});
child.on('error',()=>{console.error('Não foi possível iniciar o servidor local.');process.exitCode=1});
child.on('exit',code=>{process.exitCode=code??1});
process.on('SIGINT',()=>child.kill('SIGINT'));
process.on('SIGTERM',()=>child.kill('SIGTERM'));
