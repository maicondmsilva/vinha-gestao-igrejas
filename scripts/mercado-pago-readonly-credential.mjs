// Human-run, read-only credential check. Never pass a token in command arguments.
import {mercadoCredentialSummary,mercadoDiagnosticToken} from '../app/api/payments/mercado-pago-subscription.ts';
if(process.argv.length!==3||process.argv[2]!=='--test-readonly')throw Error('Use somente --test-readonly; nenhum token deve ser passado como argumento.');
if(!process.stdin.isTTY||!process.stdout.isTTY)throw Error('Abra um terminal interativo; entrada por arquivo/pipe recusada.');
async function hiddenCredential(){
 process.stdout.write('Cole o Access Token DE TESTE (oculto); Enter confirma, Ctrl+C cancela: ');
 return new Promise((resolve,reject)=>{
  let value='';process.stdin.setRawMode(true);process.stdin.setEncoding('utf8');process.stdin.resume();
  const finish=(error)=>{process.stdin.off('data',onData);process.stdin.setRawMode(false);process.stdin.pause();process.stdout.write('\n');const result=value;value='';error?reject(error):resolve(result)};
  const onData=chunk=>{for(const char of chunk){if(char==='\u0003'){finish(Error('Cancelado.'));return}if(char==='\r'||char==='\n'){finish();return}if(char==='\u007f'||char==='\b'){value=value.slice(0,-1);continue}if(char.charCodeAt(0)<32)continue;value+=char;if(value.length>4096){finish(Error('Entrada inválida.'));return}}};
  process.stdin.on('data',onData);
 });
}
let token='';
try{
 token=String(await hiddenCredential()).trim();
 token=mercadoDiagnosticToken(token); // Read-only: accepting a format cannot enable charges.
 const response=await fetch('https://api.mercadopago.com/users/me',{method:'GET',redirect:'error',signal:AbortSignal.timeout(15000),headers:{Authorization:'Bearer '+token}});
 token='';
 if(!response.ok)throw Error('Credencial não validada; HTTP '+response.status+'. Nenhum detalhe sensível será exibido.');
 const summary=mercadoCredentialSummary(await response.json());
 console.log('Credencial aceita pela API. Conta brasileira confirmada.');
 console.log(summary.testIdentityConfirmed?'Identidade marcada como teste pelo provedor.':'Identidade de teste NÃO comprovada; criação de assinaturas permanece bloqueada.');
 console.log('Somente consulta GET. Não criou pagamento, assinatura ou arquivo de credencial.');
}catch(error){console.error(error instanceof Error?error.message:'Consulta não concluída.');process.exitCode=1}finally{token=''}
