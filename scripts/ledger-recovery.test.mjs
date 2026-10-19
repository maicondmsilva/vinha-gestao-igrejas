import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';

// Executes the component's real send handler with controlled network responses.
// This is a deterministic handler test, not a browser/offline certification.
const source=readFileSync(new URL('../app/financeiro-piloto/page.tsx',import.meta.url),'utf8');
const handler=source.slice(source.indexOf(' async function send('),source.indexOf('\n function submit('));
const javascript=ts.transpileModule(handler,{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
function harness(responses,{save=()=>{},clear=()=>{}}={}){
 const state={pending:null,busy:false,notice:'',revision:0},calls=[];
 const send=new Function('fetch','endpoint','setBusy','setNotice','setPending','setRevision','saveLedgerPending','clearLedgerPending','window','recoveryScope','units','recoveryReady','sending',javascript+';return send;')(
  async(url,options)=>{calls.push(JSON.parse(options.body));const response=responses.shift();if(response instanceof Error)throw response;return response},
  ()=>'/api/church-ledger?tenant=synthetic',value=>state.busy=value,value=>state.notice=value,value=>state.pending=value,update=>state.revision=update(state.revision),save,clear,{sessionStorage:{}},'scope',[{id:'unit-a'}],true,{current:false});
 return{state,calls,send};
}
const command={action:'post',unitId:'unit-a',requestId:'stable-request',amount:'12,34'};
test('lost response preserves original request and retry confirms without changing identity',async()=>{
 const h=harness([new TypeError('Network unavailable'),Response.json({ok:true,id:command.requestId})]);
 await h.send(command);assert.equal(h.state.pending,command);assert.equal(h.state.busy,false);assert.equal(h.state.revision,0);assert.match(h.state.notice,/Conexão interrompida/);assert.doesNotMatch(h.state.notice,/Network unavailable/);
 await h.send(h.state.pending);assert.deepEqual(h.calls,[command,command]);assert.equal(h.state.pending,null);assert.equal(h.state.revision,1);
});

test('storage failure prevents network submission',async()=>{
 const h=harness([],{save:()=>{throw Error('Storage blocked')}});await h.send(command);assert.equal(h.calls.length,0);assert.equal(h.state.busy,false);assert.equal(h.state.revision,0);
});

test('wrong acknowledgement retains recovery instead of reporting success',async()=>{
 let removed=false;const h=harness([Response.json({ok:true,id:'different'})],{clear:()=>removed=true});await h.send(command);assert.equal(h.state.pending,command);assert.equal(removed,false);assert.equal(h.state.revision,0);
});
test('uncertain HTTP and malformed response retain original reversal for recovery',async()=>{
 for(const response of [Response.json({error:'Uncertain'},{status:503}),new Response('<html>gateway</html>',{status:502}),Response.json({ok:false})]){
  const h=harness([response]),reversal={...command,action:'reverse',originalId:'original'};
  await h.send(reversal);assert.equal(h.state.pending,reversal);assert.equal(h.state.busy,false);assert.equal(h.state.revision,0);
 }
});
test('access refusal retains original recovery without reporting a successful write',async()=>{
 const h=harness([Response.json({error:'Acesso negado'},{status:403})]);await h.send(command);
 assert.equal(h.state.pending,command);assert.equal(h.state.busy,false);assert.equal(h.state.notice,'Acesso negado');assert.equal(h.state.revision,0);
});

test('simultaneous sends share one in-flight request and never overwrite recovery',async()=>{
 let saved=0;const h=harness([Response.json({ok:true,id:command.requestId})],{save:()=>saved++});
 await Promise.all([h.send(command),h.send({...command,requestId:'another-request'})]);assert.equal(h.calls.length,1);assert.equal(saved,1);assert.equal(h.state.revision,1);
});

test('temporary authentication, timeout and rate-limit refusals preserve recovery',async()=>{
 for(const status of [401,403,408,429]){let removed=false;const h=harness([Response.json({error:'Retry later'},{status})],{clear:()=>removed=true});await h.send(command);assert.equal(h.state.pending,command);assert.equal(removed,false);assert.equal(h.state.busy,false)}
});
