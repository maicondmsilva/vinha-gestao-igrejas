import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {trustedSessionRequest} from '../app/lib/access-security.ts';
import {organizationInviteToken,organizationInviteError} from '../app/lib/organization-invite.ts';
const token='f9000000-0000-4000-8000-000000000001';
function route({user={id:'verified'},authError=null,result={data:{slug:'igreja',alreadyAccepted:true},error:null},progress={status:'completed'},fail=false}={}){
 const calls=[];const db={auth:{getUser:async()=>({data:{user},error:authError})},rpc:async(name,args)=>{calls.push([name,args]);if(fail)throw Error('secret');return result},from:()=>{const chain={select:()=>chain,eq:()=>chain,single:async()=>({data:{id:'org'},error:null}),maybeSingle:async()=>({data:progress,error:null})};return chain}};
 const code=ts.transpileModule(readFileSync(new URL('../app/api/platform/activate/route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace(/^import .*;\r?\n/gm,'').replace(/export async function/g,'async function');
 const handlers=new Function('NextResponse','createSupabaseRequestClient','trustedSessionRequest','organizationInviteToken','organizationInviteError',code+'\nreturn {GET,POST}')( {json:Response.json},()=>db,trustedSessionRequest,organizationInviteToken,organizationInviteError);
 return{...handlers,calls};
}
const request=(body=JSON.stringify({token}),origin='https://app.example.test')=>new Request('https://app.example.test/api/platform/activate',{method:'POST',headers:{origin,'content-type':'application/json'},body});
test('invite token rejects objects and malformed identifiers',()=>{assert.equal(organizationInviteToken({token}),null);assert.equal(organizationInviteToken('bad'),null);assert.equal(organizationInviteToken(token),token)});
test('cross-origin activation never calls the database',async()=>{const r=route();assert.equal((await r.POST(request(undefined,'https://evil.invalid'))).status,403);assert.equal(r.calls.length,0)});
test('malformed JSON produces a private 400 response',async()=>{const r=route();const response=await r.POST(request('{'));assert.equal(response.status,400);assert.match(response.headers.get('cache-control'),/no-store/);assert.equal(r.calls.length,0)});
test('failed verified identity never accepts the invitation',async()=>{const r=route({authError:Error('expired')});assert.equal((await r.POST(request())).status,401);assert.equal(r.calls.length,0)});
test('revoked membership is explained without leaking database details',async()=>{const r=route({result:{data:null,error:{code:'42501',message:'invite_access_revoked'}}});const response=await r.POST(request());assert.equal(response.status,403);assert.match((await response.json()).error,/não altera nem reativa/)});
test('accepted invitation resumes the existing panel',async()=>{const r=route();const response=await r.POST(request());assert.equal(response.status,200);assert.equal((await response.json()).redirectUrl,'/painel?tenant=igreja');assert.equal(r.calls.length,1)});
test('failed RPC is not reported as activated',async()=>{const r=route({fail:true});const response=await r.POST(request());assert.equal(response.status,503);assert.doesNotMatch(JSON.stringify(await response.json()),/secret/)});
test('unknown database failures remain generic',()=>assert.doesNotMatch(organizationInviteError('sensitive SQL table'),/sensitive|SQL/));
