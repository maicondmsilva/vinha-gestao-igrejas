import {spawnSync} from 'node:child_process';
import {readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
if(process.argv[2]!=='--local-synthetic')throw Error('Use --local-synthetic; no production target is accepted.');
const cwd=fileURLToPath(new URL('../',import.meta.url));
const suites=[
 ['application',['--test',...readdirSync(new URL('./',import.meta.url)).filter(name=>name.endsWith('.test.mjs')).map(name=>'scripts/'+name)]],
 ['types',['node_modules/typescript/bin/tsc','--noEmit','-p','tsconfig.ledger.json']],
 ['secrets',['scripts/check-secrets.mjs']],
 ['core SQL',['scripts/local-core-sql-tests.mjs','--local-synthetic']],
 ['proration SQL',['scripts/local-proration-test.mjs','--local-synthetic']],
 ['confirmation SQL',['scripts/local-proration-confirmation-test.mjs','--local-synthetic']],
 ['cancellation SQL',['scripts/local-proration-cancellation-test.mjs','--local-synthetic']],
 ['payer/catch-up SQL',['scripts/local-proration-payer-catchup-test.mjs','--local-synthetic']],
 ['concurrent sessions',['scripts/local-proration-concurrency.mjs','--local-synthetic']],
 ['ledger concurrency',['scripts/local-ledger-concurrency-test.mjs','--local-synthetic']],
 ['real MFA',['scripts/local-platform-mfa-smoke.mjs','--local-synthetic']],
 ['real HTTP/MFA',['scripts/local-platform-http-smoke.mjs','--local-synthetic']],
 ['build',['scripts/local-pilot-build.mjs']]
];
let failed=0;
for(const [name,args] of suites){
 console.log('START '+name);
 const result=spawnSync(process.execPath,args,{cwd,encoding:'utf8',maxBuffer:32*1024*1024,timeout:180000});
 if(result.status!==0){failed++;console.log('FAIL '+name+' (details suppressed; rerun its explicit local command).');}
 else console.log('PASS '+name);
}
console.log(`${suites.length-failed}/${suites.length} local suites passed. This does not certify external providers, browser QA or L4 completion.`);
process.exitCode=failed?1:0;
