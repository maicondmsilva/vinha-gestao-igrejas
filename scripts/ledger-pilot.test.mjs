import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {ledgerPilotEnabled,ledgerCommand,moneyCents,ledgerCurrency} from '../app/lib/ledger-pilot.ts';
import {boundedBody,uuidPattern} from '../app/lib/private-files.ts';
const unit='a0000000-0000-4000-8000-000000000001',requestId='a0000000-0000-4000-8000-000000000002',other='a0000000-0000-4000-8000-000000000003';
const local={VINHA_LEDGER_PILOT:'true',NODE_ENV:'test',NEXT_PUBLIC_VINHA_ENV:'local',NEXT_PUBLIC_SUPABASE_URL:'http://127.0.0.1:54321'};
const command={action:'post',unitId:unit,requestId,date:'2026-10-17',memo:'Movimento sintético',debit:unit,credit:other,amount:'1234,56'};
const request=value=>new Request('https://vinha.test/api/church-ledger',{method:'POST',headers:{origin:'https://vinha.test'},body:JSON.stringify(value)});
function route({env=local,role='owner',result={data:requestId,error:null}}={}){
 const calls=[];const chain={select:()=>chain,eq:()=>chain,lte:()=>chain,order:()=>chain,range:()=>Promise.resolve({data:[],error:null,count:0}),maybeSingle:()=>Promise.resolve({data:null,error:null})};
 const client={rpc:async(name,args)=>{calls.push({name,args});return result},from:()=>chain};
 const source=ts.transpileModule(readFileSync(new URL('../app/api/church-ledger/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export ','');
 const handlers=new Function('NextResponse','authorizeSupabaseChurch','ledgerPilotEnabled','ledgerCommand','boundedBody','uuidPattern','process',source+';return {GET,POST};')({json:Response.json},async()=>({access:{membership:{organization_id:'org-verified',role,units:[{id:unit,name:'Unidade teste'}]},client}}),ledgerPilotEnabled,ledgerCommand,boundedBody,uuidPattern,{env});
 return{...handlers,calls};
}
test('pilot gate refuses production, default environments and production project even when opted in',()=>{
 assert.equal(ledgerPilotEnabled(local),true);
 for(const env of [{},{...local,VERCEL_ENV:'production'},{...local,NODE_ENV:'production'},{...local,NEXT_PUBLIC_SUPABASE_URL:'https://aoxibaaydfgffrdqtkva.supabase.co'},{VINHA_LEDGER_PILOT:'true',NEXT_PUBLIC_VINHA_ENV:'test',NEXT_PUBLIC_VINHA_TEST_PROJECT_REF:'aoxibaaydfgffrdqtkva',NEXT_PUBLIC_SUPABASE_URL:'https://aoxibaaydfgffrdqtkva.supabase.co'}])assert.equal(ledgerPilotEnabled(env),false);
});
test('financial input rejects fractions of cents, ambiguous numbers and invalid accounts/dates',()=>{
 assert.equal(moneyCents('1234,56'),123456);assert.equal(moneyCents('0,01'),1);
 for(const value of ['0','-1','1.234,56','1.23','1,234','1e3','Infinity'])assert.throws(()=>moneyCents(value));
 assert.throws(()=>ledgerCommand({...command,debit:other}));assert.throws(()=>ledgerCommand({...command,date:'2026-02-30'}));assert.throws(()=>ledgerCommand({...command,requestId:'bad'}));
 assert.equal(ledgerCurrency('900719925474099300'),'R$ 9.007.199.254.740.993,00');assert.equal(ledgerCurrency('-1'),'-R$ 0,01');
});
test('disabled pilot never authenticates, reads a body or calls database',async()=>{
 const setup=route({env:{}}),r=request(command);assert.equal((await setup.POST(r)).status,503);assert.equal(r.bodyUsed,false);assert.equal(setup.calls.length,0);assert.equal((await setup.GET(new Request('https://vinha.test/api/church-ledger'))).status,503);
});
test('non-financial roles and foreign unit are denied before RPC',async()=>{
 const secretary=route({role:'secretary'});assert.equal((await secretary.POST(request(command))).status,403);assert.equal(secretary.calls.length,0);
 const owner=route();assert.equal((await owner.POST(request({...command,unitId:other}))).status,403);assert.equal(owner.calls.length,0);
});
test('posting derives ministry from verified access and preserves idempotency key',async()=>{
 const setup=route();const response=await setup.POST(request({...command,organization_id:'forged'}));assert.equal(response.status,200);assert.equal(setup.calls.length,1);
 assert.deepEqual(setup.calls[0],{name:'post_church_journal',args:{p_org:'org-verified',p_unit:unit,p_request:requestId,p_date:command.date,p_memo:command.memo,p_lines:[{accountId:unit,deltaCents:123456},{accountId:other,deltaCents:-123456}],p_reversal:null}});
});
test('reversal cannot manufacture its amounts and database failure is never success',async()=>{
 const setup=route();assert.equal((await setup.POST(request({...command,action:'reverse',originalId:other,amount:'99999'}))).status,200);assert.deepEqual(setup.calls[0].args.p_lines,[]);assert.equal(setup.calls[0].args.p_reversal,other);
 const denied=route({result:{data:null,error:{code:'22023',message:'private detail'}}});const r=await denied.POST(request(command));assert.equal(r.status,400);assert.doesNotMatch(await r.text(),/private detail|"ok":true/);
 const wrong=route({result:{data:other,error:null}});assert.equal((await wrong.POST(request(command))).status,503);
});
test('UI retains pending command before network call and has explicit submit/actions',()=>{
 const source=readFileSync(new URL('../app/financeiro-piloto/page.tsx',import.meta.url),'utf8');assert.ok(source.indexOf('setPending(command)')<source.indexOf("fetch(endpoint(),{method:'POST'"));assert.match(source,/send\(pending\)/);assert.match(source,/Resultado ainda não confirmado/);
});
test('GET bootstraps only authorized units and rejects foreign scope or malformed balances',async()=>{
 const setup=route({result:{data:[],error:null}});const bootstrap=await setup.GET(new Request('https://vinha.test/api/church-ledger'));assert.equal(bootstrap.status,200);assert.equal(setup.calls.length,0);
 assert.equal((await setup.GET(new Request(`https://vinha.test/api/church-ledger?unitId=${other}&date=2026-10-17`))).status,403);assert.equal(setup.calls.length,0);
 const response=await setup.GET(new Request(`https://vinha.test/api/church-ledger?unitId=${unit}&date=2026-10-17`));assert.equal(response.status,200);assert.deepEqual((await response.json()).pagination,{page:1,total:0,limit:25});
 const broken=route({result:{data:null,error:null}});assert.equal((await broken.GET(new Request(`https://vinha.test/api/church-ledger?unitId=${unit}&date=2026-10-17`))).status,503);
});
