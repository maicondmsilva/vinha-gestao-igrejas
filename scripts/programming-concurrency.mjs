import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {emptyEventInfo} from '../shared/event-info.ts';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente fixtures sintéticas no Docker local/CI.');
const org=randomUUID(),unit=randomUUID(),event=randomUUID(),owner=randomUUID(),users=[randomUUID(),randomUUID()],q=v=>"'"+String(v).replaceAll("'","''")+"'";
function db(sql,observe=()=>{}){return new Promise((resolve,reject)=>{const p=spawn('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{p.kill();reject(Error('Timeout do teste isolado'))},15000);p.stdout.on('data',c=>{out+=c;observe(out)});p.stderr.on('data',c=>err+=c);p.on('error',reject);p.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});p.stdin.end("set statement_timeout='10s';set lock_timeout='7s';"+sql)})}
async function good(sql){const r=await db(sql);assert.equal(r.code,0,r.err);return r.out.trim()}
const identity=i=>`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:users[i],role:'authenticated'}))},true);`;
const register=`select public.member_agenda_self(${q(org)},'register',${q(unit)},${q(event)});`;
await good(`begin;insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values ${[owner,...users].map(id=>`(${q(id)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q(id+'-agenda-race@example.invalid')},now(),now(),now())`).join(',')};
insert into public.organizations(id,name,slug,status) values(${q(org)},'Agenda concorrente fictícia',${q('agenda-race-'+org)},'active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(${q(unit)},${q(org)},'Igreja fictícia','sede','headquarters');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(${q(org)},${q(owner)},${q(unit)},'owner','active');
insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values ${users.map(id=>`(${q(org)},${q(id)},${q(unit)},'member','active')`).join(',')};
insert into public.people(organization_id,unit_id,auth_user_id,full_name,status) values ${users.map((id,i)=>`(${q(org)},${q(unit)},${q(id)},'Pessoa fictícia ${i}','active')`).join(',')};
insert into private.church_app_events(id,organization_id,unit_id,title,kind,starts_at,ends_at,capacity,status) values(${q(event)},${q(org)},${q(unit)},'Uma vaga fictícia','event',now()+interval '1 hour',now()+interval '2 hours',1,'published');commit;`);

const actor=`set local role authenticated;select set_config('request.jwt.claims',${q(JSON.stringify({sub:owner,role:'authenticated'}))},true);`;
const request=randomUUID(),fields={title:'Série concorrente fictícia',description:'Somente Docker local',kind:'service',startsLocal:new Date(Date.now()+86400000).toISOString().slice(0,16),endsLocal:new Date(Date.now()+90000000).toISOString().slice(0,16),location:'',address:'',capacity:10,category:'',cover:'',repeat:'weekly',count:3};
fields.information=emptyEventInfo();fields.information.venue.format='online';fields.information.venue.onlineUrl='https://example.com/encontro';
const create=`select public.programming_admin(${q(org)},${q(unit)},'create',${q(request)},null,${q(JSON.stringify(fields))}::jsonb);`;
let release;const barrier=new Promise(r=>release=r);
const first=db(`begin;${actor}${create}select 'PROGRAM_LOCK_HELD';select pg_sleep(1.2);commit;`,out=>{if(out.includes('PROGRAM_LOCK_HELD'))release()});
await Promise.race([barrier,first.then(r=>{throw Error('Sem barreira: '+r.err)})]);
const second=await db(`begin;${actor}${create}commit;`),winner=await first;
assert.equal(winner.code,0,winner.err);assert.equal(second.code,0,second.err);
assert.equal(await good(`select count(*) from private.church_app_events where organization_id=${q(org)} and series_id is not null;`),'3');
assert.equal(await good(`select count(*) from private.programming_requests where organization_id=${q(org)};`),'1');
assert.equal(await good(`select count(*) from private.event_information where organization_id=${q(org)};`),'3');
const firstId=await good(`select id from private.church_app_events where organization_id=${q(org)} and series_id is not null order by starts_at limit 1;`);
const detail=JSON.parse((await good(`begin;${actor}select public.programming_admin(${q(org)},${q(unit)},'detail',${q(firstId)});commit;`)).split('\n').at(-1));
const publish=`select public.programming_admin(${q(org)},${q(unit)},'publish',${q(firstId)},1,${q(JSON.stringify({future:true,versions:detail.versions}))}::jsonb);`;
const result=await Promise.all([0,1].map(()=>db(`begin;${actor}${publish}commit;`)));
assert.equal(result.filter(r=>r.code===0).length,1);assert.match(result.find(r=>r.code!==0).err,/member_event_changed/);
assert.equal(await good(`select count(*) from private.church_app_events where organization_id=${q(org)} and series_id is not null and status='published';`),'3');
const edits=await Promise.all([0,1].map(i=>{const info=structuredClone(fields.information);info.contacts.email='equipe'+i+'@example.invalid';return db(`begin;${actor}select public.event_information_admin(${q(org)},${q(unit)},'save',${q(firstId)},2,${q(JSON.stringify(info))}::jsonb);commit;`)}));assert.equal(edits.filter(r=>r.code===0).length,1);assert.match(edits.find(r=>r.code!==0).err,/member_event_changed/);
console.log('Série concorrente validada: duas tentativas, três ocorrências, um recibo; uma publicação vence e a revisão antiga é recusada. Somente Docker fictício.');
