import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco Docker local fictício.');
const run=sql=>spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',timeout:60000});
if(process.argv.includes('--install')){const r=run('begin;'+readFileSync('supabase/migrations/20261027021836_programacao_agenda_layout.sql','utf8')+'\ncommit;notify pgrst, \'reload schema\';');if(r.status!==0){console.error(r.stderr);process.exit(1)}console.log('Migração instalada no Docker local.');}
if(process.argv.includes('--functions-only')){let sql=readFileSync('supabase/migrations/20261027021836_programacao_agenda_layout.sql','utf8');sql=sql.slice(sql.indexOf('create or replace function private.member_event_purchase')).replaceAll('create function ','create or replace function ');const r=run('begin;'+sql+'\ncommit;');if(r.status!==0){console.error(r.stderr);process.exit(1)}}
const r=run(readFileSync('supabase/tests/programming.sql','utf8'));console.log(r.stdout);if(r.status!==0||/not ok/.test(r.stdout)){console.error(r.stderr);process.exit(1)}
