import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local isolated opt-in required.');
const migration=readFileSync('supabase/migrations/20261021202619_finance_entry_full_revision.sql','utf8').replace(/^begin;/,'').replace(/commit;\s*$/,'').replaceAll('create function','create or replace function');
const tests=readFileSync('supabase/tests/finance_entry_revision.sql','utf8').replace(/^begin;/,'');
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:'begin;\n'+migration+'\n'+tests,encoding:'utf8',timeout:90000,maxBuffer:4*1024*1024});
console.log(r.stdout.split('\n').filter(x=>/^\s*(?:not )?ok \d|^\s*#|^\s*1\.\./.test(x)).join('\n'));console.error(r.stderr);assert.equal(r.status,0);assert.equal(/not ok \d/.test(r.stdout),false,'SQL assertion failed');console.log('Revisões testadas; todas as alterações fictícias revertidas.');
