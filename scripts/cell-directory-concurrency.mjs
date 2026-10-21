// Docker local/CI only. No URL, credential or production argument is accepted.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Exige --local-synthetic.');
const org=randomUUID(),unit=randomUUID(),user=randomUUID(),id=randomUUID(),slug='cells-race-'+org;
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{const child=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('Teste local excedeu limite.'))},15000);child.on('error',reject);child.stdout.on('data',c=>{out+=c;onOutput(out)});child.stderr.on('data',c=>err+=c);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';"+sql)});}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const actor=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:user,role:'authenticated'}))},true);`;
const input=name=>q(JSON.stringify({name,leader_name:'',meeting_day:3,meeting_time:'19:30',meeting_format:'online',location:'',status:'active'}));
const save=(version,name)=>`select public.cell_directory_save(${q(org)},${q(unit)},${q(id)},${version},${input(name)});`;
let initialized=false;
try{
 await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(user)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('cells-'+user+'@example.invalid')},now(),now(),now());insert into public.organizations(id,name,slug,status) values(${q(org)},'Células concorrentes fictícias',${q(slug)},'active');insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede sintética','sede','headquarters');insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(user)},'owner','active',${q(unit)});${actor}${save(0,'Primeira célula fictícia')}commit;`);initialized=true;
 for(const isolation of['read committed','repeatable read','serializable']){
  const version=Number(await good(`select version from public.church_cells where id=${q(id)}`));
  let ready;const barrier=new Promise(resolve=>ready=resolve);let firstFinished=false,overlap=false;
  const first=db(`begin isolation level ${isolation};${actor}${save(version,'Primeiro editor '+isolation)}select 'CELL_LOCK_HELD';select pg_sleep(1.2);commit;`,out=>{if(out.includes('CELL_LOCK_HELD'))ready()}).then(result=>{firstFinished=true;return result});
  await Promise.race([barrier,first.then(r=>{throw Error('Sem barreira: '+r.err)})]);
  const second=await db(`begin isolation level ${isolation};${actor}select count(*) from public.church_cells;select 'CELL_SECOND_READY';${save(version,'Segundo editor '+isolation)}commit;`,out=>{if(out.includes('CELL_SECOND_READY')&&!firstFinished)overlap=true});
  const accepted=await first;assert.equal(accepted.code,0,accepted.err);assert.ok(overlap,'conexões precisam se sobrepor');assert.notEqual(second.code,0);assert.match(second.err,/40001|40P01/);assert.equal(Number(await good(`select version from public.church_cells where id=${q(id)}`)),version+1);
  console.log('PASS Células concorrentes',isolation);
 }
 assert.equal(Number(await good(`select count(*) from public.audit_logs where entity_type='church_cell' and entity_id=${q(id)}`)),4,'criação e três edições aceitas auditadas, nenhuma edição rejeitada');
}finally{
 if(initialized)await good(`begin;delete from private.member_record_numbers where organization_id=${q(org)};delete from private.member_numbering_preferences where organization_id=${q(org)};delete from private.record_counters where organization_id=${q(org)};delete from public.audit_logs where organization_id=${q(org)} and entity_type='church_cell' and entity_id=${q(id)};delete from public.church_cells where id=${q(id)} and organization_id=${q(org)};delete from public.organizations where id=${q(org)} and slug=${q(slug)};delete from auth.users where id=${q(user)} and email=${q('cells-'+user+'@example.invalid')};commit;`);
}
