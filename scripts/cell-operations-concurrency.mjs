// Tests are restricted to the fixed Docker container. No remote URL/credential.
import {spawn}from'node:child_process';import{randomUUID}from'node:crypto';import assert from'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Exige --local-synthetic.');
const org=randomUUID(),unit=randomUUID(),user=randomUUID(),cell=randomUUID(),person=randomUUID(),participant=randomUUID(),meeting=randomUUID(),slug='cell-ops-race-'+org;
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{const child=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('Tempo de teste excedido.'))},15000);child.on('error',reject);child.stdout.on('data',c=>{out+=c;onOutput(out)});child.stderr.on('data',c=>err+=c);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const actor=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:user,role:'authenticated'}))},true);`;
const command=(kind,id,version,data)=>`select public.cell_operations_save(${q(org)},${q(unit)},${q(kind)},${q(cell)},${q(id)},${version},${q(JSON.stringify(data))});`;
const meetingData=(topic,present=[participant])=>({topic,meeting_date:'2026-10-19',meeting_time:'19:30',status:'completed',present});
async function race(isolation,firstSql,secondSql,allowed){let reached;const ready=new Promise(resolve=>reached=resolve);let finished=false,overlap=false;
 const first=db(`begin isolation level ${isolation};${actor}${firstSql}select 'OPERATION_LOCK_HELD';select pg_sleep(1.2);commit;`,out=>{if(out.includes('OPERATION_LOCK_HELD'))reached()}).then(r=>{finished=true;return r});
 await Promise.race([ready,first.then(r=>{throw Error('Barreira não alcançada: '+r.err)})]);
 const second=await db(`begin isolation level ${isolation};${actor}select count(*) from public.church_cells;select 'SECOND_SNAPSHOT';${secondSql}commit;`,out=>{if(out.includes('SECOND_SNAPSHOT')&&!finished)overlap=true});
 assert.equal((await first).code,0);assert.ok(overlap,'é necessário sobrepor as conexões');assert.notEqual(second.code,0,'segunda gravação deve ser recusada');assert.match(second.err,allowed);
}
let initialized=false;
try{
 await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(user)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('ops-'+user+'@example.invalid')},now(),now(),now());insert into public.organizations(id,name,slug,status) values(${q(org)},'Concorrência fictícia',${q(slug)},'active');insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede fictícia','sede','headquarters');insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(user)},'owner','active',${q(unit)});insert into public.people(id,organization_id,unit_id,full_name) values(${q(person)},${q(org)},${q(unit)},'Pessoa concorrente fictícia');${actor}select public.cell_directory_save(${q(org)},${q(unit)},${q(cell)},0,'{"name":"Grupo concorrente","leader_name":"","meeting_day":3,"meeting_time":"19:30","meeting_format":"online","location":"","status":"active"}');select public.ministry_language_save(${q(org)},0,'{}');${command('participant',participant,0,{person_id:person,status:'active'})}${command('meeting',meeting,0,meetingData('Encontro inicial'))}commit;`);initialized=true;
 for(const isolation of['read committed','repeatable read','serializable']){
  let version=Number(await good(`select version from public.ministry_language where organization_id=${q(org)}`));
  const lang=(name)=>`select public.ministry_language_save(${q(org)},${version},${q(JSON.stringify({celulas:name}))});`;
  await race(isolation,lang('Primeiro '+isolation),lang('Segundo '+isolation),/40001|40P01/);assert.equal(Number(await good(`select version from public.ministry_language where organization_id=${q(org)}`)),version+1);console.log('PASS nomenclatura concorrente',isolation);
  version=Number(await good(`select version from public.church_cell_meetings where id=${q(meeting)}`));
  await race(isolation,command('meeting',meeting,version,meetingData('Primeiro '+isolation)),command('meeting',meeting,version,meetingData('Segundo '+isolation)),/40001|40P01/);assert.equal(Number(await good(`select version from public.church_cell_meetings where id=${q(meeting)}`)),version+1);console.log('PASS chamada concorrente',isolation);
  version=Number(await good(`select version from public.church_cell_participants where id=${q(participant)}`));
  await race(isolation,command('participant',participant,version,{person_id:person,status:'inactive'}),command('meeting',randomUUID(),0,meetingData('Não pode conter inativo')),/22023|40001|40P01/);assert.equal(Number(await good(`select count(*) from public.church_cell_meetings where organization_id=${q(org)}`)),1);console.log('PASS inativação versus nova chamada',isolation);
  await good(`begin;${actor}${command('participant',participant,version+1,{person_id:person,status:'active'})}commit;`);
 }
 assert.equal(Number(await good(`select count(*) from public.audit_logs where organization_id=${q(org)} and action='language.updated'`)),4);
 assert.equal(Number(await good(`select count(*) from public.audit_logs where organization_id=${q(org)} and action='cell.meeting.saved'`)),4);
 assert.equal(Number(await good(`select count(*) from public.church_cell_attendance where meeting_id=${q(meeting)} and present`)),1);
}finally{
 if(initialized)await good(`begin;delete from public.audit_logs where organization_id=${q(org)};delete from public.church_cell_attendance where organization_id=${q(org)};delete from public.church_cell_meetings where organization_id=${q(org)};delete from public.church_cell_participants where organization_id=${q(org)};delete from public.church_cells where id=${q(cell)} and organization_id=${q(org)};delete from public.ministry_language where organization_id=${q(org)};delete from public.organizations where id=${q(org)} and slug=${q(slug)};delete from auth.users where id=${q(user)} and email=${q('ops-'+user+'@example.invalid')};commit;`);
}
