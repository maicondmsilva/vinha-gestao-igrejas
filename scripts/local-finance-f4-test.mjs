import {spawnSync} from 'node:child_process';import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Local isolated opt-in required.');
const db=['exec','-i','supabase_db_vinha','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'];
const migration=readFileSync('supabase/migrations/20261021093022_finance_f4_digital_receipts.sql','utf8');
const check=spawnSync('docker',[...db,'-At','-c',"select to_regclass('private.finance_purposes') is not null"],{encoding:'utf8'});assert.equal(check.status,0,check.stderr);
// Local iteration never creates migration-history entries. Every fixture rolls back.
const setup=check.stdout.trim()==='t'?migration.match(/create function[\s\S]*?\$\$;/g).map(x=>x.replace('create function','create or replace function')).join('\n'):migration;
const checkout=readFileSync('supabase/migrations/20261021103532_finance_f4_checkout_reservations.sql','utf8');
const checkoutCheck=spawnSync('docker',[...db,'-At','-c',"select to_regclass('private.finance_checkout_attempts') is not null"],{encoding:'utf8'});assert.equal(checkoutCheck.status,0,checkoutCheck.stderr);
const checkoutSetup=checkoutCheck.stdout.trim()==='t'?checkout.match(/create function[\s\S]*?\$\$;/g).map(x=>x.replace('create function','create or replace function')).join('\n'):checkout;
const destination=readFileSync('supabase/migrations/20261021104459_finance_f4_beneficiary_destinations.sql','utf8');
const destinationCheck=spawnSync('docker',[...db,'-At','-c',"select to_regclass('private.finance_digital_destinations') is not null"],{encoding:'utf8'});assert.equal(destinationCheck.status,0,destinationCheck.stderr);
const destinationSetup=destinationCheck.stdout.trim()==='t'?destination.match(/create function[\s\S]*?\$\$;/g).map(x=>x.replace('create function','create or replace function')).join('\n'):destination;
const test=readFileSync('supabase/tests/finance_f4.sql','utf8').replace(/^begin;/,'').replace(/rollback;\s*$/,'');
const r=spawnSync('docker',db,{input:'begin;\n'+setup+'\n'+checkoutSetup+'\n'+destinationSetup+'\n'+test+'\nrollback;',encoding:'utf8',timeout:90000,maxBuffer:4*1024*1024});console.log(r.stdout);console.error(r.stderr);assert.equal(r.status,0);assert.doesNotMatch(r.stdout,/not ok \d/);console.log('F4 assertions passed; synthetic fixtures rolled back.');
