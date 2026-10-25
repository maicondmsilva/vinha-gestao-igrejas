import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local.');
const run=sql=>spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',timeout:60000});
if(!process.argv.includes('--test-only')){let sql=readFileSync('supabase/migrations/20261025155022_member_agenda_inbox.sql','utf8');if(process.argv.includes('--functions-only'))sql=sql.slice(sql.indexOf('create function private.member_event_enabled')).replaceAll('create function ','create or replace function ');const r=run('begin;'+sql+'\ncommit;');if(r.status!==0){console.error(r.stderr);process.exit(1)}}
const r=run(readFileSync('supabase/tests/member_agenda.sql','utf8'));console.log(r.stdout);if(r.status!==0||/not ok/.test(r.stdout)){console.error(r.stderr);process.exit(1)}
