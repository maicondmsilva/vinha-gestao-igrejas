import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {kidsCommand,kidsQuery,kidsPage} from '../app/lib/kids-foundation.ts';
import {memberChoicePage} from '../app/lib/member-choice.ts';
const unit='c1000000-0000-4000-8000-000000000001',id='f1000000-0000-4000-8000-000000000001';
const command={requestId:'f3000000-0000-4000-8000-000000000001',action:'profile',id,version:0,data:{personId:id,status:'active'}};
test('comandos K1 validam identidade, versão e lista fechada de campos',()=>{
 assert.deepEqual(kidsCommand(command),command);
 for(const v of [{...command,organizationId:id},{...command,version:-1},{...command,requestId:'bad'},{...command,data:{...command.data,full_name:'duplicação'}},{...command,data:{personId:'manual',status:'active'}},{...command,action:'checkout'}])assert.throws(()=>kidsCommand(v));
});
test('cadastro rápido e cuidados não aceitam dados ilimitados ou datas inexistentes',()=>{
 assert.doesNotThrow(()=>kidsCommand({...command,action:'person',data:{name:'Pessoa fictícia',birthDate:'2020-01-01',phone:''}}));
 for(const birthDate of ['','2020-02-31','ontem','2020-13-01'])assert.throws(()=>kidsCommand({...command,action:'person',data:{name:'Pessoa fictícia',birthDate,phone:''}}));
 assert.throws(()=>kidsCommand({...command,action:'care',data:{instructions:'x'.repeat(3001),source:'Responsável'}}));
 assert.throws(()=>kidsCommand({...command,action:'care',data:{instructions:'Permitido',source:''}}));
});
test('autorização não aceita booleanos simulados nem aprovação sem conferência',()=>{
 const data={profileId:id,personId:id,relationship:'Responsável',verificationNote:'Conferência presencial fictícia',canPickup:true,canEdit:false,isEmergency:true,status:'approved',validUntil:''};
 assert.doesNotThrow(()=>kidsCommand({...command,action:'guardian',data}));
 for(const patch of [{canPickup:'true'},{verificationNote:''},{validUntil:'2020-02-31'},{status:'self-approved'}])assert.throws(()=>kidsCommand({...command,action:'guardian',data:{...data,...patch}}));
});
test('filtros exigem unidade inequívoca e não aceitam cursores adulterados',()=>{
 for(const query of ['',`unitId=${unit}&unitId=${unit}`,`unitId=${unit}&after=bad`,`unitId=${unit}&q=a`])assert.throws(()=>kidsQuery(new Request('https://example.test/?'+query)));
 assert.equal(kidsQuery(new Request('https://example.test/?unitId='+unit)).unitId,unit);
});
function route({denied=false,units=[{id:unit}],error=null,data={id,version:1}}={}){
 const calls=[];const client={rpc:async(name,args)=>{calls.push({name,args});return{data,error}}};
 const authorize=async()=>denied?{response:Response.json({error:'denied'},{status:401})}:{access:{membership:{organization_id:'organization-from-session',units},client}};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/kids-foundation/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export async function','async function');
 return{...new Function('NextResponse','authorizeSupabaseChurch','kidsCommand','kidsPage','kidsQuery','memberChoicePage',source+';return {GET,POST}')({json:Response.json},authorize,kidsCommand,kidsPage,kidsQuery,memberChoicePage),calls};
}
const request=(body=command)=>new Request('https://example.test/api/kids-foundation?unitId='+unit,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
test('API autentica antes de consultar e exige unidade autorizada',async()=>{
 for(const config of [{denied:true},{units:[]}]){const r=route(config);assert.ok([401,403].includes((await r.POST(request())).status));assert.equal(r.calls.length,0)}
});
test('API deriva ministério da sessão e envia somente o comando validado',async()=>{
 const r=route(),response=await r.POST(request());assert.equal(response.status,200);assert.equal(r.calls[0].name,'kids_save');assert.equal(r.calls[0].args.p_organization,'organization-from-session');assert.equal(r.calls[0].args.p_unit,unit);assert.match(response.headers.get('cache-control'),/private.*no-store/);
 assert.equal((await r.POST(request({...command,actorId:id}))).status,400);assert.equal(r.calls.length,1);
});
test('API limita tamanho e não revela detalhes internos de falhas',async()=>{
 assert.equal((await route().POST(request({...command,data:{instructions:'x'.repeat(20000)}}))).status,413);
 for(const [code,status] of [['42501',403],['40001',409],['23505',409],['22023',400],['XX',503]]){
  const response=await route({error:{code,message:'internal sensitive SQL'}}).POST(request());assert.equal(response.status,status);assert.doesNotMatch(JSON.stringify(await response.json()),/sensitive SQL/);
 }
});
test('telas Kids não montam operação legada, guardam credenciais ou liberam retirada',()=>{
 const ui=readFileSync(new URL('../app/KidsFoundation.tsx',import.meta.url),'utf8');
 assert.doesNotMatch(ui,/localStorage|service_role|prompt\(|\/api\/children|\/api\/kids\?/);
 const dashboard=readFileSync(new URL('../app/DashboardApp.tsx',import.meta.url),'utf8');assert.match(dashboard,/<KidsOperations key=\{unitId\} unitId=\{unitId\}/);
 assert.doesNotMatch(dashboard,/<KidsArea people=\{people\}/);
 assert.match(readFileSync(new URL('../app/KidsOperations.tsx',import.meta.url),'utf8'),/<KidsFoundation unitId=\{unitId\}/);
});
test('kids mostra sugeridos da família',()=>{const s=readFileSync(new URL('../app/KidsFoundation.tsx',import.meta.url),'utf8')+readFileSync(new URL('../app/KidsFamilySuggestions.tsx',import.meta.url),'utf8');assert.match(s,/suggest=1&child=/);assert.match(s,/Da família/);assert.match(s,/Usar como responsável/);assert.match(s,/<KidsFamilySuggestions/)});
