// Fixed isolated Docker database only; never accepts a production connection string.
import {spawn,spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const args=['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-At'];
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
const source=readFileSync('supabase/tests/finance_f7.sql','utf8');
const ids=[...new Set(source.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/g))].filter(x=>x!=='00000000-0000-0000-0000-000000000000');
const mapping=new Map(ids.map(id=>[id,randomUUID()]));
const org=mapping.get('bf770000-0000-4000-8000-000000000001'),unit=mapping.get('cf770000-0000-4000-8000-000000000001'),actor=mapping.get('af770000-0000-4000-8000-000000000001'),category=mapping.get('df770000-0000-4000-8000-000000000002');
function sql(input){const r=spawnSync('docker',args,{input,encoding:'utf8',timeout:30000,maxBuffer:5e6});assert.equal(r.status,0,r.stderr);return r.stdout.trim()}
let seed=source.slice(0,source.indexOf('-- F7 assertions'));for(const id of ids)seed=seed.replaceAll(id,mapping.get(id));
seed=seed.replaceAll('f7-synthetic','f7-race-'+org).replaceAll('f7-owner@example.test','f7-race-'+actor+'@example.test');sql(seed+'commit;');
function session(text,user=actor){return `begin;set local lock_timeout='8s';set local statement_timeout='15s';select set_config('request.jwt.claims',${q(JSON.stringify({sub:user,role:'authenticated'}))},true);set local role authenticated;${text}commit;`}
const report=`select public.finance_f6(${q(org)},array[${q(unit)}::uuid],'report',jsonb_build_object('from',current_date,'to',current_date,'dateBy','cash','report','book','export',true));`;
const budget=(id,version,amount)=>`select public.finance_f6(${q(org)},array[${q(unit)}::uuid],'budget',jsonb_build_object('id',${q(id)},'month',date_trunc('month',current_date)::date,'category',${q(category)},'amountCents',${q(amount)},'version',${version},'reason','Planejamento concorrente fictício'));`;
function call(input,onOutput=()=>{}){return new Promise((resolve,reject)=>{const p=spawn('docker',args,{stdio:['pipe','pipe','pipe']});let out='',err='';p.stdout.on('data',b=>{out+=b;onOutput(out)});p.stderr.on('data',b=>err+=b);p.on('error',reject);p.on('close',code=>resolve({code,out,err}));p.stdin.end(input)})}
const exports=await Promise.all(Array.from({length:4},()=>call(session(report))));for(const r of exports)assert.equal(r.code,0,r.err);
assert.equal(sql(`select count(distinct entity_id) from public.audit_logs where organization_id=${q(org)} and action='finance.report_export_prepared';`),'4');
assert.equal(sql(`select count(*) from private.finance_entries where organization_id=${q(org)};`),'2');
console.log('PASS F7: quatro exportações concorrentes auditadas sem criar movimentos financeiros.');
const id=randomUUID();sql(session(budget(id,0,'10000')));
const updates=await Promise.all([call(session(budget(id,1,'15000'))),call(session(budget(id,1,'20000')))]);
assert.equal(updates.filter(r=>r.code===0).length,1);assert.match(updates.find(r=>r.code!==0).err,/40001/);
assert.equal(sql(`select version from private.finance_budgets where id=${q(id)};`),'2');
console.log('PASS F7: edições simultâneas respeitam a versão do orçamento, sem perda silenciosa.');
const finance=randomUUID(),membership=randomUUID();
sql(`begin;select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor,role:'authenticated'}))},true);insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(${q(finance)},'00000000-0000-0000-0000-000000000000','authenticated','authenticated',${q('f7-race-'+finance+'@example.test')},now(),now(),now());insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values(${q(membership)},${q(org)},${q(finance)},'finance','active',${q(unit)});insert into public.membership_unit_access(membership_id,unit_id,access_level) values(${q(membership)},${q(unit)},'admin');commit;`);
let release;const held=new Promise(resolve=>release=resolve);
const revoke=call(`begin;set local lock_timeout='8s';set local statement_timeout='15s';select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor,role:'authenticated'}))},true);select 1 from public.organizations where id=${q(org)} for no key update;select 'F7_LOCK_HELD';select pg_sleep(0.7);update public.organization_memberships set status='suspended' where id=${q(membership)};commit;`,out=>{if(out.includes('F7_LOCK_HELD'))release()});
await held;const denied=call(session(report,finance));const results=await Promise.all([revoke,denied]);assert.equal(results[0].code,0,results[0].err);assert.notEqual(results[1].code,0);assert.match(results[1].err,/42501/);
assert.equal(sql(`select count(*) from public.audit_logs where organization_id=${q(org)} and action='finance.report_export_prepared';`),'4');
console.log('PASS F7: suspensão durante espera impede exportação e não registra falso sucesso. Fixtures locais preservadas.');
