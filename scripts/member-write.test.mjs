import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {memberWriteInput,memberFormPayload} from '../app/lib/member-write.ts';
import {resolveUnitSelection} from '../app/lib/unit-integrity.ts';
const id='a0000000-0000-4000-8000-000000000001';
test('partial write keeps only provided fields and strips presentation metadata',()=>{
 assert.deepEqual(memberWriteInput({id,phone:'1199',since:'Hoje',initials:'AB',access:'member'},true),{id,campus:undefined,changes:{phone:'1199'}});
 assert.throws(()=>memberWriteInput({name:' '},false));
 assert.throws(()=>memberWriteInput({id:'outside',phone:'1199'},true));
 assert.throws(()=>memberWriteInput({id,privacy:'false'},true));
 assert.throws(()=>memberWriteInput({id,organization_id:id},true));
 assert.throws(()=>memberWriteInput({id,campus:''},true));
 assert.throws(()=>memberWriteInput([],true));
});
test('editing does not fabricate consent changes or clear unvisited fields',()=>{
 const initial={id,name:'Pessoa',privacy:true};
 assert.deepEqual(memberFormPayload({name:'Pessoa',phone:'1199',privacy:false,notes:''},initial,[]),{id,name:'Pessoa',phone:'1199'});
 assert.deepEqual(memberFormPayload({name:'Pessoa',privacy:false},initial,['privacy']),{id,name:'Pessoa',privacy:false});
 assert.deepEqual(memberFormPayload({name:'Pessoa',privacy:true,campus:id},null,[]),{name:'Pessoa',privacy:true,campus:id});
});
function route(result,unitResult={data:[],error:null}){
 const calls=[];
 const client={
  rpc:async(name,args)=>{calls.push({name,args});return result},
  from:()=>{let chain={select:()=>chain,eq:()=>chain,then:(resolve,reject)=>Promise.resolve(unitResult).then(resolve,reject)};return chain},
 };
 const source=readFileSync(new URL('../app/api/people/route.ts',import.meta.url),'utf8');
 const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText
  .replace(/^import .*;\r?\n/gm,'').replace(/export \{[\s\S]*?\};/,'return {POST:supabasePOST,PATCH:supabasePATCH};');
 const handlers=new Function('NextResponse','authorizeSupabaseChurch','resolveUnitSelection','memberWriteInput',js)(
  {json:Response.json},async()=>({access:{client,membership:{organization_id:'org-a',default_unit_id:'unit-a'}}}),resolveUnitSelection,memberWriteInput);
 return {handlers,calls};
}
const request=(body,method='PATCH')=>new Request('https://app.example.invalid/api/people',{method,body:JSON.stringify(body)});
test('PATCH uses exactly one atomic RPC without selecting a new default unit',async()=>{
 const r=route({data:id,error:null});
 const response=await r.handlers.PATCH(request({id,phone:'1199'}));
 assert.equal(response.status,200);
 assert.deepEqual(r.calls,[{name:'save_person_record',args:{p_organization:'org-a',p_unit:null,p_person:id,p_data:{phone:'1199'}}}]);
});
test('POST resolves the authorized unit and uses one atomic RPC',async()=>{
 const r=route({data:id,error:null},{data:[{id:'unit-a',name:'Unidade A'}],error:null});
 const response=await r.handlers.POST(request({name:'Pessoa'},'POST'));
 assert.equal(response.status,201);assert.equal(r.calls.length,1);
 assert.equal(r.calls[0].args.p_unit,'unit-a');assert.equal(r.calls[0].args.p_person,null);
});
test('explicit invalid unit never invokes the transaction',async()=>{
 const r=route({data:id,error:null});
 assert.equal((await r.handlers.PATCH(request({id,campus:'outside'}))).status,400);
 assert.equal(r.calls.length,0);
});
for(const [code,status] of [['P0002',404],['42501',403],['23505',409],['23514',400],['22023',400],['08006',503]]){
 test('RPC failure '+code+' never reports saved or leaks database details',async()=>{
  const r=route({data:null,error:{code,message:'sensitive database details'}});
  const response=await r.handlers.PATCH(request({id,name:'Pessoa'}));
  assert.equal(response.status,status);
  assert.doesNotMatch(await response.text(),/sensitive database details/);
  assert.equal(r.calls.length,1);
 });
}
test('route has no parallel writes or compensating deletes; form uses live units',()=>{
 const api=readFileSync(new URL('../app/api/people/route.ts',import.meta.url),'utf8');
 assert.doesNotMatch(api,/\.insert\(|\.update\(|\.upsert\(|\.delete\(|supabaseAudit/);
 const ui=readFileSync(new URL('../app/DashboardApp.tsx',import.meta.url),'utf8').split('function PersonModal')[1].split('function FamiliesAndTerms')[0];
 assert.match(ui,/units.map/);assert.match(ui,/memberFormPayload/);assert.match(ui,/goToStep/);
 assert.doesNotMatch(ui,/Unidade Norte|Família Souza|Convidar como administrador/);
});
