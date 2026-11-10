import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {previewCumulativeProration} from '../app/lib/plan-proration-preview.ts';
import {exactProrationInteger,safeProrationNumber} from '../app/lib/proration-integer.ts';
import {readProrationCatalog,prorationCatalogPrice} from '../app/lib/proration-catalog.ts';
const id='dd000000-0000-4000-8000-000000000001',version='2026-10-18T12:00:00.123456Z';
function route({role='owner',gate=true,patch={},errorTable=null}={}){
 const calls=[],now=Date.now(),tables={
  saas_unit_contracts:{id,status:'active',updated_at:version,module_decisions:{kids:true}},
  saas_proration_cycles:{contract_updated_at:version,net_cents:10000,cycle_start:now-86400000,cycle_end:now+86400000,accumulated_numerator:'0',rounded_adjustment:'0',invoice_id:id},
  saas_plans:{id:'next',name:'Novo',active:true,billing_cycle:'monthly',base_price_cents:16000},
  saas_module_catalog:[{code:'kids',monthly_price_cents:1000}],saas_plan_modules:[{plan_id:'next',module_code:'kids',included:true}],...patch};
 const client={from(table){calls.push(table);const result={data:tables[table],error:table===errorTable?{message:'private database error'}:null};const chain={select(){return chain},eq(){return chain},limit(){return Promise.resolve(result)},maybeSingle(){return Promise.resolve(result)}};return chain}};
 class OperationError extends Error{constructor(message,status=400){super(message);this.status=status}}
 client.rpc=async()=>{calls.push('catalog_rpc');return{data:{plan:tables.saas_plans,modules:tables.saas_module_catalog,links:tables.saas_plan_modules},error:errorTable==='saas_plans'?{message:'private database error'}:null}};
 const centralRoute=handler=>async request=>{try{return Response.json(await handler(request,client,{role}),{headers:{'cache-control':'no-store'}})}catch(e){return Response.json({error:e.message},{status:e.status||500})}};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/platform/contracts/plan-preview/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replace(/export async function/g,'async function');
 const handlers=new Function('NextResponse','centralRoute','OperationError','ledgerPilotEnabled','uuidPattern','previewCumulativeProration','exactProrationInteger','safeProrationNumber','readProrationCatalog','prorationCatalogPrice','process',source+'\nreturn {GET};')({json:Response.json},centralRoute,OperationError,()=>gate,/^[0-9a-f-]{36}$/,previewCumulativeProration,exactProrationInteger,safeProrationNumber,readProrationCatalog,prorationCatalogPrice,{env:{VINHA_PLAN_PRORATION_PILOT:'true'}});
 return{...handlers,calls};
}
const request=()=>new Request(`http://127.0.0.1:4100/api/platform/contracts/plan-preview?contractId=${id}&nextPlanId=next`);
test('preview isolation gate refuses before querying any table',async()=>{const r=route({gate:false});assert.equal((await r.GET(request())).status,503);assert.equal(r.calls.length,0)});
test('non-manager cannot query preview context',async()=>{const r=route({role:'support'});assert.equal((await r.GET(request())).status,403);assert.equal(r.calls.length,0)});
test('valid preview is read-only and includes add-on once only',async()=>{const response=await route().GET(request());assert.equal(response.status,200);const body=await response.json();assert.equal(body.estimate.nextNetCents,'16000');assert.equal(body.confirmationAvailable,false);assert.match(response.headers.get('cache-control'),/no-store/)});
test('stale or missing cycle cannot produce a preview',async()=>{for(const cy of [null,{contract_updated_at:'stale'}])assert.equal((await route({patch:{saas_proration_cycles:cy}}).GET(request())).status,409)});
test('database failure never exposes raw error',async()=>{const response=await route({errorTable:'saas_plans'}).GET(request());assert.equal(response.status,503);assert.doesNotMatch(JSON.stringify(await response.json()),/private database/)});
test('null prices cannot silently become zero',async()=>{const response=await route({patch:{saas_plans:{id:'next',active:true,billing_cycle:'monthly',base_price_cents:null}}}).GET(request());assert.equal(response.status,409)});
test('large exact strings are preserved but rounded JSON integers refused',()=>{assert.equal(exactProrationInteger('9007199254740993'),'9007199254740993');for(const value of [null,true,'',9007199254740992,1.5])assert.throws(()=>exactProrationInteger(value));assert.throws(()=>safeProrationNumber('9007199254740993'))});
