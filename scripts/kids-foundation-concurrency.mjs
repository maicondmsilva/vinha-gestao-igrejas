import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local fictício.');
const org=randomUUID(),unit=randomUUID(),owner=randomUUID(),actor=randomUUID(),membership=randomUUID(),person=randomUUID(),profile=randomUUID(),slug='kids-race-'+org;
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{
 const child=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']);let out='',err='';
 const timer=setTimeout(()=>{child.kill();reject(Error('Concorrência local excedeu limite.'))},20000);
 child.on('error',reject);child.stdout.on('data',c=>{out+=c;onOutput(out)});child.stderr.on('data',c=>err+=c);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.on('error',()=>{});child.stdin.end("set statement_timeout='12s';set lock_timeout='8s';"+sql);
})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const session=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor,role:'authenticated'}))},true);`;
const save=(version,status)=>`select public.kids_save(${q(org)},${q(unit)},${q(randomUUID())},'profile',${q(profile)},${version},${q(JSON.stringify({personId:person,status}))});`;
async function overlapping(firstSQL,secondSQL){let ready;const barrier=new Promise(r=>ready=r);let finished=false,overlap=false;
 const first=db(firstSQL,out=>{if(out.includes('KIDS_LOCK_HELD'))ready()}).then(r=>{finished=true;return r});
 await Promise.race([barrier,first.then(r=>{throw Error('Barreira não alcançada: '+r.err)})]);
 const second=await db(secondSQL,out=>{if(out.includes('KIDS_SECOND_READY')&&!finished)overlap=true});const one=await first;assert.equal(one.code,0,one.err);assert.ok(overlap,'As conexões devem se sobrepor.');return second;
}
let initialized=false;
try{
 await good(`begin;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 (${q(owner)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('kids-'+owner+'@example.invalid')},now(),now(),now()),
 (${q(actor)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('kids-'+actor+'@example.invalid')},now(),now(),now());
 insert into public.organizations(id,name,slug,status) values(${q(org)},'Kids concorrência fictícia',${q(slug)},'active');
 insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Sede Kids fictícia','sede','headquarters');
 insert into public.organization_memberships(organization_id,user_id,role,status,default_unit_id) values(${q(org)},${q(owner)},'owner','active',${q(unit)});
 insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values(${q(membership)},${q(org)},${q(actor)},'admin','active',${q(unit)});
 insert into public.people(id,organization_id,unit_id,full_name,birth_date,status) values(${q(person)},${q(org)},${q(unit)},'Criança concorrência fictícia','2018-01-01','active');
 ${session}${save(0,'active')}commit;`);initialized=true;
 for(const isolation of ['read committed','repeatable read','serializable']){
  const version=Number(await good(`select version from private.kids_profiles where id=${q(profile)}`));
  const second=await overlapping(`begin isolation level ${isolation};${session}${save(version,'archived')}select 'KIDS_LOCK_HELD';select pg_sleep(1);commit;`,`begin isolation level ${isolation};${session}select 'KIDS_SECOND_READY';${save(version,'active')}commit;`);
  assert.notEqual(second.code,0);assert.match(second.err,/40001|40P01/);assert.equal(Number(await good(`select version from private.kids_profiles where id=${q(profile)}`)),version+1);
  console.log('PASS Kids: edição simultânea '+isolation);
 }
 const request=randomUUID(),newPerson=randomUUID(),data={name:'Visitante idempotente fictício',birthDate:'2020-01-01',phone:''};
 const personSave=`select public.kids_save(${q(org)},${q(unit)},${q(request)},'person',${q(newPerson)},0,${q(JSON.stringify(data))});`;
 const retry=await overlapping(`begin;${session}${personSave}select 'KIDS_LOCK_HELD';select pg_sleep(1);commit;`,`begin;${session}select 'KIDS_SECOND_READY';${personSave}commit;`);
 assert.equal(retry.code,0,retry.err);assert.equal(Number(await good(`select count(*) from public.people where id=${q(newPerson)}`)),1);console.log('PASS Kids: reenvio concorrente não duplica pessoa');
 const version=Number(await good(`select version from private.kids_profiles where id=${q(profile)}`));
 const revoked=await overlapping(`begin;update public.organization_memberships set status='suspended' where id=${q(membership)};select 'KIDS_LOCK_HELD';select pg_sleep(1);commit;`,`begin;${session}select 'KIDS_SECOND_READY';${save(version,'active')}commit;`);
 assert.notEqual(revoked.code,0);assert.match(revoked.err,/42501/);assert.equal(Number(await good(`select version from private.kids_profiles where id=${q(profile)}`)),version);console.log('PASS Kids: suspensão concorrente impede gravação');
}finally{
 if(initialized)await good(`begin;
 delete from private.kids_requests where organization_id=${q(org)};
 delete from private.kids_history where organization_id=${q(org)};
 delete from private.kids_care where organization_id=${q(org)};
 delete from private.kids_guardians where organization_id=${q(org)};
 delete from private.kids_profiles where organization_id=${q(org)};
 delete from private.member_record_numbers where organization_id=${q(org)};
 delete from private.member_numbering_preferences where organization_id=${q(org)};
 delete from private.record_counters where organization_id=${q(org)};
 delete from public.organizations where id=${q(org)} and slug=${q(slug)};
 delete from auth.users where id in (${q(owner)},${q(actor)}) and email like 'kids-%@example.invalid';commit;`);
}
