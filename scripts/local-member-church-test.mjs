import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local e dados fictícios.');
const run=sql=>spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-1'],{input:sql,encoding:'utf8',timeout:60000});
const migration=readFileSync('supabase/migrations/20261025100256_member_church_preferences_transfers.sql','utf8');
if(!process.argv.includes('--test-only')){const source=process.argv.includes('--functions-only')?migration.slice(migration.indexOf('create function private.member_church(')).replaceAll('create function ','create or replace function '):migration;const applied=run(source);if(applied.status!==0){console.error(applied.stderr);process.exit(1)}}
const test=run(readFileSync('supabase/tests/member_church.sql','utf8'));console.log(test.stdout);if(test.status!==0||/not ok/.test(test.stdout)){console.error(test.stderr);process.exit(1)}
console.log('Seleção, conteúdo público e transferência verificados somente no Docker local.');
