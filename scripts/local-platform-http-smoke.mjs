import {spawn,spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
if(process.argv[2]!=='--local-synthetic')throw Error('Local synthetic opt-in required.');
const cwd=fileURLToPath(new URL('../',import.meta.url));
// Never reuse or stop another process listening on the user's port.
await new Promise((resolve,reject)=>{const probe=createServer();probe.once('error',()=>reject(Error('Port 4100 is already occupied; existing server left untouched.')));probe.listen(4100,'127.0.0.1',()=>probe.close(resolve))});
const child=spawn(process.execPath,['scripts/local-ledger-dev.mjs'],{cwd,stdio:['ignore','pipe','pipe']});
let exited=false;child.once('exit',()=>{exited=true});child.stdout.on('data',()=>{});child.stderr.on('data',()=>{});
try{
 let ready=false;const deadline=Date.now()+45000;
 for(let attempt=0;attempt<100&&!exited&&Date.now()<deadline;attempt++){
  try{const response=await fetch('http://127.0.0.1:4100/api/platform/contracts',{redirect:'error',signal:AbortSignal.timeout(2000)});if(response.status===403){ready=true;break}}catch{}
  await delay(500);
 }
 if(!ready)throw Error('Owned local HTTP server did not become ready.');
 const result=spawnSync(process.execPath,['scripts/local-platform-mfa-smoke.mjs','--local-synthetic','--http'],{cwd,stdio:'inherit',timeout:60000});
 process.exitCode=result.status??1;
}finally{
 if(!exited){
  if(process.platform==='win32')spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{stdio:'ignore'});
  else child.kill('SIGTERM');
 }
 console.log('Owned local preview stopped; pre-existing servers were not reused.');
}
