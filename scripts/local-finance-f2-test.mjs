import {spawnSync} from 'node:child_process';import {readFileSync,readdirSync} from 'node:fs';import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const db=['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'];
const exists=spawnSync('docker',[...db,'-At','-c',"select to_regclass('private.finance_settlements') is not null"],{encoding:'utf8'});assert.equal(exists.status,0,exists.stderr);
const file=readdirSync('supabase/migrations').find(x=>x.endsWith('_finance_f2_payables_receivables.sql'));
let migration=exists.stdout.trim()==='t'?'':readFileSync('supabase/migrations/'+file,'utf8');
const history=spawnSync('docker',[...db,'-At','-c',"select to_regclass('private.finance_entry_history') is not null"],{encoding:'utf8'});assert.equal(history.status,0,history.stderr);
if(history.stdout.trim()!=='t')migration+='\n'+readFileSync('supabase/migrations/20261021013421_finance_entry_history_classification.sql','utf8');
for(const file of ['finance_f1.sql','finance_f2.sql']){
 const test=readFileSync('supabase/tests/'+file,'utf8').replace(/^begin;/,'').replace(/rollback;\s*$/,'');
 const r=spawnSync('docker',db,{input:'begin;\n'+migration+'\n'+test+'\nrollback;',encoding:'utf8',timeout:90000,maxBuffer:4*1024*1024});console.log(r.stdout);console.error(r.stderr);assert.equal(r.status,0);assert.doesNotMatch(r.stdout,/not ok \d/);
}console.log('F1 + F2 SQL tests rolled back; local fixtures preserved.');
