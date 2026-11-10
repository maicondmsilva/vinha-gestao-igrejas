// Fixed local Docker only. Copies schema (never rows), adds synthetic fixtures,
// and removes only the uniquely named database created by this process.
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
if(process.argv[2]!=='--local-synthetic')throw Error('Use --local-synthetic.');
const container='supabase_db_vinha',database='proration_qa_20261018_'+randomBytes(6).toString('hex');
if(!/^proration_qa_20261018_[a-f0-9]{12}$/.test(database))throw Error('Invalid temporary database name.');
const docker=(args,input)=>spawnSync('docker',['exec','-i',container,...args],{input,encoding:'utf8',maxBuffer:32*1024*1024,timeout:60000});
function execute(sql){const r=docker(['psql','-X','-A','-t','-q','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],sql);if(r.status!==0)throw Error('Local SQL failed: '+r.stderr.slice(-1800));return r.stdout.trim()}
function connection(sql,onData=()=>{}){return new Promise((resolve,reject)=>{const child=spawn('docker',['exec','-i',container,'psql','-X','-A','-t','-q','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let out='',err='';const timer=setTimeout(()=>{child.kill();reject(Error('Local concurrent test timeout'))},20000);child.stdout.on('data',chunk=>{out+=chunk;onData(out)});child.stderr.on('data',chunk=>err+=chunk);child.on('error',reject);child.on('close',code=>{clearTimeout(timer);resolve({code,out,err})});child.stdin.end("set statement_timeout='12s';set lock_timeout='8s';\n"+sql)})}
const identity=`set local role authenticated;select set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',true);`;
const contract='dd000000-0000-4000-8000-000000000001',baseInvoice='ed000000-0000-4000-8000-000000000001';
const quote=value=>"'"+JSON.stringify(value).replaceAll("'","''")+"'::jsonb";
const call=(name,input)=>`select public.${name}(${quote(input)});`;
async function race(firstSql,secondSql){let unlock,finished=false,overlap=false;const barrier=new Promise(resolve=>unlock=resolve);
 const first=connection(`begin;${identity}${firstSql}select 'PRORATION_LOCK_HELD';select pg_sleep(1.5);commit;`,out=>{if(out.includes('PRORATION_LOCK_HELD'))unlock()}).then(r=>{finished=true;return r});
 await Promise.race([barrier,first.then(r=>{throw Error('Barrier not reached: '+r.err)})]);
 const second=await connection(`begin;select 'PRORATION_SECOND_STARTED';${identity}${secondSql}commit;`,out=>{if(out.includes('PRORATION_SECOND_STARTED')&&!finished)overlap=true});
 const initial=await first;assert.equal(initial.code,0,initial.err);assert.equal(overlap,true,'two independent sessions must overlap');return second;
}
let created=false;
try{
 const create=docker(['createdb','-U','postgres','-T','template0',database]);assert.equal(create.status,0,create.stderr);created=true;
 const schema=docker(['pg_dump','-U','postgres','-d','postgres','--schema-only','--no-owner','--schema=public','--schema=private','--schema=auth','--schema=extensions']);assert.equal(schema.status,0,'schema-only dump failed');
 execute('create schema extensions;create extension pgcrypto with schema extensions;create extension "uuid-ossp" with schema extensions;create extension pg_stat_statements with schema extensions;');
 // Hosted service-role default grants are not portable to a postgres-owned QA
 // database. Keep existing object grants, omit only future-object defaults.
 // This harness therefore does not certify default-privilege restoration.
 const portableSchema=schema.stdout.split('\n').filter(line=>!line.startsWith('ALTER DEFAULT PRIVILEGES ')).join('\n');
 execute(portableSchema.replace(/CREATE SCHEMA (public|extensions);/g,'CREATE SCHEMA IF NOT EXISTS $1;'));
 for(const file of ['20261018151747_unit_contract_proration_pilot.sql','20261018152708_proration_documents_credit_application_pilot.sql','20261018161147_proration_cycle_rollover_pilot.sql'])execute(readFileSync(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
 let fixtures=readFileSync(new URL('../supabase/tests/unit_contract_proration.sql',import.meta.url),'utf8').split("select set_config('qa.proration.input'")[0].replace(/^begin;$/m,'').replace(/^select no_plan\(\);$/m,'');execute(fixtures);
 const now=Date.now(),input={requestId:'fd000000-0000-4000-8000-000000000011',contractId:contract,nextPlanId:'qa-proration-b',baseInvoiceId:baseInvoice,expectedUpdatedAt:execute(`select updated_at from public.saas_unit_contracts where id='${contract}';`),cycleStart:now-1296000000,cycleEnd:now+1296000000};
 let second=await race(call('change_unit_contract_plan_pilot',input),call('change_unit_contract_plan_pilot',input));assert.equal(second.code,0,second.err);assert.equal(execute('select count(*) from public.saas_plan_adjustments;'),'1');console.log('PASS concurrent same plan-change UUID: one adjustment');
 const down={...input,requestId:'fd000000-0000-4000-8000-000000000012',nextPlanId:'qa-proration-a',expectedUpdatedAt:execute(`select updated_at from public.saas_unit_contracts where id='${contract}';`)};
 second=await race(call('change_unit_contract_plan_pilot',down),call('change_unit_contract_plan_pilot',{...down,requestId:'fd000000-0000-4000-8000-000000000013'}));assert.notEqual(second.code,0);assert.match(second.err,/40001/);assert.equal(execute('select count(*) from public.saas_plan_adjustments;'),'2');console.log('PASS concurrent different changes: stale version refused');
 const issue={requestId:'fd000000-0000-4000-8000-000000000014',contractId:contract,referenceMonth:execute(`select to_char(to_timestamp(cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM') from public.saas_proration_cycles where contract_id='${contract}';`)};
 second=await race(call('issue_proration_cycle_invoice_pilot',issue),call('issue_proration_cycle_invoice_pilot',issue));assert.equal(second.code,0,second.err);assert.equal(execute('select count(*) from public.saas_proration_invoice_runs;'),'1');assert.equal(execute('select count(*) from public.saas_proration_credit_uses;'),'1');assert.equal(execute("select snapshot->>'amountCents' from public.saas_proration_invoice_runs;"),'7000');console.log('PASS concurrent invoice replay: one invoice, one credit use, 7000 cents net');
 const testSource=readFileSync(new URL('../supabase/tests/unit_contract_proration.sql',import.meta.url),'utf8');execute(testSource.split('-- BEGIN ROLLOVER FIXTURE')[1].split('-- END ROLLOVER FIXTURE')[0]);
 const rolloverContract='dd000000-0000-4000-8000-000000000002',roll={requestId:'fd000000-0000-4000-8000-000000000031',contractId:rolloverContract,invoiceId:'ed000000-0000-4000-8000-000000000003',expectedUpdatedAt:execute(`select updated_at from public.saas_unit_contracts where id='${rolloverContract}';`)};
 second=await race(call('rollover_proration_cycle_pilot',roll),call('rollover_proration_cycle_pilot',roll));assert.equal(second.code,0,second.err);assert.equal(execute('select count(*) from public.saas_proration_rollovers;'),'1');assert.equal(execute(`select count(*) from public.saas_proration_credit_uses u join public.saas_proration_documents d on d.id=u.document_id where d.contract_id='${rolloverContract}';`),'0');console.log('PASS concurrent cycle rollover: one transition and credit preserved');
 execute(readFileSync(new URL('../supabase/migrations/20261018181106_proration_confirmation_catalog_guard.sql',import.meta.url),'utf8'));
 const confirmation={...input,requestId:'fd000000-0000-4000-8000-000000000041',nextPlanId:'qa-proration-a',expectedUpdatedAt:execute(`select updated_at from public.saas_unit_contracts where id='${contract}';`),expectedCatalog:JSON.parse(execute("select private.proration_catalog_snapshot('qa-proration-a');"))};
 const before=execute('select count(*) from public.saas_plan_adjustments;');
 second=await race("reset role;update public.saas_plans set base_price_cents=11000 where id='qa-proration-a';",call('confirm_unit_contract_plan_pilot',confirmation));
 assert.notEqual(second.code,0);assert.match(second.err,/40001/);assert.equal(execute('select count(*) from public.saas_plan_adjustments;'),before);
 console.log('PASS concurrent catalog edit first: stale preview refused without adjustment');
 execute("update public.saas_plans set base_price_cents=10000 where id='qa-proration-a';");
 const fresh={...confirmation,requestId:'fd000000-0000-4000-8000-000000000042',expectedCatalog:JSON.parse(execute("select private.proration_catalog_snapshot('qa-proration-a');"))};
 second=await race(call('confirm_unit_contract_plan_pilot',fresh),"reset role;set local lock_timeout='250ms';update public.saas_plans set base_price_cents=12000 where id='qa-proration-a';");
 assert.notEqual(second.code,0);assert.match(second.err,/55P03/);assert.equal(execute("select base_price_cents from public.saas_plans where id='qa-proration-a';"),'10000');
 assert.equal(execute(`select count(*) from public.saas_plan_adjustments where request_id='${fresh.requestId}';`),'1');
 execute("update public.saas_plans set base_price_cents=12000 where id='qa-proration-a';");
 assert.equal(execute("select base_price_cents from public.saas_plans where id='qa-proration-a';"),'12000');
 console.log('PASS confirmation first: catalog editor blocked until transaction ends, succeeds afterward');
 execute(`insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values('ad000000-0000-4000-8000-000000000098','00000000-0000-0000-0000-000000000000','authenticated','authenticated','backup-owner@example.invalid',now(),now(),now());insert into public.platform_operators(user_id,role,full_name,email) values('ad000000-0000-4000-8000-000000000098','owner','Backup synthetic','backup-owner@example.invalid');`);
 const revoke=`reset role;select set_config('request.jwt.claims','{}',true);update public.platform_operators set active=false where user_id='ad000000-0000-4000-8000-000000000001';`;
 const priorCount=execute('select count(*) from public.saas_plan_adjustments;');
 second=await race(`reset role;select set_config('request.jwt.claims','{}',true);lock table public.saas_plans in row exclusive mode;update public.platform_operators set active=false where user_id='ad000000-0000-4000-8000-000000000001';`,call('confirm_unit_contract_plan_pilot',fresh));
 assert.notEqual(second.code,0);assert.match(second.err,/42501/);assert.equal(execute('select count(*) from public.saas_plan_adjustments;'),priorCount);
 console.log('PASS suspension during catalog wait: prior successful result cannot be replayed');
 execute("update public.platform_operators set active=true where user_id='ad000000-0000-4000-8000-000000000001';");
 second=await race(call('confirm_unit_contract_plan_pilot',fresh),"set local lock_timeout='250ms';"+revoke);
 assert.notEqual(second.code,0);assert.match(second.err,/55P03/);assert.equal(execute("select active::text from public.platform_operators where user_id='ad000000-0000-4000-8000-000000000001';"),'true');
 execute("update public.platform_operators set active=false where user_id='ad000000-0000-4000-8000-000000000001';");
 assert.equal(execute("select active::text from public.platform_operators where user_id='ad000000-0000-4000-8000-000000000001';"),'false');
 console.log('PASS confirmation first: suspension waits for permission lock and succeeds after commit');
 execute("update public.platform_operators set active=true where user_id='ad000000-0000-4000-8000-000000000001';");
 execute(readFileSync(new URL('../supabase/migrations/20261018203432_proration_monthly_generator_isolation.sql',import.meta.url),'utf8'));
 const nextIssue={requestId:'fd000000-0000-4000-8000-000000000051',contractId:rolloverContract,referenceMonth:execute(`select to_char(to_timestamp(cycle_end/1000.0) at time zone 'America/Sao_Paulo','YYYY-MM') from public.saas_proration_cycles where contract_id='${rolloverContract}';`)};
 const legacy=`select public.generate_platform_invoices('${nextIssue.referenceMonth}',null,'bd000000-0000-4000-8000-000000000001');`;
 second=await race(legacy,call('issue_proration_cycle_invoice_pilot',nextIssue));assert.notEqual(second.code,0);assert.match(second.err,/22023/);
 assert.equal(execute(`select count(*) from public.saas_invoices where unit_contract_id='${rolloverContract}' and reference_month='${nextIssue.referenceMonth}';`),'1');
 nextIssue.requestId=execute(`select request_id from public.saas_proration_invoice_runs where contract_id='${rolloverContract}' and reference_month='${nextIssue.referenceMonth}';`);
 assert.equal(execute(`select snapshot->>'creditAppliedCents' from public.saas_proration_invoice_runs where request_id='${nextIssue.requestId}';`),'1000');
 console.log('PASS monthly generator first: dispatches proportional issuer, credit applied once, competing new request refused');
 second=await race(call('issue_proration_cycle_invoice_pilot',nextIssue),legacy);assert.equal(second.code,0,second.err);
 assert.equal(execute(`select count(*) from public.saas_invoices where unit_contract_id='${rolloverContract}' and reference_month='${nextIssue.referenceMonth}';`),'1');
 console.log('PASS proportional issuer first: monthly legacy generator never duplicates pilot invoice');
 execute("insert into public.organization_units(id,organization_id,name,slug,unit_type) values('cd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000001','Non-pilot synthetic','nonpilot','congregation');insert into public.saas_unit_contracts(id,organization_id,unit_id,payer_unit_id,plan_id,status) values('dd000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000001','cd000000-0000-4000-8000-000000000003','cd000000-0000-4000-8000-000000000003','qa-proration-a','active');");
 execute(`begin;${identity}${legacy}${legacy}commit;`);
 assert.equal(execute("select count(*) from public.saas_invoices where unit_contract_id='dd000000-0000-4000-8000-000000000003';"),'1');
 assert.equal(execute("select amount_cents from public.saas_invoices where unit_contract_id='dd000000-0000-4000-8000-000000000003';"),'12000');
 console.log('PASS non-pilot monthly regression: legacy generator still issues once at correct price');
 execute(readFileSync(new URL('../supabase/migrations/20261018203612_proration_invoice_cancellation_credit_return.sql',import.meta.url),'utf8'));
 const cancel={requestId:'fd000000-0000-4000-8000-000000000061',contractId:contract,invoiceId:execute(`select invoice_id from public.saas_proration_invoice_runs where request_id='${issue.requestId}';`),reason:'Cancelamento concorrente sintético'};
 second=await race(call('cancel_proration_invoice_pilot',cancel),call('cancel_proration_invoice_pilot',cancel));assert.equal(second.code,0,second.err);
 assert.equal(execute(`select count(*) from public.saas_proration_cancellations where invoice_id='${cancel.invoiceId}';`),'1');
 assert.equal(execute(`select sum(amount_cents) from public.saas_proration_credit_returns where invoice_id='${cancel.invoiceId}';`),'3000');
 assert.equal(execute(`select status from public.saas_invoices where id='${cancel.invoiceId}';`),'cancelled');
 console.log('PASS concurrent cancellation replay: one cancellation, exact 3000-cent return, consumption history preserved');
 console.log('PASS 11 real overlapping READ COMMITTED scenarios; no production or provider access.');
}finally{
 if(created){const cleanup=docker(['psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',`DROP DATABASE "${database}" WITH (FORCE);`]);if(cleanup.status!==0)throw Error('Temporary database cleanup failed: '+database);console.log('Temporary synthetic database removed. Existing local data preserved.');}
}
