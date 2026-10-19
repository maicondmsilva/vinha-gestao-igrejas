import {execFileSync} from 'node:child_process';
import {readFileSync,statSync} from 'node:fs';
const paths=execFileSync('git',['ls-files','--cached','--others','--exclude-standard','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const signatures=[/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----(?:\r?\n|\\n)[A-Za-z0-9+/=\\\r\n]{64,}/,/\bgh[pousr]_[A-Za-z0-9]{30,}\b/,/\bsb_secret_[A-Za-z0-9_-]{20,}\b/,/\bAKIA[0-9A-Z]{16}\b/];
let failures=0;
for(const path of paths){
 if(/(^|\/)(node_modules|dist|\.next|\.vercel|docs\/evidencias)\//.test(path)||/\.(png|jpg|jpeg|pdf|woff2?|lock)$/.test(path))continue;
 if(/(^|\/)\.env(?:\.|$)/.test(path)&&!path.endsWith('.example')){console.error('Arquivo de ambiente não permitido no código: '+path);failures++;continue}
 try{if(statSync(path).size>2000000)continue;const text=readFileSync(path,'utf8');if(signatures.some(pattern=>pattern.test(text))){console.error('Possível segredo no arquivo '+path+'; conteúdo não exibido.');failures++}}catch{/* Deleted paths have no content to scan. */}
}
if(failures)process.exit(1);console.log('Verificação estática de segredos aprovada; não substitui rotação ou varredura do histórico.');
