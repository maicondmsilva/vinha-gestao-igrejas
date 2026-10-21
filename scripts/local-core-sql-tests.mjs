import {readdirSync,readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const directory=new URL('../supabase/tests/',import.meta.url),files=readdirSync(directory).filter(file=>file.endsWith('.sql')&&file!=='unit_contract_proration.sql');
let failed=0,assertions=0;
for(const file of files){
 const sql=readFileSync(new URL(file,directory),'utf8');
 if(!/^begin;\s*$/m.test(sql)||!/(?:^|;)\s*rollback;\s*$/.test(sql)||/\bcommit\s*;/i.test(sql))throw Error('Transactional rollback guard failed: '+file);
 const result=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',maxBuffer:16*1024*1024,timeout:60000});
 const count=(result.stdout?.match(/^\s*ok \d+\b/gm)||[]).length;assertions+=count;
 if(result.status!==0||/^\s*not ok/m.test(result.stdout||'')||/Looks like you failed/.test(result.stdout||'')){failed++;console.log('FAIL '+file);}
 else console.log('PASS '+file+' ('+count+' assertions, rollback)');
}
console.log(`${assertions} passed assertions across ${files.length} transactional core files; ${failed} failed files. No migrations or production access.`);
process.exitCode=failed?1:0;
