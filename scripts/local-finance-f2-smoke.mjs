// Fixed loopback endpoints, synthetic accounts only. No external sends or charges.
import {localSupabaseConfig} from './local-supabase-config.mjs';import {randomUUID,randomBytes} from 'node:crypto';import assert from 'node:assert/strict';import {createClient} from '@supabase/supabase-js';import {createServerClient} from '@supabase/ssr';
if(process.argv[2]!=='--local-synthetic')throw Error('Use --local-synthetic.');
const cfg=localSupabaseConfig();assert.equal(cfg.API_URL,'http://127.0.0.1:54321');
const origin='http://127.0.0.1:4100',cookies=new Map(),slug='f2-http-'+randomUUID(),email=slug+'@example.invalid',password=randomBytes(32).toString('base64url');
const admin=createClient(cfg.API_URL,cfg.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}}),client=createServerClient(cfg.API_URL,cfg.PUBLISHABLE_KEY||cfg.ANON_KEY,{cookies:{getAll:()=>[...cookies].map(([name,value])=>({name,value})),setAll:values=>{for(const v of values)cookies.set(v.name,v.value)}}});
assert.equal((await admin.auth.admin.createUser({email,password,email_confirm:true})).error,null);assert.equal((await client.auth.signInWithPassword({email,password})).error,null);
const boot=await client.rpc('bootstrap_organization',{p_organization_name:'F2 HTTP — exclusivamente fictício',p_organization_slug:slug,p_headquarters_name:'Sede fictícia F2',p_full_name:'Operador fictício F2'});assert.equal(boot.error,null);
const headers=()=>({origin,cookie:[...cookies].map(([k,v])=>k+'='+encodeURIComponent(v)).join('; ')});
async function call(action,data={},query={},status=200){const path=['entry','catalog','void','snapshot','bootstrap'].includes(action)?'/api/finance-f1':'/api/finance-f2';const read=['snapshot','bootstrap','history','activity'].includes(action),response=await fetch(origin+path+'?'+new URLSearchParams({tenant:slug,...query,...(action==='bootstrap'?{action:'bootstrap'}:{})}),{method:read?'GET':'POST',headers:{...headers(),...(!read?{'content-type':'application/json'}:{})},...(!read?{body:JSON.stringify({action,unitId:unit,data})}:{})});const result=await response.json();assert.equal(response.status,status,JSON.stringify({action,error:result.error}));return result}
let unit;unit=(await call('bootstrap')).units[0].id;const account=randomUUID(),income=randomUUID(),expense=randomUUID(),date=new Date().toLocaleDateString('sv-SE');
for(const [id,kind,name,direction]of [[account,'account','Caixa F2 HTTP',''],[income,'category','Receitas F2 HTTP','income'],[expense,'category','Despesas F2 HTTP','expense']])await call('catalog',{id,kind,name,direction,parent:'',shared:false,active:true,version:0,details:{}});
const title=randomUUID(),entry={id:title,kind:'income',amount:'100,00',description:'Recebível fictício HTTP',account,category:income,center:'',supplier:'',person:'',party:'Pessoa sem cadastro',method:'pix',notes:'',competence:date,due:date,paid:''};await call('entry',entry);
const pay={id:randomUUID(),title,version:1,principal:'40,00',interest:'1,00',fine:'2,00',discount:'3,00',fee:'1,00',feeCategory:expense,account,date,method:'pix',reason:'Parcial fictícia'};
await Promise.all([call('settle',pay),call('settle',pay)]);
const query={units:unit,from:date,to:date};let snapshot=await call('snapshot',{},query);assert.equal(snapshot.summary.receivable,'6000');assert.equal(snapshot.accounts[0].balanceCents,'3900');
let hist=await call('history',{}, {unit,title});assert.equal(hist.payments.length,1);assert.equal(hist.remaining,'6000');
await call('settle',{...pay,id:randomUUID()}, {},409);
await call('void',{id:title,version:2,reason:'Contorno fictício',date,requestId:randomUUID()}, {},400);
await call('void',{id:hist.payments[0].cashEntry,version:1,reason:'Contorno fictício',date,requestId:randomUUID()}, {},400);
// Independent simultaneous requests with the same version: exactly one wins.
const candidates=[{...pay,id:randomUUID(),version:2,principal:'30,00',interest:'0',fine:'0',discount:'0',fee:'0'},{...pay,id:randomUUID(),version:2,principal:'30,00',interest:'0',fine:'0',discount:'0',fee:'0'}];
const results=await Promise.all(candidates.map(async data=>{const r=await fetch(origin+'/api/finance-f2?tenant='+slug,{method:'POST',headers:{...headers(),'content-type':'application/json'},body:JSON.stringify({action:'settle',unitId:unit,data})});return r.status}));assert.deepEqual(results.sort(),[200,409]);
hist=await call('history',{}, {unit,title});assert.equal(hist.remaining,'3000');assert.equal(hist.payments.length,2);
const reverse={id:randomUUID(),settlement:pay.id,date,reason:'Estorno parcial fictício'};await call('reverse',reverse);await call('reverse',reverse);
hist=await call('history',{}, {unit,title});assert.equal(hist.remaining,'7000');snapshot=await call('snapshot',{},query);assert.equal(snapshot.accounts[0].balanceCents,'3000');
await call('reschedule',{id:randomUUID(),title,version:hist.version,due:date,reason:'Reagendamento fictício'});
const activity=await call('activity',{}, {unit,title,action:'activity'});assert.ok(activity.items.some(e=>e.changes.due_date));assert.ok(activity.items.every(e=>e.actorId));
const series={id:randomUUID(),mode:'installments',count:3,frequency:'monthly',entry:{...entry,id:randomUUID(),amount:'100,01',due:'2026-01-31'}};const scheduled=await call('series',series);await call('series',series);assert.deepEqual(scheduled.items.map(x=>x.amount),['3334','3334','3333']);assert.deepEqual(scheduled.items.map(x=>x.due),['2026-01-31','2026-02-28','2026-03-31']);
// Payable + explicit fee increases total outgoing, not the face value of principal.
const payable=randomUUID();await call('entry',{...entry,id:payable,kind:'expense',category:expense,amount:'20,00'});await call('settle',{...pay,id:randomUUID(),title:payable,version:1,principal:'20,00',interest:'0',fine:'0',discount:'0',fee:'1,00'});snapshot=await call('snapshot',{},query);assert.equal(snapshot.accounts[0].balanceCents,'900');assert.equal(snapshot.summary.payable,'0');
// Failure in fee classification must roll back the cash entry and principal entirely.
const another=randomUUID();await call('entry',{...entry,id:another});const before=await call('snapshot',{},query);await call('settle',{...pay,id:randomUUID(),title:another,feeCategory:income},{},400);assert.equal((await call('history',{}, {unit,title:another})).payments.length,0);assert.equal((await call('snapshot',{},query)).accounts[0].balanceCents,before.accounts[0].balanceCents);
assert.equal((await fetch(origin+'/api/finance-f2?unit='+unit+'&title='+title)).status,401);
await client.auth.signOut();console.log('F2 HTTP passed: partial/full settlements, fees, payable, concurrency, rollback, reversal, reschedule, installments and access. Local synthetic fixtures only.');
