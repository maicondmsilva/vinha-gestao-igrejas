import type {ReceiverEnvironment} from './finance-receivers.ts';

/** Official read-only account lookup; never sends a payment, token in URL or follows redirects. */
export async function mercadoKeyIdentity(credential:string,environment:ReceiverEnvironment,transport:typeof fetch=fetch){
 if(!credential||credential.length>2000||/\s/.test(credential))throw Error('Chave inválida.');
 if(environment==='production'&&credential.startsWith('TEST-'))throw Error('Use a chave do ambiente selecionado.');
 const response=await transport('https://api.mercadopago.com/users/me',{method:'GET',headers:{Authorization:'Bearer '+credential,accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(15000)});
 if(response.status===401||response.status===403)throw Error('O Mercado Pago recusou a consulta da conta.');
 if(!response.ok)throw Error('Consulta temporariamente indisponível.');
 const raw=await response.text();if(raw.length>65536)throw Error('Resposta inválida.');const d=JSON.parse(raw);
 if(!d||!/^\d{1,30}$/.test(String(d.id))||d.site_id!=='MLB'||!Array.isArray(d.tags)||d.tags.some((x:unknown)=>typeof x!=='string')||d.tags.includes('test_user')!==(environment==='sandbox'))throw Error('Titular ou ambiente não confirmado.');
 if(d.status?.site_status&&d.status.site_status!=='active')throw Error('Conta indisponível no provedor.');
 const holder=[d.first_name,d.last_name].filter(x=>typeof x==='string').join(' ').trim()||(typeof d.nickname==='string'?d.nickname.trim():'');
 if(!holder||holder.length>160)throw Error('Titular não informado.');
 // Manual tokens do not provide an expiry claim here. This is our revalidation horizon, not a provider guarantee.
 return{externalId:String(d.id),holder,expiresAt:new Date(Date.now()+30*86400000).toISOString()};
}

export function mercadoKeyMaterial(credential:string,identity:{externalId:string},publicKey='',webhookSecret=''){
 return{credential,access_token:credential,user_id:identity.externalId,publicKey,webhookSecret};
}
