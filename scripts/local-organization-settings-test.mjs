import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco Docker local.');
const source=readFileSync('supabase/migrations/20261024213649_organization_settings_source.sql','utf8').replaceAll('create table ','create table if not exists ').replaceAll('create index ','create index if not exists ').replaceAll('create function ','create or replace function ');
for(const [label,sql] of [['install',source],['test',readFileSync('supabase/tests/organization_settings.sql','utf8')]]){
 const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-1'],{input:sql,encoding:'utf8',timeout:45000,maxBuffer:8e6});
 process.stdout.write(r.stdout||'');if(r.status!==0||/not ok|Looks like you failed|ERROR:/.test(r.stdout+r.stderr)){process.stderr.write(r.stderr||'');throw Error(label+' falhou');}
}
