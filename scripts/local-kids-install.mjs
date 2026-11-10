import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente preparação do banco Docker local.');
const migration=readFileSync('supabase/migrations/20261024024447_kids_identity_foundation.sql','utf8')
 .replaceAll('create table ','create table if not exists ').replaceAll('create index ','create index if not exists ')
 .replaceAll('create function ','create or replace function ')
 .replace('create index if not exists kids_history_person_scope','alter table private.kids_history add column if not exists person_id uuid;\ncreate index if not exists kids_history_person_scope')
 .replace('create or replace function private.kids_allowed',"alter table private.kids_guardians add column if not exists verification_note text not null default '';\ncreate or replace function private.kids_allowed");
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-1'],{input:migration,encoding:'utf8',timeout:30000});
if(r.status!==0){console.error(r.stderr);process.exit(1)}
console.log('Kids preparado somente no banco Docker local. Nenhum dado de cliente modificado.');
