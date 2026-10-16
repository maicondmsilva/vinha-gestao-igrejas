import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {resolveUnitSelection,validUnitParent,unitPreference} from '../app/lib/unit-integrity.ts';

const units=[
 {id:'sede',name:'Sede',parent_unit_id:null},
 {id:'filha',name:'Filha',parent_unit_id:'sede'},
 {id:'neta',name:'Neta',parent_unit_id:'filha'},
];
test('access selector drops revoked preferences and never selects an unauthorized default',()=>{
 assert.equal(unitPreference(units,'outside','filha'),'filha');
 assert.equal(unitPreference(units,'outside','outside'),'');
 assert.equal(unitPreference([],null,'sede'),'');
 assert.equal(unitPreference(units,'neta','sede'),'neta');
 const source=readFileSync(new URL('../app/acesso/page.tsx',import.meta.url),'utf8');
 assert.doesNotMatch(source,/setLegacy|api\/access\/context/);
 assert.match(source,/unitPreference/);
});
test('explicit missing, wildcard and ambiguous unit selections never fall back',()=>{
 assert.equal(resolveUnitSelection(units,'outside','sede'),null);
 assert.equal(resolveUnitSelection(units,'%','sede'),null);
 assert.equal(resolveUnitSelection([...units,{id:'other',name:'Filha'}],'filha name','sede'),null);
 assert.equal(resolveUnitSelection([...units,{id:'other',name:'Neta'}],'NETA','sede'),null);
 assert.equal(resolveUnitSelection(units,'FILHA','sede'),'filha');
 assert.equal(resolveUnitSelection(units,undefined,'sede'),'sede');
 assert.equal(resolveUnitSelection(units,undefined,'outside'),null);
 assert.equal(resolveUnitSelection(units,undefined,null),null);
});
test('hierarchy rejects self, descendants, missing parents and existing cycles',()=>{
 assert.equal(validUnitParent(units,'sede','neta'),false);
 assert.equal(validUnitParent(units,'filha','filha'),false);
 assert.equal(validUnitParent(units,'new','outside'),false);
 assert.equal(validUnitParent(units,'new','neta'),true);
 assert.equal(validUnitParent(units,'filha','sede'),true);
 assert.equal(validUnitParent(units,'sede',null),true);
 assert.equal(validUnitParent([{id:'a',name:'A',parent_unit_id:'b'},{id:'b',name:'B',parent_unit_id:'a'}],'new','a'),false);
});

// Execute the real route bodies with a session-scoped client double.
// SQL/RLS itself is deliberately not simulated or claimed as verified here.
function route(name,responses){
 const calls=[];
 const client={from(table){
  const call={table,method:'select',filters:[]};calls.push(call);
  const result=responses.shift();
  const chain={
   select(){return chain},eq(key,value){call.filters.push([key,value]);return chain},
   update(value){call.method='update';call.value=value;return chain},
   upsert(){call.method='upsert';return chain},
   maybeSingle(){return Promise.resolve(result)},
   then(resolve,reject){return Promise.resolve(result).then(resolve,reject)},
  };return chain;
 }};
 let audits=0;
 const access={client,membership:{organization_id:'org-a',default_unit_id:'sede',role:'admin'}};
 const source=readFileSync(new URL('../app/api/'+name+'/route.ts',import.meta.url),'utf8');
 assert.doesNotMatch(source,/cloudflare:workers|env\.DB|legacy(GET|POST|PATCH)/);
 const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText
  .replace(/^import .*;\r?\n/gm,'')
  .replace(/export \{[\s\S]*?\};/,'return {PATCH:supabasePATCH};');
 const handlers=new Function('NextResponse','authorizeSupabaseChurch','supabaseAudit','resolveUnitSelection','validUnitParent',js)(
  {json:Response.json},async()=>({access,response:null}),async()=>{audits++},resolveUnitSelection,validUnitParent);
 return {handlers,calls,audits:()=>audits};
}
const request=body=>new Request('https://app.example.invalid/api',{method:'PATCH',body:JSON.stringify(body)});
for(const name of ['people','units']){
 test(name+': inaccessible row cannot be reported saved or produce dependent writes',async()=>{
  const r=route(name,[{data:name==='units'?[]:null,error:null}]);
  const response=await r.handlers.PATCH(request({id:'foreign-id',name:'Example'}));
  assert.equal(response.status,404);
  assert.equal(r.calls.length,1);
  assert.ok(r.calls[0].filters.some(([key,value])=>key==='organization_id'&&value==='org-a'));
  assert.equal(r.audits(),0);
 });
 test(name+': zero-row update returns 404 and never saves address or audit',async()=>{
  const row={id:'local-id',unit_id:'filha',name:'Filha',parent_unit_id:'sede'};
  const r=route(name,[{data:name==='units'?[...units,row]:row,error:null},{data:null,error:null}]);
  const response=await r.handlers.PATCH(request({id:'local-id',name:'Example'}));
  assert.equal(response.status,404);
  assert.equal(r.calls.length,2);
  assert.equal(r.calls[1].method,'update');
  assert.ok(r.calls[1].filters.some(([key,value])=>key==='organization_id'&&value==='org-a'));
  assert.equal(r.audits(),0);
 });
}
test('people: omitted campus preserves existing unit and successful update writes its address',async()=>{
 const r=route('people',[{data:{id:'local-id',unit_id:'filha'},error:null},{data:{id:'local-id'},error:null},{error:null}]);
 const response=await r.handlers.PATCH(request({id:'local-id',name:'Example'}));
 assert.equal(response.status,200);
 assert.equal(r.calls[1].value.unit_id,'filha');
 assert.equal(r.calls[2].table,'person_addresses');
 assert.equal(r.audits(),1);
});
test('units: circular reparenting stops before update',async()=>{
 const r=route('units',[{data:units,error:null}]);
 const response=await r.handlers.PATCH(request({id:'sede',name:'Sede',type:'headquarters',parentUnitId:'neta'}));
 assert.equal(response.status,400);
 assert.equal(r.calls.length,1);
 assert.equal(r.audits(),0);
});
for(const name of ['people','units']){
 test(name+': database failure stops editing without audit',async()=>{
  const r=route(name,[{data:null,error:{message:'offline'}}]);
  const response=await r.handlers.PATCH(request({id:'local-id',name:'Example'}));
  assert.equal(response.status,503);
  assert.equal(r.calls.length,1);
  assert.equal(r.audits(),0);
 });
}
