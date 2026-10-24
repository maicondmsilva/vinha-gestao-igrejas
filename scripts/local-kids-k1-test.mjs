import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente banco local e dados fictícios.');
// Iterate the same migration transactionally, preserving all pre-existing local data.
const migration=readFileSync('supabase/migrations/20261024020252_kids_identity_foundation.sql','utf8')
 .replaceAll('create table ','create table if not exists ').replaceAll('create index ','create index if not exists ')
 .replaceAll('create function ','create or replace function ')
 .replace('create index if not exists kids_history_person_scope','alter table private.kids_history add column if not exists person_id uuid;\ncreate index if not exists kids_history_person_scope')
 .replace('create or replace function private.kids_allowed',"alter table private.kids_guardians add column if not exists verification_note text not null default '';\ncreate or replace function private.kids_allowed");
const test=readFileSync('supabase/tests/kids_foundation.sql','utf8').replace(/^begin;/,'');
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:'begin;\n'+migration+'\n'+test,encoding:'utf8',timeout:90000,maxBuffer:8*1024*1024});
console.log(r.stdout.split('\n').filter(l=>/^\s*(?:not )?ok \d|^\s*#|^\s*1\.\./.test(l)).join('\n'));
console.error(r.stderr);assert.equal(r.status,0);assert.equal(/not ok \d/.test(r.stdout),false,'Falha nos testes Kids');
console.log('K1: testes locais concluídos com rollback; nenhum acesso à produção.');
