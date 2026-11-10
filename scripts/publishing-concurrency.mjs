import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente fixtures sintéticas no Docker local/CI.');
const org=randomUUID(),unit=randomUUID(),secondUnit=randomUUID(),item=randomUUID(),owner=randomUUID(),q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,observe=()=>{}){return new Promise((resolve,reject)=>{const p=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{p.kill();reject(Error('Timeout do teste isolado'))},15000);p.stdout.on('data',c=>{out+=c;observe(out)});p.stderr.on('data',c=>err+=c);p.on('error',reject);p.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});p.stdin.end("set statement_timeout='10s';set lock_timeout='7s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}

const actor=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:owner,role:'authenticated'}))},true);`;
await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(owner)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q(owner+'@example.invalid')},now(),now(),now());
insert into public.organizations(id,name,slug,status) values(${q(org)},'Publicação concorrente fictícia',${q('publisher-race-'+org)},'active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'A fictícia','a','headquarters'),(${q(secondUnit)},${q(org)},'B fictícia','b','campus');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(${q(org)},${q(owner)},${q(unit)},'owner','active');commit;`);
const fields={kind:'notice',title:'Aviso de teste concorrente',body:'Somente local',source:'',poster:'',category:'',channel:'',scope:'selected',targets:[unit,secondUnit],group:'',groupVersion:0,provider:'',starts:'',ends:'',download:false,share:true};
await good(`begin;${actor}select public.publishing_admin(${q(org)},${q(unit)},'save',${q(item)},0,${q(JSON.stringify(fields))}::jsonb);commit;`);
const publish=`select public.publishing_admin(${q(org)},${q(unit)},'publish',${q(item)},1,'{}');`;
let release;const barrier=new Promise(r=>release=r);
const first=db(`begin;${actor}${publish}select 'PUBLISH_LOCK_HELD';select pg_sleep(1.2);commit;`,out=>{if(out.includes('PUBLISH_LOCK_HELD'))release()});
await Promise.race([barrier,first.then(r=>{throw Error('Sem barreira: '+r.err)})]);
const second=await db(`begin;${actor}${publish}commit;`),winner=await first;
assert.equal(winner.code,0,winner.err);assert.notEqual(second.code,0);assert.match(second.err,/publishing_changed/);
assert.equal(await good(`select count(*) from private.member_publications where publishing_id=${q(item)} and published;`),'2');
assert.equal(await good(`select count(distinct unit_id) from private.member_publications where publishing_id=${q(item)};`),'2');
console.log('Duas publicações concorrentes: uma vence, revisão antiga recusada, exatamente duas cópias para igrejas autorizadas. Somente Docker fictício.');
