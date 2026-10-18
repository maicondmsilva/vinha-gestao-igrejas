// Opt-in, synthetic local fixtures only. Does not accept remote URLs or credentials.
import {localSupabaseConfig} from './local-supabase-config.mjs';
import {randomBytes,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {createServerClient} from '@supabase/ssr';
if(process.argv[2]!=='--local-synthetic')throw Error('Use --local-synthetic para autorizar dados fictícios no Docker local.');
const config=localSupabaseConfig();
assert.equal(config.API_URL,'http://127.0.0.1:54321','somente Supabase local fixo');
const origin='http://127.0.0.1:4100',cookies=new Map(),slug='piloto-local-'+randomUUID();
const admin=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const client=createServerClient(config.API_URL,config.PUBLISHABLE_KEY||config.ANON_KEY,{cookies:{getAll:()=>[...cookies].map(([name,value])=>({name,value})),setAll:values=>{for(const value of values)cookies.set(value.name,value.value)}}});
const email=slug+'@example.invalid',password=randomBytes(32).toString('base64url');
// No mail is sent; this account is synthetic, in the fixed local Auth service.
const created=await admin.auth.admin.createUser({email,password,email_confirm:true});assert.equal(created.error,null,'criação de conta local');
const signed=await client.auth.signInWithPassword({email,password});assert.equal(signed.error,null,'login local real');
const boot=await client.rpc('bootstrap_organization',{p_organization_name:'Homologação local sintética',p_organization_slug:slug,p_headquarters_name:'Sede teste local',p_full_name:'Operador sintético'});assert.equal(boot.error,null,'bootstrap com sessão local');
const units=await client.from('organization_units').select('id').eq('organization_id',boot.data);assert.equal(units.error,null);assert.equal(units.data.length,1);const unitId=units.data[0].id;
async function api(body,query={}){
 const response=await fetch(origin+'/api/church-ledger?'+new URLSearchParams({tenant:slug,...query}),{method:body?'POST':'GET',headers:{origin,cookie:[...cookies].map(([k,v])=>k+'='+encodeURIComponent(v)).join('; '),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
 const data=await response.json();assert.equal(response.status,200,'API local: '+(body?.action||'consulta')+' / '+String(data.error||''));return data;
}
const date=new Date().toISOString().slice(0,10),asset=await api({action:'account',unitId,name:'Caixa sintético',kind:'asset'}),income=await api({action:'account',unitId,name:'Ofertas sintéticas',kind:'income'});
const requestId=randomUUID(),post={action:'post',unitId,requestId,date,memo:'Teste HTTP local — sem valor real',debit:asset.id,credit:income.id,amount:'123,45'};
assert.equal((await api(post)).id,requestId);assert.equal((await api(post)).id,requestId);
let snapshot=await api(null,{unitId,date});assert.equal(snapshot.journals.length,1,'reenvio HTTP não duplica');assert.equal(snapshot.balances.find(a=>a.accountId===asset.id).balanceCents,'12345');
await api({action:'reverse',unitId,requestId:randomUUID(),date,memo:'Estorno do teste HTTP local',originalId:requestId});
snapshot=await api(null,{unitId,date});assert.equal(snapshot.journals.length,2);assert.equal(snapshot.balances.find(a=>a.accountId===asset.id).balanceCents,'0');
await client.auth.signOut();
console.log('PASS login local + bootstrap + contas + lançamento HTTP + repetição + estorno + saldo zero.');
console.log('Dados fictícios preservados exclusivamente no Docker local; nenhuma mensagem ou cobrança real.');
console.log('Referência do teste: '+slug);
