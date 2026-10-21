import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import ts from 'typescript';
import {boundedBody} from '../app/lib/private-files.ts';import {checkoutCommand,checkoutOrigin} from '../app/lib/digital-checkout.ts';
const id='af400000-0000-4000-8000-000000000001',body={unit:id,order:id,name:'Pessoa fictícia'};
process.env.FINANCE_CHECKOUT_ORIGIN='https://teste.vinhaigrejas.com.br';
function route(config={}){
 const calls=[];let reserves=0;
 const client={rpc:async(name,args)=>{calls.push({name,args});reserves++;return{data:{id,receiver:id,expired:config.expired||false},error:config.error||config.revoke&&reserves>1?{code:'42501'}:null}}};
 const authorizeSupabaseChurch=async()=>config.denied?{response:Response.json({}, {status:401})}:{access:{membership:{organization_id:'trusted-org',role:config.role||'owner',units:config.units||[{id}]},client}};
 const deps={authorizeSupabaseChurch,supabaseAdminClient:()=>client,boundedBody,checkoutCommand,checkoutOrigin,digitalConnection:async()=>({}),dispatchDigitalCheckout:async()=>{calls.push({dispatch:true});if(config.fail)throw Error('internal secret');return{state:'ready',checkoutUrl:'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=123'}}};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/finance-digital/checkout/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export async function ','async function ');
 return{...new Function(...Object.keys(deps),source+';return{POST}')( ...Object.values(deps)),calls};
}
const req=(d=body)=>new Request('https://untrusted.example/api/finance-digital/checkout',{method:'POST',body:JSON.stringify(d)});
test('checkout rota exige sessão, titular autorizado e unidade antes do banco',async()=>{for(const[c,status]of[[{denied:true},401],[{role:'finance'},403],[{role:'member'},403],[{units:[]},403]]){const r=route(c);assert.equal((await r.POST(req())).status,status);assert.equal(r.calls.length,0)}});
test('checkout rota não aceita valor ou recebedor escolhidos pelo navegador',async()=>{for(const extra of ['gross','receiver','org','email','status']){const r=route();assert.equal((await r.POST(req({...body,[extra]:'x'}))).status,400);assert.equal(r.calls.length,0)}});
test('checkout rota reserva no ministério da sessão e revalida antes de liberar link',async()=>{const r=route(),response=await r.POST(req());assert.equal(response.status,200);assert.equal(r.calls[0].args.p_org,'trusted-org');assert.equal(r.calls[0].name,'finance_checkout_reserve');assert.equal(r.calls.filter(x=>x.name==='finance_checkout_reserve').length,2);assert.match(response.headers.get('cache-control'),/no-store/)});
test('checkout acesso revogado durante chamada não revela link',async()=>{const r=route({revoke:true}),response=await r.POST(req());assert.equal(response.status,403);assert.equal(r.calls.filter(x=>x.dispatch).length,1);assert.doesNotMatch(JSON.stringify(await response.json()),/checkoutUrl|pref_id/)});
test('checkout erro ou expiração interrompe antes do provedor',async()=>{for(const c of [{error:true},{expired:true}]){const r=route(c),response=await r.POST(req());assert.ok([403,409].includes(response.status));assert.equal(r.calls.filter(x=>x.dispatch).length,0)}});
test('checkout falha externa não vaza credencial nem promete pagamento',async()=>{const r=route({fail:true}),response=await r.POST(req());assert.equal(response.status,503);const data=JSON.stringify(await response.json());assert.doesNotMatch(data,/internal secret|checkoutUrl/);assert.match(data,/Não há confirmação de pagamento/)});
