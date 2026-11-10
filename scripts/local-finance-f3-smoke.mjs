// Loopback only; synthetic users. No provider request, message or real charge.
import {localSupabaseConfig} from './local-supabase-config.mjs';import {randomUUID,randomBytes} from 'node:crypto';import assert from 'node:assert/strict';import {createClient} from '@supabase/supabase-js';import {createServerClient} from '@supabase/ssr';
if(process.argv[2]!=='--local-synthetic')throw Error('Use --local-synthetic.');
const cfg=localSupabaseConfig();assert.equal(cfg.API_URL,'http://127.0.0.1:54321');
const origin='http://127.0.0.1:4100',cookies=new Map(),slug='f3-http-'+randomUUID(),email=slug+'@example.invalid',password=randomBytes(32).toString('base64url');
const admin=createClient(cfg.API_URL,cfg.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}}),client=createServerClient(cfg.API_URL,cfg.PUBLISHABLE_KEY||cfg.ANON_KEY,{cookies:{getAll:()=>[...cookies].map(([name,value])=>({name,value})),setAll:values=>{for(const v of values)cookies.set(v.name,v.value)}}});
assert.equal((await admin.auth.admin.createUser({email,password,email_confirm:true})).error,null);assert.equal((await client.auth.signInWithPassword({email,password})).error,null);
assert.equal((await client.rpc('bootstrap_organization',{p_organization_name:'F3 HTTP — exclusivamente fictício',p_organization_slug:slug,p_headquarters_name:'Sede fictícia F3',p_full_name:'Operador fictício F3'})).error,null);
const headers=()=>({origin,cookie:[...cookies].map(([k,v])=>k+'='+encodeURIComponent(v)).join('; ')});
const boot=await fetch(origin+'/api/finance-f1?'+new URLSearchParams({tenant:slug,action:'bootstrap'}),{headers:headers()}),bootstrap=await boot.json();assert.equal(boot.status,200);const unit=bootstrap.units[0].id;
async function call(data,status=200){const r=await fetch(origin+'/api/finance-receivers?'+new URLSearchParams({tenant:slug,unit}),{method:data?'POST':'GET',headers:{...headers(),...(data?{'Content-Type':'application/json'}:{})},...(data?{body:JSON.stringify({unit,provider:'safe2pay',environment:'sandbox',...data})}:{})}),d=await r.json();assert.equal(r.status,status,d.error);assert.match(r.headers.get('cache-control'),/no-store/);return d}
assert.deepEqual((await call()).items,[]);
const opened=await call({action:'open'});assert.equal(opened.url,'https://safe2pay.com.br/');assert.equal((await call({action:'open'})).id,opened.id);let list=await call();assert.equal(list.items.length,1);assert.equal(list.items[0].status,'opening_external');assert.deepEqual(list.paymentMethodsEnabled,[]);
await call({action:'connect'},409);await call({action:'open',organizationId:randomUUID()},400);
await call({action:'revoke',version:1});list=await call();assert.equal(list.items[0].status,'revoked');assert.equal(list.events.length,2);assert.doesNotMatch(JSON.stringify(list),/ciphertext|access_token|refresh_token|verifier/);
const faked=await client.rpc('finance_receiver_server',{p_actor:randomUUID(),p_org:randomUUID(),p_unit:unit,p_action:'complete',p_data:{}});assert.ok(faked.error);
const anon=await fetch(origin+'/api/finance-receivers?unit='+unit);assert.equal(anon.status,401);
const badOrigin=await fetch(origin+'/api/finance-receivers?tenant='+slug,{method:'POST',headers:{...headers(),origin:'https://untrusted.invalid','Content-Type':'application/json'},body:JSON.stringify({unit,provider:'safe2pay',environment:'sandbox',action:'open'})});assert.equal(badOrigin.status,403);
console.log('F3 HTTP: sessão real local, abertura pendente idempotente, revogação, histórico, isolamento, prova falsa e origem inválida conferidos. Somente registros fictícios locais; nenhuma chamada ao provedor.');
