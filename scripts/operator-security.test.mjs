import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {requireOperatorChange} from '../app/lib/operator-mutations.ts';

test('operator writes require one confirmed row and do not expose raw database errors',()=>{
 assert.throws(()=>requireOperatorChange({data:[],error:null},'Sem alteração'),/Sem alteração/);
 assert.throws(()=>requireOperatorChange({data:null,error:null},'Sem alteração'),/Sem alteração/);
 assert.throws(()=>requireOperatorChange({data:[{},{}],error:null},'Sem alteração'),/Sem alteração/);
 assert.throws(()=>requireOperatorChange({data:null,error:{message:'sensitive database detail'}},'Sem alteração'),error=>!error.message.includes('sensitive'));
 assert.doesNotThrow(()=>requireOperatorChange({data:[{id:'confirmed'}],error:null},'Sem alteração'));
});

function handlers(result){
 const source=readFileSync(new URL('../app/admin-vinha/operadores/page.tsx',import.meta.url),'utf8');
 const mutationSource=source.slice(source.indexOf(' async function updateOperator('),source.indexOf(' async function copy('));
 const notices=[],busy=[],calls=[];let loaded=0;
 const chain={update:patch=>{calls.push(['update',patch]);return chain},eq:(...args)=>{calls.push(['eq',...args]);return chain},is:(...args)=>{calls.push(['is',...args]);return chain},select:async field=>{calls.push(['select',field]);if(result instanceof Error)throw result;return result}};
 const client={from:table=>{calls.push(['from',table]);return chain}};
 const run=new Function('supabase','setNotice','setBusy','load','requireOperatorChange',ts.transpile(mutationSource,{target:ts.ScriptTarget.ES2022})+';return {updateOperator,revoke}');
 return {...run(client,value=>notices.push(value),value=>busy.push(value),async()=>{loaded++},requireOperatorChange),notices,busy,calls,get loaded(){return loaded}};
}
test('real operator handler rejects zero-row RLS updates and always releases busy state',async()=>{
 const h=handlers({data:[],error:null});await h.updateOperator({user_id:'target'},{active:false});
 assert.match(h.notices.at(-1),/não alterado/);assert.deepEqual(h.busy,[true,false]);assert.equal(h.loaded,0);
 assert.ok(h.calls.some(call=>call[0]==='select'&&call[1]==='user_id'));
});
test('real revoke handler checks pending state and does not report a stale invite cancelled',async()=>{
 const h=handlers({data:[],error:null});await h.revoke({id:'target'});
 assert.match(h.notices.at(-1),/não cancelado/);assert.equal(h.loaded,0);
 assert.ok(h.calls.some(call=>call[0]==='is'&&call[1]==='accepted_at'&&call[2]===null));
 assert.ok(h.calls.some(call=>call[0]==='is'&&call[1]==='revoked_at'&&call[2]===null));
});
test('real revoke success reloads only after a confirmed row',async()=>{
 const h=handlers({data:[{id:'target'}],error:null});await h.revoke({id:'target'});
 assert.equal(h.notices.at(-1),'Convite cancelado.');assert.equal(h.loaded,1);assert.deepEqual(h.busy,[true,false]);
});
test('network failure does not leave operator buttons busy',async()=>{
 const h=handlers(new Error('Falha de conexão'));await h.updateOperator({user_id:'target'},{active:false});
 assert.deepEqual(h.busy,[true,false]);assert.equal(h.loaded,0);assert.notEqual(h.notices.at(-1),'Permissão atualizada e registrada na auditoria.');
});
test('expired pending invitations can be cancelled before issuing a new one',()=>{
 const source=readFileSync(new URL('../app/admin-vinha/operadores/page.tsx',import.meta.url),'utf8');
 assert.match(source,/status==='Pendente'\|\|status==='Expirado'/);
 assert.match(source,/<select disabled=\{busy\} value=\{item.role\}/);
});
