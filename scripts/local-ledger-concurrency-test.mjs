import {spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const database='l4_ledger_qa_'+randomBytes(6).toString('hex'),container='supabase_db_vinha';
if(!/^l4_ledger_qa_[a-f0-9]{12}$/.test(database))throw Error('Invalid isolated database.');
const docker=(args,input)=>spawnSync('docker',['exec','-i',container,...args],{input,encoding:'utf8',maxBuffer:32*1024*1024,timeout:60000});
function sql(input){const result=docker(['psql','-X','-q','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],input);assert.equal(result.status,0,'isolated schema preparation failed')}
let created=false;
try{
 const result=docker(['createdb','-U','postgres','-T','template0',database]);assert.equal(result.status,0);created=true;
 const dump=docker(['pg_dump','-U','postgres','-d','postgres','--schema-only','--no-owner','--schema=public','--schema=private','--schema=auth','--schema=extensions']);assert.equal(dump.status,0);
 sql('create schema extensions;create extension pgcrypto with schema extensions;create extension "uuid-ossp" with schema extensions;create extension pg_stat_statements with schema extensions;');
 sql(dump.stdout.split('\n').filter(line=>!line.startsWith('ALTER DEFAULT PRIVILEGES ')).join('\n').replace(/CREATE SCHEMA (public|extensions);/g,'CREATE SCHEMA IF NOT EXISTS $1;'));
 sql("insert into public.saas_plans(id,code,name,base_price_cents) values('ledger-synthetic','ledger-synthetic','Synthetic ledger test plan',1000);insert into public.saas_module_catalog(code,name,monthly_price_cents) values('finance','Synthetic finance module',0);insert into public.saas_plan_modules(plan_id,module_code,included) values('ledger-synthetic','finance',true);");
 const tests=spawnSync(process.execPath,['scripts/ledger-concurrency.mjs'],{env:{...process.env,VINHA_LOCAL_LEDGER_TEST_DATABASE:database},stdio:'inherit',timeout:120000});process.exitCode=tests.status??1;
}finally{
 if(created){const result=docker(['psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',`DROP DATABASE "${database}" WITH (FORCE);`]);assert.equal(result.status,0,'temporary ledger cleanup');console.log('Temporary ledger database removed; existing local data preserved.');}
}
