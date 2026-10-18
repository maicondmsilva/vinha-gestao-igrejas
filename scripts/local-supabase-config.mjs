import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
export function localSupabaseConfig(){
 const result=spawnSync('powershell.exe',['-NoProfile','-Command','& .\\node_modules\\.bin\\supabase.cmd status -o json 2>$null'],{cwd:fileURLToPath(new URL('../',import.meta.url)),encoding:'utf8',stdio:['ignore','pipe','pipe']});
 let config;try{config=JSON.parse(result.stdout||'')}catch{throw Error('Não foi possível consultar o Supabase local; nenhum segredo será exibido.')}
 // CLI may report stopped optional services with a nonzero exit while returning
 // valid local configuration. Do not confuse that with DB/Auth availability.
 if(config.API_URL!=='http://127.0.0.1:54321'||!(config.PUBLISHABLE_KEY||config.ANON_KEY))throw Error('Recusado: somente Supabase local fixo é permitido.');
 return config;
}
