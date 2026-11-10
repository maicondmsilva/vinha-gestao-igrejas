import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import ts from 'typescript';
import {boundedBody} from '../app/lib/private-files.ts';import {receiverId} from '../app/lib/finance-receivers.ts';
const unit='af400000-0000-4000-8000-000000000001',target='af400000-0000-4000-8000-000000000002',body={unit,target,receipt:unit,version:0};
function route(config={}){
 const calls=[],client={rpc:async(name,args)=>{calls.push({name,args});return{data:{ok:true,items:[]},error:config.error||null}}};
 const deps={authorizeSupabaseChurch:async()=>config.denied?{response:Response.json({}, {status:401})}:{access:{membership:{organization_id:'trusted-org',role:config.role||'owner',units:config.units||[{id:unit},{id:target}]},client}},boundedBody,receiverId};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/finance-digital/destinations/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export const ','const ');
 return{...new Function(...Object.keys(deps),source+';return{GET,POST}')( ...Object.values(deps)),calls};
}
const req=(d=body)=>new Request('https://local/api/finance-digital/destinations',{method:'POST',body:JSON.stringify(d)});
test('destinação exige sessão e acesso às duas igrejas',async()=>{for(const[c,status]of[[{denied:true},401],[{role:'finance'},403],[{units:[{id:unit}]},403],[{units:[{id:target}]},403]]){const r=route(c);assert.equal((await r.POST(req())).status,status);assert.equal(r.calls.length,0)}});
test('destinação não permite escolher valor, ministério ou provar repasse pelo navegador',async()=>{for(const k of ['amount','org','transferred','bankAccount']){const r=route();assert.equal((await r.POST(req({...body,[k]:'x'}))).status,400);assert.equal(r.calls.length,0)}});
test('destinação usa ministério verificado e versão explícita',async()=>{const r=route(),response=await r.POST(req());assert.equal(response.status,200);assert.equal(r.calls[0].args.p_org,'trusted-org');assert.deepEqual(r.calls[0].args.p_data,{receipt:unit,target,version:0});assert.match(response.headers.get('cache-control'),/no-store/)});
test('destinação informa conflito sem expor banco',async()=>{const r=route({error:{code:'40001',message:'secret'}}),response=await r.POST(req());assert.equal(response.status,409);assert.doesNotMatch(JSON.stringify(await response.json()),/secret/)});
test('financeiro pode ler somente a própria unidade autorizada',async()=>{const r=route({role:'finance',units:[{id:unit}]});assert.equal((await r.GET(new Request('https://local/?unit='+unit))).status,200);assert.equal((await r.GET(new Request('https://local/?unit='+target))).status,403)});
test('destinação recusa filtros extras e repetidos',async()=>{for(const q of ['?unit='+unit+'&unit='+unit,'?unit='+unit+'&org='+unit]){const r=route();assert.equal((await r.GET(new Request('https://local/'+q))).status,400);assert.equal(r.calls.length,0)}});
