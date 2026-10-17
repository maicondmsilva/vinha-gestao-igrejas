import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {hierarchyError,validHierarchyDecision,hierarchyAcceptanceMessage} from '../app/lib/hierarchy-governance.ts';

test('hierarchy decisions must be explicit and unknown database details stay private',()=>{
 for(const value of [null,undefined,'','APPROVE','approved',{},1])assert.equal(validHierarchyDecision(value),false);
 for(const value of ['approve','reject'])assert.equal(validHierarchyDecision(value),true);
 assert.doesNotMatch(hierarchyError({code:'99999',message:'secret database detail'}).message,/secret/);
 assert.equal(hierarchyError({code:'40001'}).status,409);
 assert.equal(hierarchyError({code:'42501',message:'hierarchy_previous_approval_unavailable'}).status,403);
 assert.match(hierarchyError({message:'hierarchy_previous_approval_unavailable'}).message,/renovar/);
});
test('only a final confirmed status is presented as an active link',()=>{
 assert.match(hierarchyAcceptanceMessage({status:'approved'}),/ativado/);
 for(const result of [{status:'pending'},{status:'pending',renewalRequired:true},{status:'rejected'}])assert.doesNotMatch(hierarchyAcceptanceMessage(result),/Vínculo aprovado e ativado/);
 assert.match(hierarchyAcceptanceMessage({status:'pending',renewalRequired:true}),/renovar/);
});
function route(session,result){
 const calls=[];
 const source=readFileSync(new URL('../app/api/hierarchy/requests/route.ts',import.meta.url),'utf8').replace(/^import .*;\r?\n/gm,'');
 const code=ts.transpile(source,{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS});
 const run=new Function('exports','NextResponse','sessionFrom','db','rpc','hierarchyError','validHierarchyDecision',code+';return exports.PATCH');
 const handler=run({}, {json:(data,options={})=>({data,status:options.status||200})},async()=>session,()=>({rpc:async(name,args)=>{calls.push({name,args});return result}}),()=>{throw new Error('unexpected RPC wrapper')},hierarchyError,validHierarchyDecision);
 return {handler,calls};
}
const request=data=>new Request('https://app.vinhaigrejas.com.br/api/hierarchy/requests',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify(data)});
test('real hierarchy route takes the ministry only from the verified session',async()=>{
 const h=route({role:'admin',churchId:'verified-org'},{data:{status:'pending'},error:null});
 const result=await h.handler(request({id:'request',decision:'approve',churchId:'injected-org',p_organization:'injected-org'}));
 assert.equal(result.status,200);assert.equal(h.calls[0].args.p_organization,'verified-org');
});
test('real hierarchy route rejects malformed decisions before database writes',async()=>{
 const h=route({role:'admin',churchId:'org'},{});
 assert.equal((await h.handler(request({id:'request'}))).status,400);assert.equal(h.calls.length,0);
 const denied=route({role:'secretary',churchId:'org'},{});
 assert.equal((await denied.handler(request({id:'request',decision:'approve'}))).status,403);assert.equal(denied.calls.length,0);
});
test('real hierarchy route returns a renewal failure without false success',async()=>{
 const h=route({role:'admin',churchId:'org'},{data:null,error:{code:'42501',message:'hierarchy_previous_approval_unavailable'}});
 const result=await h.handler(request({id:'request',decision:'approve'}));
 assert.equal(result.status,403);assert.match(result.data.error,/renovar/);assert.equal(result.data.status,undefined);
});
