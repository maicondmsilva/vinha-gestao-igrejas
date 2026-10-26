import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {kidsOperationCommand,kidsOperationsQuery,kidsOperationsPage,kidsAdmissionPage} from '../app/lib/kids-operations.ts';
const unit='c1000000-0000-4000-8000-000000000001',id='f1000000-0000-4000-8000-000000000001',requestId='f3000000-0000-4000-8000-000000000001';
const command={requestId,action:'checkin',id,version:0,data:{sessionId:id,groupId:id,profileId:id,guardianId:id,identityConfirmed:true,receiptSecret:'a'.repeat(64)}};
test('K2 valida campos, confirma identidade e recusa referência livre',()=>{
 assert.deepEqual(kidsOperationCommand(command),command);
 for(const v of [{...command,organizationId:id},{...command,version:1},{...command,data:{...command.data,profileId:'Nome manual'}},{...command,data:{...command.data,identityConfirmed:'true'}},{...command,data:{...command.data,identityConfirmed:false}},{...command,data:{...command.data,receiptSecret:'abc'}},{...command,data:{...command.data,bypass:true}},{...command,action:'forceCheckout'}])assert.throws(()=>kidsOperationCommand(v));
});
test('K2 exige números inteiros e janela válida de sessão',()=>{
 for(const capacity of [0,501,1.5,'20'])assert.throws(()=>kidsOperationCommand({...command,action:'room',data:{name:'Sala',location:'',capacity,active:true}}));
 for(const endsAt of ['bad','2026-10-24T09:00:00Z','2026-10-26T10:00:00Z'])assert.throws(()=>kidsOperationCommand({...command,action:'session',data:{name:'Sessão',startsAt:'2026-10-24T10:00:00Z',endsAt}}));
});
test('K2 não permite cuidado em papel auxiliar ou equipe sem pessoa',()=>{
 const d={sessionId:id,personId:id,groupId:id,role:'teacher',canCare:true,active:true};assert.doesNotThrow(()=>kidsOperationCommand({...command,action:'assignment',data:d}));
 for(const patch of [{role:'assistant'},{personId:null},{groupId:null},{role:'owner'},{active:'true'}])assert.throws(()=>kidsOperationCommand({...command,action:'assignment',data:{...d,...patch}}));
});
test('K2 recuperação e proteção exigem motivo; aceite não recebe conteúdo extra',()=>{
 for(const action of ['recover','hold','transfer'])assert.throws(()=>kidsOperationCommand({...command,action,data:{reason:''}}));
 assert.doesNotThrow(()=>kidsOperationCommand({...command,action:'transferAccept',version:1,data:{}}));
 assert.throws(()=>kidsOperationCommand({...command,action:'transferAccept',data:{force:true}}));
});
test('filtros rejeitam duplicidade, conta ausente e cursores adulterados',()=>{
 for(const q of ['',`unitId=${unit}&unitId=${unit}`,`unitId=${unit}&sessionId=x`,`unitId=${unit}&q=Ab`,`unitId=${unit}&status=invalid`,`unitId=${unit}&after=bad`])assert.throws(()=>kidsOperationsQuery(new Request('https://example.test/?'+q)));
 assert.equal(kidsOperationsQuery(new Request(`https://example.test/?unitId=${unit}`)).status,'present');
});
test('resposta não aceita chaves de comprovante; busca exige referências',()=>{
 const p={unitId:unit,sessionId:null,canConfigure:true,canSupervise:true,canReceive:true,canDirectory:true,updatedAt:'2026-10-24T10:00:00Z',items:[],nextCursor:null,rooms:[],classes:[],sessions:[],groups:[],assignments:[],history:[]};
 assert.doesNotThrow(()=>kidsOperationsPage(p,unit));assert.throws(()=>kidsOperationsPage({...p,receiptHash:'secret'},unit));assert.throws(()=>kidsOperationsPage({...p,items:Array(51).fill({})},unit));
 assert.throws(()=>kidsAdmissionPage({unitId:unit,items:[{id:'bad',name:'Criança',guardians:[]}]},unit));
});
function route({denied=false,units=[{id:unit}],error=null,data={ok:true,id,version:1}}={}){
 const calls=[],client={rpc:async(name,args)=>{calls.push({name,args});return{data,error}}},authorize=async()=>denied?{response:Response.json({error:'denied'},{status:401})}:{access:{membership:{organization_id:'from-session',units},client}};
 const code=ts.transpileModule(readFileSync(new URL('../app/api/kids-operations/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export async function','async function');
 return{...new Function('NextResponse','authorizeSupabaseChurch','kidsOperationCommand','kidsOperationsQuery','kidsOperationsPage','kidsAdmissionPage',code+';return {GET,POST}')({json:Response.json},authorize,kidsOperationCommand,kidsOperationsQuery,kidsOperationsPage,kidsAdmissionPage),calls};
}
const request=(body=command)=>new Request('https://example.test/api/kids-operations?unitId='+unit,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
test('API autentica e deriva ministério; impede igreja fora do escopo',async()=>{
 const unauth=route({denied:true});assert.equal((await unauth.POST(request())).status,401);assert.equal(unauth.calls.length,0);
 const scope=route({units:[]});assert.equal((await scope.POST(request())).status,403);assert.equal(scope.calls.length,0);
 const ok=route();const r=await ok.POST(request());assert.equal(r.status,200);assert.equal(ok.calls[0].name,'kids_operations_save');assert.equal(ok.calls[0].args.p_organization,'from-session');assert.match(r.headers.get('Cache-Control'),/no-store/);
});
test('API limita corpo e não repete segredos ou SQL em erros',async()=>{
 const large=route();assert.equal((await large.POST(request({...command,data:{reason:'x'.repeat(17000)}}))).status,413);assert.equal(large.calls.length,0);
 const bad=route();const r=await bad.POST(new Request('https://example.test/?unitId='+unit,{method:'POST',headers:{'Content-Type':'application/json'},body:'{"secret":"EXPOSE-ME",INVALID'}));assert.equal(r.status,400);assert.doesNotMatch(await r.text(),/EXPOSE-ME/);
 const sql=route({error:{code:'XX000',message:'private SQL secret EXPOSE-ME'}});assert.doesNotMatch(await (await sql.POST(request())).text(),/EXPOSE-ME|private SQL/);
});
test('API traduz conflito e guarda resultado de código incorreto como falha de retirada',async()=>{
 const conflict=route({error:{code:'40001',message:'kids_capacity_full'}});assert.equal((await conflict.POST(request())).status,409);
 const failure=route({data:{ok:false,id,version:2,reason:'receipt_invalid',remainingAttempts:4}});const response=await failure.POST(request());assert.equal(response.status,200);assert.equal((await response.json()).ok,false);
});
test('interface usa criptografia do navegador e não persiste código em armazenamento',()=>{
 const ui=readFileSync(new URL('../app/KidsOperations.tsx',import.meta.url),'utf8');assert.match(ui,/crypto\.getRandomValues/);assert.doesNotMatch(ui,/localStorage|sessionStorage|console\.log|Math\.random/);assert.match(ui,/setUncertain\(true\)/);assert.match(ui,/kidsOperationCommand/);assert.match(ui,/endpoint="\/api\/kids-foundation"/);assert.match(ui,/receipt\.code/);
 const css=readFileSync(new URL('../app/kids-operations.css',import.meta.url),'utf8');assert.match(css,/@media\(max-width:760px\)/);assert.match(css,/min-height:18px!important/);
});
