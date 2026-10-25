import {readFileSync} from 'node:fs';import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local fictício.');
const run=sql=>spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',timeout:60000});
if(process.argv.includes('--functions-only')){const source=readFileSync('supabase/migrations/20261025213320_member_learning_bible.sql','utf8'),r=run(source.slice(source.indexOf('create function private.scripture_valid')).replaceAll('create function ','create or replace function '));if(r.status!==0){console.error(r.stderr);process.exit(1)}}
const r=run(readFileSync('supabase/tests/member_learning.sql','utf8'));console.log(r.stdout.split('\n').filter(l=>/ok \d|1\.\.\d|ERROR|failed/.test(l)).join('\n'));if(r.status!==0||/not ok|Looks like you failed/.test(r.stdout+r.stderr)){console.error(r.stderr);process.exit(1)}
