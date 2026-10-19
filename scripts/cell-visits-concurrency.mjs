// Fixed local Docker target only. Never accepts a connection string or remote credentials.
import{spawn}from'node:child_process';import{randomUUID}from'node:crypto';import assert from'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Exige --local-synthetic.');
const org=randomUUID(),unit=randomUUID(),user=randomUUID(),person=randomUUID(),cell=randomUUID(),visit=randomUUID(),slug='visits-race-'+org;
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{const child=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('Tempo excedido no Docker local.'))},15000);child.on('error',reject);child.stdout.on('data',c=>{out+=c;onOutput(out)});child.stderr.on('data',c=>err+=c);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const actor=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:user,role:'authenticated'}))},true);`;
const data=(name,personId=null,date='2026-01-01')=>({person_id:personId,visitor_name:name,visit_date:date,status:'recorded'});
const save=(id,version,body)=>`select public.cell_visits_save(${q(org)},${q(unit)},${q(cell)},${q(id)},${version},${q(JSON.stringify(body))});`;
async function race(isolation,firstSql,secondSql,allowed,firstActor=actor){let reached;const ready=new Promise(resolve=>reached=resolve);let finished=false,overlap=false;
 const first=db(`begin isolation level ${isolation};${firstActor}${firstSql}select 'VISIT_LOCK_HELD';select pg_sleep(1);commit;`,out=>{if(out.includes('VISIT_LOCK_HELD'))reached()}).then(r=>{finished=true;return r});
 await Promise.race([ready,first.then(r=>{throw Error('Barreira não alcançada: '+r.err)})]);
 const second=await db(`begin isolation level ${isolation};${actor}select count(*) from public.church_cells;select 'VISIT_SNAPSHOT';${secondSql}commit;`,out=>{if(out.includes('VISIT_SNAPSHOT')&&!finished)overlap=true});
 assert.equal((await first).code,0);assert.ok(overlap,'conexões devem se sobrepor');assert.notEqual(second.code,0);assert.match(second.err,allowed);
}
let initialized=false;
try{
 await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(user)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('visits-'+user+'@example.invalid')},now(),now(),now());insert into public.organizations(id,name,slug,status) values(${q(org)},'Visitas concorrentes fictícias',${q(slug)},'active');insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede fictícia','sede','headquarters');insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(user)},'owner','active',${q(unit)});insert into public.people(id,organization_id,unit_id,full_name) values(${q(person)},${q(org)},${q(unit)},'Membro fictício concorrente');${actor}select public.cell_directory_save(${q(org)},${q(unit)},${q(cell)},0,'{"name":"Grupo fictício concorrente","leader_name":"","meeting_day":1,"meeting_time":"19:30","meeting_format":"online","location":"","status":"active"}');${save(visit,0,data('Visita fictícia inicial'))}commit;`);initialized=true;
 for(const isolation of['read committed','repeatable read','serializable']){
  const version=Number(await good(`select version from public.church_cell_visits where id=${q(visit)}`));
  await race(isolation,save(visit,version,data('Primeiro '+isolation)),save(visit,version,data('Segundo '+isolation)),/40001|40P01/);
  assert.equal(Number(await good(`select version from public.church_cell_visits where id=${q(visit)}`)),version+1);console.log('PASS visita concorrente',isolation);
  const date=isolation==='read committed'?'2026-01-02':isolation==='repeatable read'?'2026-01-03':'2026-01-04';
  await race(isolation,save(randomUUID(),0,data('Membro',person,date)),save(randomUUID(),0,data('Membro',person,date)),/23505|40001|40P01/);
  assert.equal(Number(await good(`select count(*) from public.church_cell_visits where cell_id=${q(cell)} and person_id=${q(person)} and visit_date=${q(date)}`)),1);console.log('PASS visita duplicada',isolation);
  await race(isolation,`update public.organizations set status='suspended' where id=${q(org)};`,save(randomUUID(),0,data('Recusado após suspensão')),/42501|40001|40P01/,'');
  assert.equal(Number(await good(`select count(*) from public.church_cell_visits where organization_id=${q(org)} and visitor_name='Recusado após suspensão'`)),0);console.log('PASS suspensão versus registro',isolation);
  await good(`update public.organizations set status='active' where id=${q(org)}`);
 }
}finally{
 if(initialized)await good(`begin;delete from public.audit_logs where organization_id=${q(org)};delete from public.church_cell_visits where organization_id=${q(org)} and unit_id=${q(unit)};delete from public.church_cells where id=${q(cell)} and organization_id=${q(org)};delete from public.people where id=${q(person)} and organization_id=${q(org)};delete from public.organizations where id=${q(org)} and slug=${q(slug)};delete from auth.users where id=${q(user)} and email=${q('visits-'+user+'@example.invalid')};commit;`);
}
