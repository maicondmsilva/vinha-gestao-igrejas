import {spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
if(process.env.GITHUB_ACTIONS!=='true'&&process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local fictício.');
const seed=randomUUID(),source=readFileSync('supabase/tests/kids_operations.sql','utf8').replaceAll('kids-k2-test-',`kids-k2-race-${seed}-`).replaceAll("'kids-k2-test'",`'kids-k2-race-${seed}'`).replaceAll("'kids-k2-other'",`'kids-k2-other-${seed}'`);
const helpers=source.match(/create function pg_temp\.\w+[\s\S]*?\$\$;/g).join('\n');
const auth=`set local role authenticated;select pg_temp.actor('owner');`;
function db(sql,onOutput=()=>{}){return new Promise((resolve,reject)=>{const p=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']);let out='',err='';const timer=setTimeout(()=>{p.kill();reject(Error('Tempo limite local.'))},25000);p.on('error',reject);p.stdout.on('data',c=>{out+=c;onOutput(out)});p.stderr.on('data',c=>err+=c);p.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});p.stdin.on('error',()=>{});p.stdin.end(`set statement_timeout='18s';set lock_timeout='12s';${helpers}${sql}`)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
async function overlap(first,second){let ready;const barrier=new Promise(r=>ready=r);let done=false,overlapped=false;
 const one=db(first,o=>{if(o.includes('K2_LOCK_HELD'))ready()}).then(r=>{done=true;return r});
 await Promise.race([barrier,one.then(r=>{throw Error('Sem barreira: '+r.err)})]);const two=await db(second,o=>{if(o.includes('K2_SECOND_READY')&&!done)overlapped=true});const firstResult=await one;assert.equal(firstResult.code,0,firstResult.err);assert.ok(overlapped,'Conexões devem se sobrepor.');return two;
}
let initialized=false;
try{
 // Strip duplicated helpers from the setup since every connection installs them.
 const fixture=source.slice(source.indexOf('insert into auth.users'),source.indexOf("select ok(not has_function_privilege")).replace(/create function pg_temp\.\w+[\s\S]*?\$\$;/g,'');
 await good('begin;'+fixture+'commit;');initialized=true;
 const setup=`${auth}
 select pg_temp.op('room','room',0,'{"name":"Sala A","location":"","capacity":1,"active":true}');
 select pg_temp.op('class','class',0,'{"name":"Turma A","minMonths":0,"maxMonths":215,"active":true}');
 select pg_temp.op('session','session',0,jsonb_build_object('name','Sessão concorrente','startsAt',now(),'endsAt',now()+interval '2 hours'));
 select pg_temp.op('group','group',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'roomId',pg_temp.ki('room'),'classId',pg_temp.ki('class'),'capacity',1,'minStaff',1));
 select pg_temp.op('assignment','teacher-assignment',0,jsonb_build_object('sessionId',pg_temp.ki('session'),'personId',pg_temp.ki('teacher-person'),'groupId',pg_temp.ki('group'),'role','teacher','canCare',false,'active',true));
 select pg_temp.op('sessionState','session',1,'{"status":"open"}');`;
 await good('begin;'+setup+'commit;');
 const cleanPresence=`begin;delete from private.kids_custody_events where organization_id=pg_temp.ki('org') and attendance_id is not null;delete from private.kids_attendance where organization_id=pg_temp.ki('org');delete from private.kids_operation_requests where organization_id=pg_temp.ki('org') and result->>'id' in(pg_temp.ki('attendance')::text,pg_temp.ki('attendance2')::text);update private.kids_session_rooms set occupied=0 where organization_id=pg_temp.ki('org');commit;`;
 for(const isolation of ['read committed','repeatable read','serializable']){
  const second=await overlap(`begin isolation level ${isolation};${auth}select pg_temp.op('checkin','attendance',0,pg_temp.entry());select 'K2_LOCK_HELD';select pg_sleep(1);commit;`,`begin isolation level ${isolation};${auth}select 'K2_SECOND_READY';select pg_temp.op('checkin','attendance2',0,pg_temp.entry('child2'));commit;`);
  assert.notEqual(second.code,0);assert.match(second.err,/40001|40P01/);assert.equal(await good(`select count(*) from private.kids_attendance where organization_id=pg_temp.ki('org')`),'1');
  console.log('PASS K2 última vaga: '+isolation);await good(cleanPresence);
 }
 const replay=`select public.kids_operations_save(pg_temp.ki('org'),pg_temp.ki('unit'),pg_temp.ki('same-request'),'checkin',pg_temp.ki('attendance'),0,pg_temp.entry());`;
 const repeated=await overlap(`begin;${auth}${replay}select 'K2_LOCK_HELD';select pg_sleep(1);commit;`,`begin;${auth}select 'K2_SECOND_READY';${replay}commit;`);assert.equal(repeated.code,0,repeated.err);assert.equal(await good(`select count(*) from private.kids_attendance where organization_id=pg_temp.ki('org')`),'1');console.log('PASS K2 reenvio simultâneo não duplica presença');
 const revoked=await overlap(`begin;update private.kids_guardians set status='revoked',approved_by=null,approved_at=null where profile_id=pg_temp.ki('child-profile');select 'K2_LOCK_HELD';select pg_sleep(1);commit;`,`begin;${auth}select 'K2_SECOND_READY';select pg_temp.op('checkout','attendance',1,pg_temp.exit_data());commit;`);assert.notEqual(revoked.code,0);assert.match(revoked.err,/42501/);assert.equal(await good(`select status from private.kids_attendance where id=pg_temp.ki('attendance')`),'present');console.log('PASS K2 revogação concorrente impede retirada');
 await good(cleanPresence);
 const suspended=await overlap(`begin;update public.organization_memberships set status='suspended' where id=pg_temp.ki('teacher-membership');select 'K2_LOCK_HELD';select pg_sleep(1);commit;`,`begin;${auth}select 'K2_SECOND_READY';select pg_temp.op('checkin','attendance',0,pg_temp.entry('child2'));commit;`);assert.notEqual(suspended.code,0);assert.match(suspended.err,/kids_staff_insufficient/);console.log('PASS K2 suspensão da equipe impede nova entrada');
}finally{
 if(initialized)await good(`begin;
 delete from private.kids_custody_events where organization_id in(pg_temp.ki('org'),pg_temp.ki('foreign'));
 delete from private.kids_operation_requests where organization_id in(pg_temp.ki('org'),pg_temp.ki('foreign'));
 delete from private.kids_attendance where organization_id=pg_temp.ki('org');delete from private.kids_assignments where organization_id=pg_temp.ki('org');delete from private.kids_session_rooms where organization_id=pg_temp.ki('org');delete from private.kids_sessions where organization_id=pg_temp.ki('org');delete from private.kids_rooms where organization_id=pg_temp.ki('org');delete from private.kids_classes where organization_id=pg_temp.ki('org');delete from private.kids_operation_mutex where unit_id=pg_temp.ki('unit');
 delete from private.kids_requests where organization_id=pg_temp.ki('org');delete from private.kids_history where organization_id=pg_temp.ki('org');delete from private.kids_care where organization_id=pg_temp.ki('org');delete from private.kids_guardians where organization_id=pg_temp.ki('org');delete from private.kids_profiles where organization_id=pg_temp.ki('org');
 delete from private.member_record_numbers where organization_id=pg_temp.ki('org');delete from private.member_numbering_preferences where organization_id=pg_temp.ki('org');delete from private.record_counters where organization_id=pg_temp.ki('org');
 delete from public.organizations where id in(pg_temp.ki('org'),pg_temp.ki('foreign')) and slug in('kids-k2-race-${seed}','kids-k2-other-${seed}');
 delete from auth.users where id in(select pg_temp.ki(x) from unnest(array['owner','teacher','reception','other','teacher2']) x) and email like '%-k2@example.invalid';commit;`);
}
