import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
// Compile only: no deploy, no remote project, no credentials required.
const env={...process.env,VERCEL:'1',NEXT_PUBLIC_VINHA_ENV:'local',NEXT_PUBLIC_SUPABASE_URL:'http://127.0.0.1:54321',VINHA_PROVIDER_MODE:'sandbox'};
for(const key of ['VERCEL_ENV','SUPABASE_SECRET_KEY','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_ACCESS_TOKEN','DATABASE_URL','POSTGRES_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY'])delete env[key];
const result=spawnSync(process.execPath,['node_modules/vite/bin/vite.js','build'],{cwd:fileURLToPath(new URL('../',import.meta.url)),env,stdio:'inherit'});
process.exitCode=result.status??1;
