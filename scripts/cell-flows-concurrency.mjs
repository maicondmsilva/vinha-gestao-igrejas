// Only the fixed, isolated Docker database and random synthetic fixtures.
import{spawn}from'node:child_process';import{randomUUID}from'node:crypto';import assert from'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Exige --local-synthetic.');
const org=randomUUID(),unit=randomUUID(),user=randomUUID(),leader=randomUUID(),person=randomUUID(),source=randomUUID(),target=randomUUID(),participant=randomUUID(),a=randomUUID(),b=randomUUID(),slug='flows-race-'+org;
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{const child=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('Tempo excedido no Docker.'))},15000);child.on('error',reject);child.stdout.on('data',c=>{out+=c;onOutput(out)});child.stderr.on('data',c=>err+=c);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});child.stdin.end("set statement_timeout='8s';set lock_timeout='4s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const auth=u=>`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:u,role:'authenticated'}))},true);`,actor=auth(user);
const save=(kind,id,v,data={})=>`select public.cell_flows_save(${q(org)},${q(unit)},${q(kind)},${q(id)},${v},${q(JSON.stringify(data))});`;
const operation=(kind,cell,id,v,data)=>`select public.cell_operations_save(${q(org)},${q(unit)},${q(kind)},${q(cell)},${q(id)},${v},${q(JSON.stringify(data))});`;
async function race(isolation,firstSql,secondSql,allowed,firstActor=actor,success=false){let reached;const ready=new Promise(resolve=>reached=resolve);let finished=false,overlap=false;
 const first=db(`begin isolation level ${isolation};${firstActor}${firstSql}select 'FLOW_LOCK_HELD';select pg_sleep(1);commit;`,out=>{if(out.includes('FLOW_LOCK_HELD'))reached()}).then(r=>{finished=true;return r});
 await Promise.race([ready,first.then(r=>{throw Error('Barreira não alcançada: '+r.err)})]);
 const second=await db(`begin isolation level ${isolation};${actor}select count(*) from public.church_cells;select 'FLOW_SNAPSHOT';${secondSql}commit;`,out=>{if(out.includes('FLOW_SNAPSHOT')&&!finished)overlap=true});
 assert.equal((await first).code,0);assert.ok(overlap);if(second.code===0){assert.ok(success,'Segunda escrita deveria falhar')}else assert.match(second.err,allowed);
 return second.code===0;
}
let initialized=false;
try{
 await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) select id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','flows-'||id||'@example.invalid',now(),now(),now() from unnest(array[${q(user)}::uuid,${q(leader)}::uuid])id;insert into public.organizations(id,name,slug,status) values(${q(org)},'Fluxos concorrentes fictícios',${q(slug)},'active');insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede fictícia','sede','headquarters');insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(user)},'owner','active',${q(unit)}),(${q(org)},${q(leader)},'leader','active',${q(unit)});insert into public.membership_unit_access(membership_id,unit_id,access_level) select id,${q(unit)},'manage' from public.organization_memberships where organization_id=${q(org)} and user_id=${q(leader)};insert into public.people(id,organization_id,unit_id,full_name,status) values(${q(person)},${q(org)},${q(unit)},'Pessoa concorrente fictícia','active');insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by) select id,${q(org)},${q(unit)},'Grupo '||id,1,'19:30','online',${q(user)} from unnest(array[${q(source)}::uuid,${q(target)}::uuid])id;insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by) select id,${q(org)},${q(unit)},'Rede '||id,'active',${q(user)} from unnest(array[${q(a)}::uuid,${q(b)}::uuid])id;insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values(${q(participant)},${q(org)},${q(unit)},${q(source)},${q(person)},'active',${q(user)});commit;`);initialized=true;
 for(const isolation of['read committed','repeatable read','serializable']){
  await good(`delete from public.church_cell_network_parents where organization_id=${q(org)}`);
  await race(isolation,save('hierarchy',a,0,{parent_id:b}),save('hierarchy',b,0,{parent_id:a}),/22023|40001/);console.log('PASS ciclo concorrente',isolation);
  for(const scenario of['decision','source','destination','issuer','roster']){
   await good(`begin;delete from public.church_cell_attendance where organization_id=${q(org)};delete from public.church_cell_meetings where organization_id=${q(org)};delete from public.church_cell_transfers where organization_id=${q(org)};delete from public.church_cell_participants where cell_id=${q(target)};update public.church_cell_participants set status='active',version=1 where id=${q(participant)};update public.organization_memberships set status='active' where organization_id=${q(org)} and user_id=${q(leader)};commit;`);
   const transfer=randomUUID();await good(`begin;${auth(leader)}${save('request',transfer,0,{source_id:participant,target_cell_id:target,source_version:1})}commit;`);
   if(scenario==='decision')await race(isolation,save('accept',transfer,1),save('reject',transfer,1),/40001/);
   if(scenario==='source')await race(isolation,operation('participant',source,participant,1,{person_id:person,status:'inactive'}),save('accept',transfer,1),/40001/);
   if(scenario==='destination')await race(isolation,operation('participant',target,randomUUID(),0,{person_id:person,status:'active'}),save('accept',transfer,1),/40001/);
   if(scenario==='issuer')await race(isolation,`update public.organization_memberships set status='suspended' where organization_id=${q(org)} and user_id=${q(leader)};`,save('accept',transfer,1),/42501|40001/,'');
   if(scenario==='roster'){
    const meeting=randomUUID(),second=await race(isolation,operation('meeting',source,meeting,0,{topic:'Histórico concorrente',meeting_date:'2026-10-19',meeting_time:'19:30',status:'completed',present:[participant]}),save('accept',transfer,1),/40001/,actor,true);
    if(!second)await good(`begin;${actor}${save('accept',transfer,1)}commit;`);
    assert.equal(await good(`select count(*) from public.church_cell_attendance where meeting_id=${q(meeting)} and participant_id=${q(participant)} and present`),'1');
   }
   console.log('PASS transferência concorrente',scenario,isolation);
  }
 }
}finally{
 if(initialized)await good(`begin;delete from private.member_record_numbers where organization_id=${q(org)};delete from private.member_numbering_preferences where organization_id=${q(org)};delete from private.record_counters where organization_id=${q(org)};delete from public.audit_logs where organization_id=${q(org)};delete from public.church_cell_attendance where organization_id=${q(org)};delete from public.church_cell_meetings where organization_id=${q(org)};delete from public.church_cell_transfers where organization_id=${q(org)};delete from public.church_cell_participants where organization_id=${q(org)};delete from public.church_cell_network_parents where organization_id=${q(org)};delete from private.cell_hierarchy_guards where unit_id=${q(unit)};delete from public.church_cell_networks where organization_id=${q(org)};delete from public.church_cells where organization_id=${q(org)};delete from public.people where id=${q(person)} and organization_id=${q(org)};delete from public.organizations where id=${q(org)} and slug=${q(slug)};delete from auth.users where id in(${q(user)},${q(leader)}) and email like 'flows-%@example.invalid';commit;`);
}
