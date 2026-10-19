// Explicitly fixed local target; no production connection strings are accepted.
import{spawn}from'node:child_process';import{randomUUID}from'node:crypto';import assert from'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Exige --local-synthetic.');
const org=randomUUID(),unit=randomUUID(),user=randomUUID(),cell=randomUUID(),network=randomUUID(),other=randomUUID(),slug='networks-race-'+org;
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{const child=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('Tempo excedido no Docker.'))},15000);child.on('error',reject);child.stdout.on('data',c=>{out+=c;onOutput(out)});child.stderr.on('data',c=>err+=c);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const actor=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:user,role:'authenticated'}))},true);`;
const data=(name,status='active')=>({name,supervisor_name:'Responsável fictício',supervisor_person_id:null,status});
const save=(kind,id,version,body)=>`select public.cell_networks_save(${q(org)},${q(unit)},${q(kind)},${q(id)},${version},${q(JSON.stringify(body))});`;
const directory=(version,status)=>`select public.cell_directory_save(${q(org)},${q(unit)},${q(cell)},${version},${q(JSON.stringify({name:'Grupo concorrente',leader_name:'',meeting_day:1,meeting_time:'19:30',meeting_format:'online',location:'',status}))});`;
async function race(isolation,firstSql,secondSql,allowed,firstActor=actor){let reached;const ready=new Promise(resolve=>reached=resolve);let finished=false,overlap=false;
 const first=db(`begin isolation level ${isolation};${firstActor}${firstSql}select 'NETWORK_LOCK_HELD';select pg_sleep(1);commit;`,out=>{if(out.includes('NETWORK_LOCK_HELD'))reached()}).then(r=>{finished=true;return r});
 await Promise.race([ready,first.then(r=>{throw Error('Barreira não alcançada: '+r.err)})]);
 const second=await db(`begin isolation level ${isolation};${actor}select count(*) from public.church_cells;select 'NETWORK_SNAPSHOT';${secondSql}commit;`,out=>{if(out.includes('NETWORK_SNAPSHOT')&&!finished)overlap=true});
 assert.equal((await first).code,0);assert.ok(overlap);assert.notEqual(second.code,0);assert.match(second.err,allowed);
}
let initialized=false;
try{
 await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(user)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('networks-'+user+'@example.invalid')},now(),now(),now());insert into public.organizations(id,name,slug,status) values(${q(org)},'Redes concorrentes fictícias',${q(slug)},'active');insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede fictícia','sede','headquarters');insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(user)},'owner','active',${q(unit)});${actor}${directory(0,'active')}${save('network',network,0,data('Rede inicial'))}${save('network',other,0,data('Outra rede'))}commit;`);initialized=true;
 for(const isolation of['read committed','repeatable read','serializable']){
  let version=Number(await good(`select version from public.church_cell_networks where id=${q(network)}`));
  await race(isolation,save('network',network,version,data('Primeira '+isolation)),save('network',network,version,data('Segunda '+isolation)),/40001/);console.log('PASS rede concorrente',isolation);
  version=Number(await good(`select coalesce((select version from public.church_cell_network_links where cell_id=${q(cell)}),0)`));
  await race(isolation,save('assignment',cell,version,{network_id:network}),save('assignment',cell,version,{network_id:other}),/40001/);console.log('PASS vínculo concorrente',isolation);
  const linkVersion=version+1,otherVersion=Number(await good(`select version from public.church_cell_networks where id=${q(other)}`));
  await race(isolation,save('network',other,otherVersion,data('Outra rede','archived')),save('assignment',cell,linkVersion,{network_id:other}),/22023|40001/);console.log('PASS arquivar rede versus associar',isolation);
  await good(`begin;${actor}${save('network',other,otherVersion+1,data('Outra rede'))}commit;`);
  const cellVersion=Number(await good(`select version from public.church_cells where id=${q(cell)}`));
  await race(isolation,directory(cellVersion,'archived'),save('assignment',cell,linkVersion,{network_id:other}),/42501|40001/);console.log('PASS arquivar grupo versus associar',isolation);
  await good(`begin;${actor}${directory(cellVersion+1,'active')}commit;`);
  await race(isolation,`update public.organizations set status='suspended' where id=${q(org)};`,save('assignment',cell,linkVersion,{network_id:other}),/42501|40001/,'');console.log('PASS suspensão versus vínculo',isolation);
  await good(`update public.organizations set status='active' where id=${q(org)}`);
  assert.equal(await good(`select network_id from public.church_cell_network_links where cell_id=${q(cell)}`),network);
 }
}finally{
 if(initialized)await good(`begin;delete from public.audit_logs where organization_id=${q(org)};delete from public.church_cell_network_links where organization_id=${q(org)} and unit_id=${q(unit)};delete from public.church_cell_networks where organization_id=${q(org)} and unit_id=${q(unit)};delete from public.church_cells where id=${q(cell)} and organization_id=${q(org)};delete from public.organizations where id=${q(org)} and slug=${q(slug)};delete from auth.users where id=${q(user)} and email=${q('networks-'+user+'@example.invalid')};commit;`);
}
