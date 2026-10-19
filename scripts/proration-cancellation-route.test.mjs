import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {cancellationCommand} from '../app/lib/proration-cancellation-command.ts';
const id='a0000000-0000-4000-8000-000000000001',command={requestId:id,contractId:id,invoiceId:id,reason:'Cancelamento sintético'};
function route({gate=true,result={data:{...command,status:'cancelled'},error:null}}={}){
 const calls=[];
 class OperationError extends Error{constructor(message,status=400){super(message);this.status=status}}
 const client={rpc:async(name,args)=>{calls.push({name,args});return result}};
 const centralRoute=handler=>async request=>{try{return Response.json(await handler(request,client),{headers:{'cache-control':'no-store'}})}catch(e){return Response.json({error:e.message},{status:e.status||500})}};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/platform/contracts/cancel-invoice/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replace(/export async function/g,'async function');
 const handlers=new Function('NextResponse','centralRoute','OperationError','ledgerPilotEnabled','boundedBody','cancellationCommand','process',source+'\nreturn {POST};')({json:Response.json},centralRoute,OperationError,()=>gate,async request=>new Uint8Array(await request.arrayBuffer()),cancellationCommand,{env:{VINHA_PLAN_PRORATION_PILOT:'true'}});
 return{...handlers,calls};
}
const request=(body=command,origin='http://127.0.0.1:4100')=>new Request('http://127.0.0.1:4100/api/platform/contracts/cancel-invoice',{method:'POST',headers:{origin,'content-type':'application/json'},body:JSON.stringify(body)});
test('cancellation isolation gate stops before RPC',async()=>{const r=route({gate:false});assert.equal((await r.POST(request())).status,503);assert.equal(r.calls.length,0)});
test('cross-origin cancellation cannot call database',async()=>{const r=route();assert.equal((await r.POST(request(command,'https://evil.invalid'))).status,403);assert.equal(r.calls.length,0)});
test('invalid cancellation cannot call database',async()=>{const r=route();assert.equal((await r.POST(request({...command,reason:''}))).status,400);assert.equal(r.calls.length,0)});
test('successful internal cancellation has no external side effect or browser refund amount',async()=>{const r=route(),response=await r.POST(request({...command,refundCents:999}));assert.equal(response.status,200);assert.deepEqual(r.calls,[{name:'cancel_proration_invoice_pilot',args:{p_data:command}}]);assert.equal((await response.json()).providerCancellationCreated,false);assert.match(response.headers.get('cache-control'),/no-store/)});
test('denial and unverified result never claim cancellation',async()=>{for(const result of [{data:null,error:{code:'42501',message:'internal secret'}},{data:{...command,status:'open'},error:null}]){const r=route({result}),response=await r.POST(request());assert.ok(response.status>=400);assert.doesNotMatch(JSON.stringify(await response.json()),/internal secret/)} });
