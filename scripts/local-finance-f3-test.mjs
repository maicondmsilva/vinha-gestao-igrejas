import {spawnSync} from 'node:child_process';import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const db=['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'];
const exists=spawnSync('docker',[...db,'-At','-c',"select to_regclass('private.finance_receivers') is not null"],{encoding:'utf8'});assert.equal(exists.status,0,exists.stderr);
const sql=exists.stdout.trim()==='t'?'':readFileSync('supabase/migrations/20261021021930_finance_f3_receiving_accounts.sql','utf8');
const test=readFileSync('supabase/tests/finance_f3.sql','utf8').replace(/^begin;/,'').replace(/rollback;\s*$/,'');
const result=spawnSync('docker',db,{input:'begin;\n'+sql+'\n'+test+'\nrollback;',encoding:'utf8',timeout:90000,maxBuffer:4*1024*1024});console.log(result.stdout);console.error(result.stderr);assert.equal(result.status,0);assert.doesNotMatch(result.stdout,/not ok \d/);console.log('F3 SQL rolled back; local fixtures preserved.');
