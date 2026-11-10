import {spawn} from 'node:child_process';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local fictício.');
function db(sql,observe=()=>{}){return new Promise((resolve,reject)=>{const p=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{p.kill();reject(Error('Timeout de concorrência'))},20000);p.stdout.on('data',c=>{out+=c;observe(out)});p.stderr.on('data',c=>err+=c);p.on('error',reject);p.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});p.stdin.end("set statement_timeout='14s';set lock_timeout='10s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);assert.doesNotMatch(r.out,/not ok/);return r.out.trim()}
for(const isolation of ['read committed','repeatable read']){
 const seed=randomUUID(),source=readFileSync('supabase/tests/member_services.sql','utf8').replaceAll('member-services-test-',`services-race-${seed}-`).replaceAll("'member-services-test'",`'services-race-${seed}'`).replaceAll("'family-outside'",`'outside-${seed}'`).replaceAll('-family@example.invalid',`-${seed}@example.invalid`);
 const helpers=source.match(/create function pg_temp\.\w+[\s\S]*?\$\$;/g).join('\n');
 await good(source.slice(0,source.indexOf("select throws_ok($$select public.member_agenda_self"))+'commit;');
 const buy=who=>`select pg_temp.actor('${who}');set local role authenticated;select public.member_event_purchase(pg_temp.fi('org'),pg_temp.fi('a'),'buy',pg_temp.fi('event'),jsonb_build_object('id',pg_temp.fi('${who}-race-order')));`;
 let release;const barrier=new Promise(r=>release=r);const first=db('begin;'+helpers+buy('member')+"select 'PAID_HOLD_LOCKED';select pg_sleep(1.2);commit;",out=>{if(out.includes('PAID_HOLD_LOCKED'))release()});
 await Promise.race([barrier,first.then(r=>{throw Error(r.err||'Barreira ausente')})]);
 const second=await db(`begin isolation level ${isolation};`+helpers+"select count(*) from private.member_event_orders;"+buy('second')+'commit;'),winner=await first;
 assert.equal(winner.code,0,winner.err);assert.notEqual(second.code,0);assert.match(second.err,/member_event_full|serialize|serialization/);
 assert.equal(await good(helpers+"select count(*) from private.member_event_orders where event_id=pg_temp.fi('event') and state='holding';"),'1');
 console.log('Ingresso pago: última vaga preservada em '+isolation+'.');
}
