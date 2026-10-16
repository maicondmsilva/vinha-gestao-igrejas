// Local/CI only: never accepts a database URL, token, password or remote project.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';

const container=process.env.GITHUB_ACTIONS==='true'?'supabase_db_vinha':'supabase_db_vinha-rls-replay-20261015';
const org=randomUUID(),unit=randomUUID(),users=Array.from({length:4},()=>randomUUID()),members=users.map(()=>randomUUID());
const slug='governance-race-'+org;
const q=value=>"'"+String(value).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){
 return new Promise((resolve,reject)=>{
  const child=spawn('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});
  let out='',err='';
  const timer=setTimeout(()=>{child.kill();reject(new Error('isolated database test timed out'));},15000);
  child.stdout.on('data',chunk=>{out+=chunk;onOutput(out)});
  child.stderr.on('data',chunk=>{err+=chunk});
  child.on('error',error=>{clearTimeout(timer);reject(error)});
  child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});
  child.stdin.on('error',()=>{});
  child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';\n"+sql);
 });
}
async function good(sql){const result=await db(sql);assert.equal(result.code,0,result.err);return result.out.trim()}
const identity=index=>`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:users[index],role:'authenticated'}))},true);`;
async function race(level,revocation){
 await good(`update public.organization_memberships set role='owner',status='active' where id in (${q(members[0])},${q(members[1])});
 update public.organization_memberships set role='admin',status='active' where id=${q(members[2])};
 update public.organization_memberships set role='leader',status='active' where id=${q(members[3])};`);
 let release;
 let firstDone=false,overlapObserved=false;
 const held=new Promise(resolve=>{release=resolve});
 const target=revocation?members[2]:members[0];
 const change=revocation?"status='suspended'":"role='admin'";
 const first=db(`begin;${identity(0)}update public.organization_memberships set ${change} where id=${q(target)};select 'HOLDING_GOVERNANCE_LOCK';select pg_sleep(1.5);commit;`,out=>{if(out.includes('HOLDING_GOVERNANCE_LOCK'))release()}).then(result=>{firstDone=true;return result});
 // The marker is emitted only after the first write acquired the governance/owner locks.
 await Promise.race([held,first.then(result=>{throw new Error('first writer did not reach lock barrier: '+result.err)})]);
 const second=await db(`begin isolation level ${level};select count(*) from public.organization_memberships where organization_id=${q(org)};select 'SECOND_SNAPSHOT_READY';${identity(revocation?2:1)}
 update public.organization_memberships set role=${q(revocation?'secretary':'admin')} where id=${q(revocation?members[3]:members[1])};commit;`,out=>{if(out.includes('SECOND_SNAPSHOT_READY')&&!firstDone)overlapObserved=true});
 const firstResult=await first;assert.equal(firstResult.code,0,firstResult.err);
 assert.ok(overlapObserved,'both database sessions must overlap before the first commit');
 assert.notEqual(second.code,0,'stale or concurrent write must be denied');
 assert.match(second.err,/42501|40001|40P01/,'must fail closed on authorization/serialization/deadlock, not a generic timeout');
 const ownerCount=Number(await good(`select count(*) from public.organization_memberships where organization_id=${q(org)} and role='owner' and status='active';`));
 assert.ok(ownerCount>=1,'ministry must retain an active owner');
 if(revocation)assert.equal(await good(`select role::text from public.organization_memberships where id=${q(members[3])};`),'leader','revoked manager cannot commit a grant from a stale snapshot');
 else assert.equal(ownerCount,1,'exactly one owner remains after one legitimate departure');
 console.log('PASS',level,revocation?'revocation versus grant':'concurrent owner departures');
}
let initialized=false;
try{
 await good(`begin;
 insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values ${users.map(id=>`(${q(id)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('race-'+id+'@example.invalid')},'',now(),now(),now())`).join(',')};
 insert into public.organizations(id,name,slug,status) values(${q(org)},'Governança concorrente sintética',${q(slug)},'active');
 insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede sintética','sede','headquarters');
 insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values ${users.map((id,i)=>`(${q(members[i])},${q(org)},${q(id)},${q(i<2?'owner':i===2?'admin':'leader')},'active',${q(unit)})`).join(',')};commit;`);
 initialized=true;
 for(const level of ['read committed','repeatable read','serializable']){
  await race(level,false);await race(level,true);
 }
}finally{
 if(initialized){
  // Exact random identities created by this process; never enumerate or delete customer data.
  await good(`begin;delete from public.organizations where id=${q(org)} and slug=${q(slug)};
   delete from auth.users where ${users.map(id=>`(id=${q(id)} and email=${q('race-'+id+'@example.invalid')})`).join(' or ')};commit;`);
 }
}
