// Local browser QA fixture. Credential is accepted through stdin, never persisted.
import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
import {localSupabaseConfig} from './local-supabase-config.mjs';
if(process.argv[2]!=='--local-synthetic')throw Error('Preparação local exige --local-synthetic.');
const config=localSupabaseConfig();
if(process.stdin.isTTY)process.stdin.setRawMode(true);
console.log('Aguardando credencial fictícia por stdin; valores não serão exibidos.');
const lines=createInterface({input:process.stdin,terminal:false});
let input;for await(const line of lines){input=JSON.parse(line);lines.close();break}
if(process.stdin.isTTY)process.stdin.setRawMode(false);
if(!input||typeof input.email!=='string'||!/^visual-[a-z0-9-]+@example\.invalid$/.test(input.email)||typeof input.password!=='string'||input.password.length<24)throw Error('Dados de teste inválidos.');
const admin=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const created=await admin.auth.admin.createUser({email:input.email,password:input.password,email_confirm:true});
if(created.error)throw Error('Não foi possível criar conta fictícia local.');
const client=createClient(config.API_URL,config.PUBLISHABLE_KEY||config.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const signed=await client.auth.signInWithPassword(input);if(signed.error)throw Error('Login de preparação falhou.');
const slug='visual-local-'+randomUUID();
const boot=await client.rpc('bootstrap_organization',{p_organization_name:'Homologação visual — dados fictícios',p_organization_slug:slug,p_headquarters_name:'Sede visual de teste',p_full_name:'Operador visual sintético'});
if(boot.error)throw Error('Bootstrap local não confirmado.');
await client.auth.signOut();
console.log(JSON.stringify({email:input.email,slug,url:'http://127.0.0.1:4100/financeiro-piloto?tenant='+slug}));
