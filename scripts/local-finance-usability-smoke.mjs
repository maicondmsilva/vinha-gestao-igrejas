// HTTP + Storage on local Docker only. No external provider, real member or production database.
import {localSupabaseConfig} from './local-supabase-config.mjs';import {randomUUID,randomBytes} from 'node:crypto';import assert from 'node:assert/strict';import {createClient} from '@supabase/supabase-js';import {createServerClient} from '@supabase/ssr';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const c=localSupabaseConfig();assert.equal(c.API_URL,'http://127.0.0.1:54321');const origin='http://127.0.0.1:4100',slug='finance-ux-'+randomUUID(),email=slug+'@example.invalid',password=randomBytes(32).toString('base64url'),cookies=new Map();
const admin=createClient(c.API_URL,c.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}}),client=createServerClient(c.API_URL,c.PUBLISHABLE_KEY||c.ANON_KEY,{cookies:{getAll:()=>[...cookies].map(([name,value])=>({name,value})),setAll:rows=>{for(const row of rows)cookies.set(row.name,row.value)}}});
assert.equal((await admin.auth.admin.createUser({email,password,email_confirm:true})).error,null);assert.equal((await client.auth.signInWithPassword({email,password})).error,null);const bootstrap=await client.rpc('bootstrap_organization',{p_organization_name:'Financeiro UX exclusivamente fictício',p_organization_slug:slug,p_headquarters_name:'Sede fictícia UX',p_full_name:'Operador fictício'});assert.equal(bootstrap.error,null);
const headers=()=>({origin,cookie:[...cookies].map(([k,v])=>k+'='+encodeURIComponent(v)).join('; ')});
const boot=await fetch(origin+'/api/finance-f1?tenant='+slug+'&action=bootstrap',{headers:headers()}),bootData=await boot.json();assert.equal(boot.status,200);const unitId=bootData.units[0].id,bankId=randomUUID(),categoryId=randomUUID(),entryId=randomUUID();
async function command(data,status=200){const response=await fetch(origin+'/api/finance-f1?tenant='+slug,{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({unitId,...data})}),d=await response.json();assert.equal(response.status,status,d.error);return d}
const bank={id:bankId,kind:'account',name:'Banco fictício — conta operacional',direction:'',parent:'',shared:false,version:0,active:true,details:{bank:'Banco de teste',number:'Agência 0001 / Conta fictícia 123-4'}};
const category={id:categoryId,kind:'category',name:'Categoria fictícia UX',direction:'income',parent:'',shared:false,version:0,active:true,details:{description:'Não são dados de cliente'}};
await command({action:'catalog',data:bank});await command({action:'catalog',data:category});
const today=new Date().toLocaleDateString('sv-SE'),entry={id:entryId,kind:'income',description:'Lançamento fictício com comprovante',amount:'100,01',account:bankId,category:categoryId,competence:today,due:today,paid:today,method:'bank'};
await command({action:'entry',data:entry});
const url=origin+'/api/finance-f1/files?'+new URLSearchParams({tenant:slug,unitId,entryId});
async function upload(file){const body=new FormData();body.set('file',file);return fetch(url,{method:'POST',headers:headers(),body})}
assert.equal((await upload(new File(['<html>not pdf</html>'],'fake.pdf',{type:'application/pdf'}))).status,400);
const pdf='%PDF-1.7\nSynthetic local financial attachment. No real receipt.';
const uploaded=await upload(new File([pdf],'comprovante-ficticio.pdf',{type:'application/pdf'})),saved=await uploaded.json();assert.equal(uploaded.status,201,saved.error);assert.match(saved.name,/\.pdf$/);
const list=await fetch(url,{headers:headers()}),files=await list.json();assert.equal(list.status,200);assert.equal(files.items.length,1);assert.equal(files.items[0].name,saved.name);
const downloaded=await fetch(url+'&file='+encodeURIComponent(saved.name),{headers:headers()});assert.equal(downloaded.status,200);assert.match(downloaded.headers.get('cache-control'),/no-store/);assert.equal(downloaded.headers.get('x-content-type-options'),'nosniff');assert.equal(await downloaded.text(),pdf);
assert.equal((await fetch(url)).status,401);
assert.equal((await fetch(url.replace(unitId,randomUUID()),{headers:headers()})).status,403);
await command({action:'catalog',data:{...category,version:1,active:false}});
await command({action:'entry',data:{...entry,id:randomUUID(),description:'Não deve gravar categoria inativa'}},400);
await command({action:'catalog',data:{...category,version:2,active:true}});
await command({action:'catalog',data:{...category,version:2,active:false}},409);
await command({action:'catalog',data:{...category,version:3,name:'Categoria fictícia editada'}});
const query=new URLSearchParams({tenant:slug,units:unitId,from:today,to:today}),snapshot=await fetch(origin+'/api/finance-f1?'+query,{headers:headers()}),data=await snapshot.json();assert.equal(snapshot.status,200);assert.equal(data.entries.length,1);assert.equal(data.entries[0].id,entryId);assert.equal(data.catalog.find(x=>x.id===categoryId).name,'Categoria fictícia editada');assert.equal(data.catalog.find(x=>x.id===categoryId).active,true);assert.equal(data.catalog.find(x=>x.id===bankId).details.number,bank.details.number);
console.log('Financeiro UX local: conta bancária vinculada, comprovante privado enviado/listado/baixado, arquivo adulterado e acesso indevido recusados; categoria editada/desativada/reativada com conflito de versão e histórico preservados. Um único lançamento fictício. Nenhum provedor externo acessado.');
