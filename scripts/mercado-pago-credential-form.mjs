import {createServer} from 'node:http';
import {randomBytes} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {mercadoDiagnosticToken,mercadoCredentialSummary} from '../app/api/payments/mercado-pago-subscription.ts';

async function readOnlyAccount(token){
 const response=await fetch('https://api.mercadopago.com/users/me',{method:'GET',redirect:'error',signal:AbortSignal.timeout(15000),headers:{Authorization:'Bearer '+token}});
 if(!response.ok)throw Error('Consulta recusada.');
 return mercadoCredentialSummary(await response.json());
}
const page=content=>`<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Vinha · diagnóstico local</title><style>body{font:17px Arial;background:#f2f5f1;color:#193f30;margin:0;padding:30px}main{max-width:560px;margin:40px auto;background:white;padding:32px;border-radius:16px}input,button{box-sizing:border-box;width:100%;padding:14px;margin:12px 0}button{background:#285c45;color:white;border:0;border-radius:8px}p{line-height:1.6}</style><main><h1>Vinha</h1>${content}</main></html>`;
export async function startCredentialDiagnostic({verify=readOnlyAccount}={}){
 const nonce=randomBytes(32).toString('hex');let origin='',used=false;
 const server=createServer(async(req,res)=>{
  // Preserve the same-origin POST Origin header; no-referrer can turn it into null.
  // Cross-origin destinations still receive no referrer, including this session URL.
  const send=(status,content)=>{res.writeHead(status,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'same-origin','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"});res.end(page(content))};
  if(req.headers.host!==new URL(origin).host||req.url!==`/${nonce}`){send(404,'<p>Página indisponível.</p>');return}
  if(req.method==='GET'){
   if(used){send(409,'<p>Esta sessão já foi utilizada. Nenhuma nova consulta será feita.</p>');return}
   send(200,`<h2>Consulta local de credencial</h2><p>Use somente o Access Token da conta de teste. A chave fica temporariamente na memória e será enviada apenas à API oficial do Mercado Pago para consultar a conta. Não será salva em arquivo. Nenhum pagamento ou assinatura será criado.</p><p>Não use a chave anteriormente compartilhada: substitua-a primeiro. Não permita que o navegador salve este campo.</p><form method="post" action="/${nonce}" autocomplete="off"><input type="hidden" name="csrf" value="${nonce}"><label for="credential">Access Token — não é a Public Key</label><input id="credential" name="credential" type="password" autocomplete="off" required maxlength="4096"><button type="submit">Consultar conta · somente leitura</button></form>`);return;
  }
  if(req.method!=='POST'||req.headers.origin!==origin||req.headers['content-type']!=='application/x-www-form-urlencoded'||Number(req.headers['content-length']||0)>8192){send(403,'<p>Solicitação recusada.</p>');return}
  if(used){send(409,'<p>Consulta já iniciada. Não reenvie a chave.</p>');return}
  try{
   let raw='',size=0;for await(const chunk of req){size+=chunk.length;if(size>8192)throw Error('Limite excedido.');raw+=chunk.toString('utf8')}
   const form=new URLSearchParams(raw);raw='';
   if(form.getAll('csrf').length!==1||form.get('csrf')!==nonce||form.getAll('credential').length!==1||[...form.keys()].some(k=>!['csrf','credential'].includes(k))){send(403,'<p>Solicitação recusada.</p>');return}
   let token;try{token=mercadoDiagnosticToken(form.get('credential')||'')}catch{send(400,'<p>Formato inválido. Use Access Token, não Public Key. Nenhum pedido externo foi feito.</p>');return}finally{form.delete('credential')}
   if(used){token='';send(409,'<p>Consulta já iniciada. Não reenvie a chave.</p>');return}
   used=true;let summary;try{summary=await verify(token)}finally{token=''}
   if(summary?.credentialAccepted!==true||typeof summary.testIdentityConfirmed!=='boolean')throw Error('Resposta inválida.');
   send(200,`<h2>Consulta concluída</h2><p>Credencial aceita pela API. Conta brasileira confirmada.</p><p>${summary.testIdentityConfirmed?'A API identificou esta conta como conta de teste.':'A identidade de teste NÃO foi comprovada; a criação de assinaturas continua bloqueada.'}</p><p>Nenhum pagamento, assinatura ou arquivo de credencial foi criado. Pode fechar esta aba.</p>`);
  }catch{send(502,'<h2>Consulta não concluída</h2><p>Confira o Access Token e a conexão. Nenhum pagamento foi criado. Não compartilhe a chave nem reenvie nesta sessão.</p>')}
 });
 server.requestTimeout=20000;server.headersTimeout=10000;
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
 origin=`http://127.0.0.1:${server.address().port}`;
 const timer=setTimeout(()=>{server.close();server.closeAllConnections()},10*60*1000);timer.unref();server.once('close',()=>clearTimeout(timer));
 return{server,url:`${origin}/${nonce}`};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(process.argv.length!==3||process.argv[2]!=='--test-form')throw Error('Use --test-form, sem chave nos argumentos.');
 const {url}=await startCredentialDiagnostic();console.log('Abra no navegador deste computador: '+url);console.log('Formulário local válido por 10 minutos. Não compartilhe a URL. Ctrl+C encerra.');
}
