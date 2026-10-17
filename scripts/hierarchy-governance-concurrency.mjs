// Only a fixed ephemeral local/CI Docker container is accepted; never a DB URL.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const container=process.env.GITHUB_ACTIONS==='true'?'supabase_db_vinha':'supabase_db_vinha-rls-replay-20261015';
const q=value=>"'"+String(value).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){
 return new Promise((resolve,reject)=>{
  const child=spawn('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});
  let out='',err='';const timer=setTimeout(()=>{child.kill();reject(new Error('isolated hierarchy test timed out'))},15000);
  child.stdout.on('data',chunk=>{out+=chunk;onOutput(out)});child.stderr.on('data',chunk=>{err+=chunk});
  child.on('error',error=>{clearTimeout(timer);reject(error)});child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});
  child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';\n"+sql);
 });
}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
async function scenario(level,kind){
 const orgs=[randomUUID(),randomUUID()],users=Array.from({length:4},()=>randomUUID()),members=Array.from({length:3},()=>randomUUID());
 const slugs=orgs.map(id=>'hierarchy-race-'+id),request=randomUUID();let initialized=false;
 const identity=i=>`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:users[i],role:'authenticated',aal:i===3?'aal2':'aal1'}))},true);`;
 const approve=`select public.approve_organization_hierarchy(${q(request)},${q(orgs[1])},'approve');`;
 try{
  await good(`begin;
   insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values ${users.map(id=>`(${q(id)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('hierarchy-race-'+id+'@example.invalid')},'',now(),now(),now())`).join(',')};
   insert into public.organizations(id,name,slug,status) values ${orgs.map((id,i)=>`(${q(id)},'Hierarquia concorrente sintética',${q(slugs[i])},'active')`).join(',')};
   insert into public.platform_operators(user_id,role,full_name,email) values(${q(users[3])},'owner','Operador sintético',${q('hierarchy-race-'+users[3]+'@example.invalid')});
   insert into public.organization_memberships(id,organization_id,user_id,role,status) values(${q(members[0])},${q(orgs[0])},${q(users[0])},'owner','active'),(${q(members[1])},${q(orgs[1])},${q(users[1])},'owner','active'),(${q(members[2])},${q(orgs[0])},${q(users[2])},'admin','active');
   insert into public.saas_hierarchy_requests(id,parent_church_id,child_church_id,billing_mode,requested_by,created_at) values(${q(request)},${q(orgs[0])},${q(orgs[1])},'centralized',${q(users[3])},1);
   ${identity(2)}select public.approve_organization_hierarchy(${q(request)},${q(orgs[0])},'approve');commit;`);initialized=true;
  let release,firstDone=false,overlap=false;const held=new Promise(resolve=>{release=resolve});
  const firstWrite=kind==='revocation'?`${identity(0)}update public.organization_memberships set status='suspended' where id=${q(members[2])};`:`${identity(1)}${approve}`;
  const first=db(`begin;${firstWrite}select 'HOLDING_HIERARCHY_LOCK';select pg_sleep(1.5);commit;`,out=>{if(out.includes('HOLDING_HIERARCHY_LOCK'))release()}).then(result=>{firstDone=true;return result});
  await Promise.race([held,first.then(result=>{throw new Error('first transaction did not reach barrier: '+result.err)})]);
  const second=await db(`begin isolation level ${level};select count(*) from public.saas_hierarchy_requests where id=${q(request)};select 'SECOND_HIERARCHY_SNAPSHOT_READY';${identity(1)}${approve}commit;`,out=>{if(out.includes('SECOND_HIERARCHY_SNAPSHOT_READY')&&!firstDone)overlap=true});
  const initial=await first;assert.equal(initial.code,0,initial.err);assert.ok(overlap,'two independent sessions must overlap');
  if(kind==='revocation'){
   assert.notEqual(second.code,0,'a stale first approver must fail closed');assert.match(second.err,/42501|40001|40P01/);
   assert.equal(await good(`select count(*) from public.saas_organization_links where child_church_id=${q(orgs[1])} and status='active';`),'0');
   assert.equal(await good(`select count(*) from public.saas_billing_responsibilities where church_id=${q(orgs[1])};`),'0');
   assert.equal(await good(`select status from public.saas_hierarchy_requests where id=${q(request)};`),'pending');
  }else{
   if(second.code!==0)assert.match(second.err,/40001|40P01/,'duplicate must succeed idempotently or fail on snapshot conflict');
   assert.equal(await good(`select count(*) from public.saas_organization_links where child_church_id=${q(orgs[1])} and status='active';`),'1');
   assert.equal(await good(`select count(*) from public.organization_hierarchy_events where request_id=${q(request)} and action='activated';`),'1');
   assert.equal(await good(`select count(*) from public.saas_billing_responsibilities where church_id=${q(orgs[1])} and payer_church_id=${q(orgs[0])} and billing_mode='centralized';`),'1');
  }
  console.log('PASS hierarchy',level,kind==='revocation'?'first approver revocation versus final acceptance':'concurrent duplicate final acceptance');
 }finally{
  if(initialized)await good(`begin;
   delete from public.organization_hierarchy_events where request_id=${q(request)} and child_organization_id=${q(orgs[1])};
   delete from public.saas_billing_responsibilities where church_id=${q(orgs[1])};
   delete from public.saas_organization_links where child_church_id=${q(orgs[1])} and parent_church_id=${q(orgs[0])};
   delete from public.saas_hierarchy_requests where id=${q(request)} and child_church_id=${q(orgs[1])};
   delete from public.organizations where ${orgs.map((id,i)=>`(id=${q(id)} and slug=${q(slugs[i])})`).join(' or ')};
   delete from public.platform_operators where user_id=${q(users[3])};
   delete from auth.users where ${users.map(id=>`(id=${q(id)} and email=${q('hierarchy-race-'+id+'@example.invalid')})`).join(' or ')};commit;`);
 }
}
for(const level of ['read committed','repeatable read','serializable']){await scenario(level,'revocation');await scenario(level,'duplicate')}
