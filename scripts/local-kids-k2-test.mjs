import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente testes Docker local.');
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:readFileSync('supabase/tests/kids_operations.sql','utf8'),encoding:'utf8',timeout:45000,maxBuffer:8e6});
console.log(r.stdout);if(r.status!==0||/not ok|Looks like you failed|ERROR:/.test(r.stdout+r.stderr)){console.error(r.stderr);process.exit(1)}
