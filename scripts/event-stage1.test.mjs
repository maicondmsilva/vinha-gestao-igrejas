import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {emptyEventInfo,eventInfoValid,canonicalEventPath} from '../shared/event-info.ts';
import {programmingCommand} from '../app/lib/programming-command.ts';
import {boundedBody,uuidPattern} from '../app/lib/private-files.ts';
const id='aa000000-0000-4000-8000-000000000001';
test('informações do evento recusam links executáveis, credenciais e campos extras',()=>{
 const good=emptyEventInfo();assert.ok(eventInfoValid(good));
 for(const bad of[{...good,organization:id},{...good,venue:{...good.venue,onlineUrl:'javascript:alert(1)'}},{...good,contacts:{...good.contacts,website:'https://user:pass@example.com'}},{...good,team:[id,id]},{...good,targets:[id,id]},{...good,gallery:[{id,url:'data:text/html,unsafe',caption:''}]}])assert.equal(eventInfoValid(bad),false);
});
test('atividade exige intervalo válido e imagem só aceita HTTPS ou arquivo do evento',()=>{
 const good=emptyEventInfo();good.schedule=[{id,title:'Acolhimento',starts:'2027-01-31T19:00:00-03:00',ends:'2027-01-31T19:30:00-03:00',location:''}];good.gallery=[{id,url:'/api/event-images/'+id,caption:'Comunidade'}];assert.ok(eventInfoValid(good));assert.equal(eventInfoValid({...good,schedule:[{...good.schedule[0],ends:good.schedule[0].starts}]}),false);assert.equal(eventInfoValid({...good,gallery:[{id,url:'/api/private-file/'+id,caption:''}]}),false);
});
test('comando preserva informações e não aceita adicioná-las a preço ou publicação',()=>{
 const info=emptyEventInfo(),data={title:'Encontro',description:'',kind:'event',startsLocal:'2027-01-31T19:00',endsLocal:'2027-01-31T21:00',location:'',address:'',capacity:100,category:'',cover:'',repeat:'none',count:1,information:info};assert.deepEqual(programmingCommand({unit:id,action:'create',id,data}).data.information,info);assert.equal(programmingCommand({unit:id,action:'publish',id,version:1,data:{future:false,versions:{[id]:1},information:info}}),null);
});
function informationRoute(result={data:{ok:true},error:null},denied=false){const calls=[],src=ts.transpileModule(readFileSync(new URL('../app/api/event-information/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export const ','const ');return{calls,...new Function('authorizeSupabaseChurch','db','boundedBody','uuidPattern','eventInfoValid',src+';return {GET,POST}')(async()=>denied?{response:Response.json({error:'denied'},{status:403})}:{access:{membership:{organization_id:'session-org'}}},()=>({rpc:async(name,args)=>{calls.push({name,args});return result}}),boundedBody,uuidPattern,eventInfoValid)}}
const save=extra=>new Request('https://vinha.test/api/event-information',{method:'POST',body:JSON.stringify({unit:id,event:id,action:'save',version:2,data:emptyEventInfo(),...extra})});
test('API deriva organização da sessão e recusa identidade forjada',async()=>{const r=informationRoute();assert.equal((await r.POST(save())).status,200);assert.equal(r.calls[0].args.p_org,'session-org');assert.equal((await r.POST(save({organization:id}))).status,400);assert.equal(r.calls.length,1);const denied=informationRoute(undefined,true);assert.equal((await denied.POST(save())).status,403);assert.equal(denied.calls.length,0)});
test('API exige confirmação e traduz conflito sem vazar detalhes internos',async()=>{const no=informationRoute({data:{},error:null});assert.equal((await no.POST(save())).status,503);const conflict=informationRoute({data:null,error:{code:'40001',message:'private internal SQL'}}),r=await conflict.POST(save());assert.equal(r.status,409);assert.match(r.headers.get('cache-control'),/no-store/);assert.doesNotMatch(await r.text(),/private internal SQL/)});

test('somente URLs canônicas liberam a página pública e a equipe',()=>{assert.ok(canonicalEventPath('/eventos/e-'+id));assert.ok(canonicalEventPath('/eventos/e-'+id+'/equipe'));for(const path of ['/eventos/legado','/eventos/pagamento','/eventos/e-'+id+'/checkout','/eventos/e-'+id+'/../pagamento'])assert.equal(canonicalEventPath(path),false)});
