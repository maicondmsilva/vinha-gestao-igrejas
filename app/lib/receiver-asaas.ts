import {createHash} from 'node:crypto';
import type {ReceiverEnvironment} from './finance-receivers.ts';
/** Read-only account verification. Never creates customers, subaccounts or charges. */
export async function asaasReceiverIdentity(credential:string,environment:ReceiverEnvironment,transport:typeof fetch=fetch){
 const base=environment==='sandbox'?'https://api-sandbox.asaas.com/v3':'https://api.asaas.com/v3';
 async function read(path:string){const r=await transport(base+path,{headers:{access_token:credential,'User-Agent':'Vinha/1.0',accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('O Asaas recusou a chave neste ambiente.');const raw=await r.text();if(raw.length>65536)throw Error('Resposta inválida do Asaas.');return JSON.parse(raw) as Record<string,unknown>}
 const info=await read('/myAccount/commercialInfo/'),account=await read('/myAccount/accountNumber');
 const holder=String(info.companyName||info.name||'').trim(),document=String(info.cpfCnpj||'').replace(/\D/g,''),agency=String(account.agency||''),number=String(account.account||''),digit=String(account.accountDigit??'');
 if(!holder||holder.length>160||!/^\d{11}(?:\d{3})?$/.test(document)||!/^\d+$/.test(agency)||!/^\d+$/.test(number)||!/^\d$/.test(digit))throw Error('O Asaas não retornou a identificação completa da conta. Confira o cadastro no ambiente oficial.');
 // Do not expose or persist raw personal document/bank numbers in the public configuration.
 return{externalId:'asaas:'+createHash('sha256').update([document,agency,number,digit].join(':')).digest('hex'),holder,expiresAt:new Date(Date.now()+86400000).toISOString()};
}
