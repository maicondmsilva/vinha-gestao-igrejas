import {createClient} from '@supabase/supabase-js';
import {createServerClient} from '@supabase/ssr';
import {randomBytes,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {localSupabaseConfig} from './local-supabase-config.mjs';
import {localTestTotp} from './local-test-totp.mjs';
import {verifiedPlatformIdentity} from '../app/lib/access-security.ts';
if(process.argv[2]!=='--local-synthetic')throw Error('Explicit local synthetic opt-in required.');
const config=localSupabaseConfig();assert.equal(config.API_URL,'http://127.0.0.1:54321');
const options={auth:{persistSession:false,autoRefreshToken:false}},admin=createClient(config.API_URL,config.SERVICE_ROLE_KEY,options),cookies=new Map();
const client=createServerClient(config.API_URL,config.PUBLISHABLE_KEY||config.ANON_KEY,{cookies:{getAll:()=>[...cookies].map(([name,value])=>({name,value})),setAll:values=>{for(const value of values)cookies.set(value.name,value.value)}}});
const http=process.argv.includes('--http'),origin='http://127.0.0.1:4100';
const central=(path='/api/platform/contracts')=>fetch(origin+path,{redirect:'error',headers:{origin,cookie:[...cookies].map(([name,value])=>name+'='+encodeURIComponent(value)).join('; ')},signal:AbortSignal.timeout(15000)});
// Read-only real HTTP checks. No submit, send, provider verification or customer mutation.
const financialReads=[
 ['/api/platform/billing/operations',data=>Array.isArray(data.items)&&data.productionEnabled===false],
 ['/api/platform/billing/channels',data=>Array.isArray(data.channels)&&typeof data.enabled==='boolean'],
];
const email='mfa-local-'+randomUUID()+'@example.invalid',password=randomBytes(32).toString('base64url');let userId=null;
try{
 const created=await admin.auth.admin.createUser({email,password,email_confirm:true});assert.equal(created.error,null,'synthetic Auth creation');userId=created.data.user.id;assert.match(userId,/^[0-9a-f-]{36}$/);
 const fixture=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:`insert into public.platform_operators(user_id,role,full_name,email) values('${userId}','admin','MFA synthetic local','${email}');`,encoding:'utf8'});assert.equal(fixture.status,0,'synthetic operator fixture');
 assert.equal((await client.auth.signInWithPassword({email,password})).error,null,'real local password sign-in');
 assert.equal(await verifiedPlatformIdentity(client,'POST'),null,'aal1 must not authorize Central write');
 if(http){assert.equal((await central()).status,403,'HTTP rejects aal1');for(const [path] of financialReads)assert.equal((await central(path)).status,403,'Financial HTTP rejects aal1: '+path);}
 const factor=await client.auth.mfa.enroll({factorType:'totp',friendlyName:'Synthetic local MFA'});assert.equal(factor.error,null,'TOTP enrollment');
 const verified=await client.auth.mfa.challengeAndVerify({factorId:factor.data.id,code:localTestTotp(factor.data.totp.secret)});assert.equal(verified.error,null,'real local TOTP verification');
 const identity=await verifiedPlatformIdentity(client,'POST');assert.equal(identity?.user.id,userId,'server identity must match synthetic user');assert.equal(identity.operator.role,'admin');
 const assurance=await client.auth.mfa.getAuthenticatorAssuranceLevel();assert.equal(assurance.data.currentLevel,'aal2');
 if(http){const response=await central();assert.equal(response.status,200,'HTTP accepts confirmed MFA session');const data=await response.json();assert.ok(Array.isArray(data.contracts)&&Array.isArray(data.units));assert.match(response.headers.get('cache-control'),/no-store/);console.log('PASS real HTTP Central: aal1 rejected, aal2 accepted, private contract response.');}
 if(http){
  for(const [path,valid] of financialReads){const response=await central(path);assert.equal(response.status,200,'Financial read with MFA: '+path);assert.ok(valid(await response.json()),'Financial response shape: '+path);assert.match(response.headers.get('cache-control'),/no-store/);}
  const legacy=await central('/api/finance/reconciliation');assert.equal(legacy.status,503);assert.equal((await legacy.json()).code,'FEATURE_NOT_RELEASED');
  console.log('PASS financial HTTP reads with MFA: operations, channels; legacy reconciliation fails closed. No external requests sent.');
 }
 console.log('PASS real local Auth: password sign-in, aal1 denied, TOTP verified, aal2 Central identity accepted.');
}finally{
 try{
  const signout=await client.auth.signOut();assert.equal(signout.error,null,'local session sign-out');
  if(http){assert.equal((await central()).status,403,'HTTP rejects signed-out session');for(const [path] of financialReads)assert.equal((await central(path)).status,403,'Financial HTTP rejects logout: '+path);}
 }finally{
  if(userId){const removed=await admin.auth.admin.deleteUser(userId);assert.equal(removed.error,null,'remove only the synthetic account created by this run');console.log('Synthetic account and its MFA factor removed after sign-out. No production or messages.');}
 }
}
