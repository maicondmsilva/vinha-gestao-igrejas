import{spawnSync}from'node:child_process';import{readFileSync}from'node:fs';import assert from'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const source=readFileSync('supabase/migrations/20261022013523_finance_f6_reports.sql','utf8');
const functions=source.match(/create function[\s\S]*?\$\$;/g).map(x=>x.replace('create function','create or replace function')).join('\n');
const test=readFileSync('supabase/tests/finance_f6.sql','utf8').replace(/^begin;/,'');
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:'begin;\n'+functions+'\n'+test,encoding:'utf8',timeout:90000,maxBuffer:8*1024*1024});console.log(r.stdout.split('\n').filter(x=>/^\s*(?:not )?ok \d|^\s*#|^\s*1\.\./.test(x)).join('\n'));console.error(r.stderr);assert.equal(r.status,0);assert.equal(/not ok \d/.test(r.stdout),false);
