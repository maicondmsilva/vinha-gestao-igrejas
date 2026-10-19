import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {trustedSessionRequest} from '../app/lib/access-security.ts';
import {organizationInviteToken} from '../app/lib/organization-invite.ts';
const token='fb000000-0000-4000-8000-000000000001';
function route({user={id:'verified',email_confirmed_at:'2026-10-16'},authError=null,pending={data:null,error:null},result={data:{ok:true,slug:'igreja',alreadyCreated:false},error:null},fail=false}={}){
 const calls=[];let authCalls=0;
 const client={auth:{getUser:async()=>{authCalls++;return{data:{user},error:authError}}},rpc:async(name,args)=>{calls.push([name,args]);if(fail)throw Error('internal secret');return name==='pending_organization_invitation'?pending:result}};
 const code=ts.transpileModule(readFileSync(new URL('../app/api/trial/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replace(/export async function/g,'async function');
 const handlers=new Function('NextResponse','db','trustedSessionRequest','organizationInviteToken',code+'\nreturn {POST}')( {json:Response.json},()=>client,trustedSessionRequest,organizationInviteToken);
 return{...handlers,calls,get authCalls(){return authCalls}};
}
const request=(body='{}',origin='https://app.example.test')=>new Request('https://app.example.test/api/trial',{method:'POST',headers:{origin,'content-type':'application/json'},body});
test('trial rejects cross-origin before authentication or RPC',async()=>{const r=route();assert.equal((await r.POST(request('{}','https://evil.invalid'))).status,403);assert.equal(r.authCalls,0);assert.equal(r.calls.length,0)});
test('trial rejects auth errors even when a user object is returned',async()=>{const r=route({authError:Error('expired')});assert.equal((await r.POST(request())).status,401);assert.equal(r.calls.length,0)});
test('unconfirmed account never registers a ministry',async()=>{const r=route({user:{id:'unconfirmed'}});assert.equal((await r.POST(request())).status,401);assert.equal(r.calls.length,0)});
test('failed invitation lookup does not fall through to create a trial',async()=>{const r=route({pending:{data:null,error:{message:'sensitive SQL'}}});const response=await r.POST(request());assert.equal(response.status,503);assert.equal(r.calls.length,1);assert.doesNotMatch(JSON.stringify(await response.json()),/sensitive|SQL/)});
test('pending invitation returns only a validated activation destination',async()=>{const r=route({pending:{data:{token},error:null}});const response=await r.POST(request());assert.equal(response.status,409);assert.equal((await response.json()).redirectUrl,'/ativar/'+token);assert.equal(r.calls.length,1)});
test('malformed invitation destination is not returned',async()=>{const r=route({pending:{data:{token:'https://evil.invalid'},error:null}});const response=await r.POST(request());assert.equal(response.status,503);assert.doesNotMatch(JSON.stringify(await response.json()),/evil/)});
test('invalid JSON and non-object payloads cannot call registration',async()=>{for(const body of ['{','null','[]']){const r=route();const response=await r.POST(request(body));assert.equal(response.status,400);assert.equal(r.calls.length,1);assert.match(response.headers.get('cache-control'),/no-store/)}});
test('oversized trial payload does not call registration',async()=>{const r=route();assert.equal((await r.POST(request('x'.repeat(12001)))).status,413);assert.equal(r.calls.length,1)});
test('database confirmation denial does not claim trial creation',async()=>{const r=route({result:{data:null,error:{code:'42501',message:'self_service_identity_unavailable'}}});assert.equal((await r.POST(request())).status,401)});
test('successful trial uses confirmed RPC result and private response',async()=>{const r=route();const response=await r.POST(request());assert.equal(response.status,200);assert.equal((await response.json()).redirectUrl,'/painel?tenant=igreja');assert.match(response.headers.get('cache-control'),/private/);assert.equal(r.calls.length,2)});
test('unknown database errors remain generic and incomplete success is refused',async()=>{for(const result of [{data:null,error:{message:'private table users'}},{data:{ok:true,slug:'https://evil.invalid'},error:null}]){const r=route({result});const response=await r.POST(request());assert.ok(response.status>=400);assert.doesNotMatch(JSON.stringify(await response.json()),/private table|evil/)}});
test('network uncertainty never reports saved or leaks internal errors',async()=>{const r=route({fail:true});const response=await r.POST(request());assert.equal(response.status,503);assert.doesNotMatch(JSON.stringify(await response.json()),/internal secret/)});
