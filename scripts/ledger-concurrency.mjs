// Synthetic fixtures, fixed ephemeral container only. Never accepts a production URL.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const isolatedDatabase=process.env.VINHA_LOCAL_LEDGER_TEST_DATABASE;
if(isolatedDatabase&&!/^l4_ledger_qa_[a-f0-9]{12}$/.test(isolatedDatabase))throw Error('Invalid isolated ledger database.');
const container=isolatedDatabase?'supabase_db_vinha':process.env.GITHUB_ACTIONS==='true'?'supabase_db_vinha':'supabase_db_vinha-rls-replay-20261015';
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{
 const child=spawn('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d',isolatedDatabase||'postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});
 let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('isolated ledger test timeout'))},15000);
 child.stdout.on('data',chunk=>{out+=chunk;onOutput(out)});child.stderr.on('data',chunk=>{err+=chunk});
 child.on('error',error=>{clearTimeout(timer);reject(error)});child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});
 child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';\n"+sql);
})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
async function scenario(level,kind){
 const org=randomUUID(),unit=randomUUID(),user=randomUUID(),accounts=[randomUUID(),randomUUID()],request=randomUUID(),slug='ledger-race-'+org;
 const identity=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:user,role:'authenticated'}))},true);`;
 const post=`select public.post_church_journal(${q(org)},${q(unit)},${q(request)},current_date-2,'Synthetic race',${q(JSON.stringify(accounts.map((accountId,i)=>({accountId,deltaCents:i?-100:100}))))}::jsonb);`;
 let initialized=false;
 try{
  await good(`begin;
   insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(user)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q(slug+'@example.invalid')},now(),now(),now());
   insert into public.organizations(id,name,slug,status) values(${q(org)},'Synthetic ledger race',${q(slug)},'active');
   insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede sintética',${q(slug)},'headquarters');
   insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(user)},'owner','active',${q(unit)});
   insert into public.church_ledger_accounts(id,organization_id,unit_id,name,kind) values(${q(accounts[0])},${q(org)},${q(unit)},'Banco','asset'),(${q(accounts[1])},${q(org)},${q(unit)},'Ofertas','income');
   insert into public.church_ledger_periods(organization_id,unit_id) values(${q(org)},${q(unit)});commit;`);initialized=true;
  let release,done=false,overlap=false;const held=new Promise(resolve=>release=resolve);
  const firstWrite=kind==='close'?`select public.close_church_ledger_period(${q(org)},${q(unit)},current_date-1);`:post;
  const first=db(`begin;${identity}${firstWrite}select 'LEDGER_LOCK_HELD';select pg_sleep(1.5);commit;`,out=>{if(out.includes('LEDGER_LOCK_HELD'))release()}).then(r=>{done=true;return r});
  await Promise.race([held,first.then(r=>{throw Error('missing ledger barrier: '+r.err)})]);
  const second=await db(`begin isolation level ${level};select count(*) from public.church_ledger_periods where organization_id=${q(org)};select 'LEDGER_SNAPSHOT_READY';${identity}${post}commit;`,out=>{if(out.includes('LEDGER_SNAPSHOT_READY')&&!done)overlap=true});
  const initial=await first;assert.equal(initial.code,0,initial.err);assert.ok(overlap,'independent sessions must overlap');
  if(kind==='close'){assert.notEqual(second.code,0);assert.match(second.err,/22023|40001|40P01/);assert.equal(await good(`select count(*) from public.church_ledger_journals where organization_id=${q(org)};`),'0')}
  else{if(second.code!==0)assert.match(second.err,/40001|40P01/);assert.equal(await good(`select count(*) from public.church_ledger_journals where organization_id=${q(org)};`),'1');assert.equal(await good(`select sum(delta_cents) from public.church_ledger_lines where organization_id=${q(org)};`),'0')}
  console.log('PASS ledger',level,kind);
 }finally{
  if(initialized)await good(`begin;
   delete from public.church_ledger_lines where organization_id=${q(org)} and unit_id=${q(unit)};
   delete from public.church_ledger_journals where organization_id=${q(org)} and unit_id=${q(unit)};
   delete from public.church_ledger_accounts where organization_id=${q(org)} and unit_id=${q(unit)};
   delete from public.church_ledger_periods where organization_id=${q(org)} and unit_id=${q(unit)};
   delete from public.organizations where id=${q(org)} and slug=${q(slug)};
   delete from auth.users where id=${q(user)} and email=${q(slug+'@example.invalid')};commit;`);
 }
}
for(const level of ['read committed','repeatable read','serializable']){await scenario(level,'close');await scenario(level,'duplicate')}
