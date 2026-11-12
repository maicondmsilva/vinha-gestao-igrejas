import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {trustedSessionRequest} from '../app/lib/access-security.ts';
const transpile=path=>ts.transpileModule(readFileSync(new URL(path,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replaceAll('export ','');
function staff({role='owner',result={data:{ok:true,slug:'igreja-teste'},error:null}}={}){
 const calls=[];const client={rpc:async(name,args)=>{calls.push({name,args});return result}};
 const access={membership:{organization_id:'org-verified',membership_id:'member-verified',role,units:[]},client};
 const handlers=new Function('NextResponse','authorizeSupabaseChurch','createSupabaseRequestClient','trustedSessionRequest',transpile('../app/lib/supabase/staff-routes.ts')+';return {staffGET,invitesGone,activateStaff};')({json:Response.json},async request=>trustedSessionRequest(request)?{access,response:null}:{access:null,response:Response.json({error:'origin'},{status:403})},()=>client,trustedSessionRequest);
 return{handlers,calls};
}
const request=data=>new Request('https://vinha.test/api/users/invites',{method:'POST',headers:{origin:'https://vinha.test','content-type':'application/json'},body:JSON.stringify(data)});
test('convites encerrados respondem 410 sem tocar no banco',async()=>{
 const setup=staff();const response=await setup.handlers.invitesGone(request({organizationId:'forged',email:'new@example.test',name:'Pessoa',role:'secretary',unitId:'unit'}));
 assert.equal(response.status,410);assert.match(await response.text(),/Convites encerrados/);assert.equal(setup.calls.length,0);
});
test('acceptance rejects malformed token and database denial without reporting activation',async()=>{
 const setup=staff({result:{data:null,error:{code:'42501',message:'private detail'}}});
 assert.equal((await setup.handlers.activateStaff(request({token:{}}))).status,400);assert.equal(setup.calls.length,0);
 const denied=await setup.handlers.activateStaff(request({token:'a0000000-0000-4000-8000-000000000001'}));assert.equal(denied.status,403);assert.doesNotMatch(await denied.text(),/private detail|redirectUrl/);
});
test('accepted staff invitation returns only a validated panel destination',async()=>{
 const setup=staff();const response=await setup.handlers.activateStaff(request({token:'a0000000-0000-4000-8000-000000000001'}));assert.equal((await response.json()).redirectUrl,'/painel?tenant=igreja-teste');
 const hostile=staff({result:{data:{ok:true,slug:'//other.test'},error:null}});assert.equal((await hostile.handlers.activateStaff(request({token:'a0000000-0000-4000-8000-000000000001'}))).status,503);
});
test('SSR proxy forwards refreshed cookies to handler and browser without granting access',async()=>{
 let clientCalls=0;const pending=new Map(),cookies=new Map([['sb-fixture-auth-token','expired']]);
 const NextResponse={next:({request})=>({forwarded:request,headers:new Headers(),cookies:{set:(name,value)=>pending.set(name,value)}})};
 const run=new Function('NextResponse','createServerClient','process',transpile('../proxy.ts')+';return proxy;')(NextResponse,(_url,_key,options)=>({auth:{getUser:async()=>{clientCalls++;options.cookies.setAll([{name:'sb-fixture-auth-token',value:'renewed',options:{sameSite:'lax'}}]);return{data:{user:{id:'verified'}}}}}}),{env:{NEXT_PUBLIC_SUPABASE_URL:'https://fixture.test',NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:'publishable-test'}});
 const req={cookies:{getAll:()=>[...cookies].map(([name,value])=>({name,value})),set:(name,value)=>cookies.set(name,value)}};
 const response=await run(req);assert.equal(cookies.get('sb-fixture-auth-token'),'renewed');assert.equal(pending.get('sb-fixture-auth-token'),'renewed');assert.equal(response.headers.get('Cache-Control'),'private, no-store, max-age=0');assert.equal(clientCalls,1);
 await run({cookies:{getAll:()=>[]}});assert.equal(clientCalls,1);
});
