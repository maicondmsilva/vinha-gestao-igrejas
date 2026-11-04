import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco Docker local fictício.');
const sql=readFileSync('supabase/migrations/20261104091208_eventos_etapa2_tickets_checkout.sql','utf8');
const body=process.argv.includes('--install')?'begin;'+sql+'\ncommit;':(sql.match(/create (?:or replace )?function [\s\S]*?\$\$;/g)||[]).map(s=>s.replace(/^create (?:or replace )?function/,'create or replace function')).join('\n')+'\n'+(sql.match(/(?:revoke|grant) [^;]+;/g)||[]).join('\n')+'\n'+(sql.match(/create trigger [^;]+;/g)||[]).map(t=>{const m=t.match(/^create trigger (\w+) [\s\S]*? on ([\w.]+) /);return 'drop trigger if exists '+m[1]+' on '+m[2]+';'+t}).join('\n');
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:body,encoding:'utf8',timeout:60000});if(r.status!==0){console.error(r.stdout);console.error(r.stderr);process.exit(1)}console.log('Estrutura local da etapa 2 validada.');

if(process.argv.includes('--test')){const t=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:readFileSync('supabase/tests/event_stage2.sql','utf8'),encoding:'utf8',timeout:60000});console.log(t.stdout);console.error(t.stderr);if(t.status!==0||t.stdout.includes('not ok'))process.exit(1)}
