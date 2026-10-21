// Docker local only. Independent psql connections; no production URL/credentials.
import {spawn,spawnSync} from 'node:child_process';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const db=['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-At'];
const sql=readFileSync('supabase/tests/finance_f4.sql','utf8'),ids=[...new Set(sql.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/g))].filter(x=>x!=='00000000-0000-0000-0000-000000000000'),map=new Map(ids.map(x=>[x,randomUUID()]));
const replace=s=>ids.reduce((a,k)=>a.replaceAll(k,map.get(k)),s).replaceAll('f4-synthetic','f4-concurrent-'+Date.now()).replaceAll('f4-owner@example.test','f4-concurrent-'+Date.now()+'@example.test');
const setup=replace(sql.slice(0,sql.indexOf("select set_config('f4.proof'")))+'\ncommit;';
const prep=spawnSync('docker',db,{input:setup,encoding:'utf8',maxBuffer:4e6});assert.equal(prep.status,0,prep.stderr);
const org=map.get('bf400000-0000-4000-8000-000000000001'),receiver=map.get('ff400000-0000-4000-8000-000000000001'),order=map.get('af410000-0000-4000-8000-000000000001');
const proof={reference:order,externalId:'race'+Date.now(),receiverExternalId:'123',environment:'production',currency:'BRL',gross:'10000',net:'9650',refunded:'0',fees:[{kind:'processing',amount:'350'}],state:'approved',settlement:'available',occurredAt:new Date(Date.now()-1000).toISOString(),paidDate:new Date().toISOString().slice(0,10),method:'pix',installments:1};
const query=`select public.finance_digital_ingest('${receiver}','${JSON.stringify(proof)}');`;
function call(){return new Promise((resolve,reject)=>{const p=spawn('docker',db,{stdio:['pipe','pipe','pipe']});let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);p.on('error',reject);p.on('close',code=>code?reject(Error(err)):resolve(out));p.stdin.end(query)})}
await Promise.all([call(),call(),call(),call()]);
const result=spawnSync('docker',db,{input:`select count(*)||':'||sum(case when kind='income' then amount_cents else -amount_cents end) from private.finance_entries where organization_id='${org}';`,encoding:'utf8'});assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.trim(),'2:9650');
console.log('F4 concorrência real: quatro eventos simultâneos, uma receita e uma taxa; líquido 9650. Apenas fixtures fictícias locais preservadas.');
