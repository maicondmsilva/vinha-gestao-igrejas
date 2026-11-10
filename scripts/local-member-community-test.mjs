import {readFileSync} from 'node:fs';import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco local fictício.');
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:readFileSync('supabase/tests/member_community.sql','utf8'),encoding:'utf8',timeout:60000});console.log(r.stdout);if(r.status!==0||/not ok|Looks like you failed/.test(r.stdout+r.stderr)){console.error(r.stderr);process.exit(1)}
