// Isolated rehearsal only: no default network transport or persisted credentials.
import {mercadoCredentialSummary,mercadoDiagnosticToken,mercadoTestSubscriptionDraft,validateMercadoSubscriptionSnapshot,type TestSubscriptionDraft} from './mercado-pago-subscription.ts';

export async function rehearseMercadoSubscription(input:TestSubscriptionDraft,credential:string,transport:typeof fetch,now=Date.now()){
 const payload=mercadoTestSubscriptionDraft(input,now);
 let token=mercadoDiagnosticToken(credential);
 const request=async(url:string,method:string,body?:unknown)=>{
  const response=await transport(url,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
  if(!response.ok)throw Error('Ensaio interrompido pelo provedor; não repetir automaticamente.');
  return response.json();
 };
 try{
  const identity=mercadoCredentialSummary(await request('https://api.mercadopago.com/users/me','GET'));
  if(!identity.testIdentityConfirmed)throw Error('Conta de teste não comprovada.');
  // Never retry this POST: a timeout may mean an unknown remote outcome.
  return validateMercadoSubscriptionSnapshot(await request('https://api.mercadopago.com/preapproval','POST',payload),input);
 }finally{token=''}
}
