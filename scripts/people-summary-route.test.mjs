import test from 'node:test';import assert from 'node:assert/strict';import{readFileSync}from'node:fs';import ts from'typescript';
import{peopleSummary,summaryUnit}from'../app/lib/people-summary.ts';
const unit='11111111-1111-4111-8111-111111111111';
const result={unitId:unit,generatedAt:'2026-10-19T12:00:00Z',counts:{total:'0',members:'0',visitors:'0',integration:'0',other:'0'}};
function route({denied=false,units=[{id:unit}],error=null,data=result}={}){
 let calls=0;
 const client={rpc:async()=>{calls++;return{data,error}}};
 const authorize=async()=>denied?{response:Response.json({error:'denied'},{status:401})}:{access:{membership:{organization_id:'org-from-session',units},client}};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/reports/people/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replace('export async function GET','async function GET');
 return{get:new Function('NextResponse','authorizeSupabaseChurch','summaryUnit','peopleSummary',source+';return GET')({json:Response.json},authorize,summaryUnit,peopleSummary),calls:()=>calls};
}
const request=()=>new Request('https://example.test/api/reports/people?unitId='+unit);
test('relatório sem login ou unidade permitida não consulta banco',async()=>{for(const config of [{denied:true},{units:[]}]){const r=route(config);assert.ok([401,403].includes((await r.get(request())).status));assert.equal(r.calls(),0)}});
test('relatório exige seleção explícita antes da RPC',async()=>{const r=route();assert.equal((await r.get(new Request('https://example.test/'))).status,400);assert.equal(r.calls(),0)});
test('relatório retornado é privado e não expõe extras',async()=>{const r=route({data:{...result,email:'secret'}});const response=await r.get(request());assert.equal(response.status,200);assert.match(response.headers.get('cache-control'),/no-store/);assert.equal('email' in await response.json(),false)});
test('falhas do banco são genéricas e dados incoerentes recusados',async()=>{for(const config of [{error:{code:'42501',message:'sensitive SQL'}},{error:{code:'XX',message:'sensitive SQL'}},{data:{}}]){const response=await route(config).get(request());assert.ok([403,503].includes(response.status));assert.doesNotMatch(JSON.stringify(await response.json()),/sensitive SQL/)}});
