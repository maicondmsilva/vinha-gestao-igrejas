import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco Docker local.');
for(const file of ['supabase/migrations/20261024213655_member_self_service_identity.sql','supabase/tests/member_self_service.sql']){
 let sql=readFileSync(file,'utf8');const install=file.includes('migrations');
 if(install)sql=sql.replaceAll('create table ','create table if not exists ').replaceAll('create index ','create index if not exists ').replaceAll('create unique index ','create unique index if not exists ').replaceAll('create function ','create or replace function ');
 const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:install?'begin;'+sql+'commit;':sql,encoding:'utf8',timeout:45000,maxBuffer:8e6});
 if(r.status||/not ok|Looks like you failed|ERROR:/.test(r.stdout+r.stderr)){process.stdout.write(r.stdout);process.stderr.write(r.stderr);process.exit(1)}
 console.log(install?'Migração local instalada.':r.stdout.split('\n').filter(l=>/ok \d|1\.\./.test(l)).join('\n'));
}
