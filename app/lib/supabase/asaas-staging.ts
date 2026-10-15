import {httpsUrl} from './financial-payloads.ts';
export type AsaasRecord={id?:string;link?:string;status?:string;externalReference?:string;pdfUrl?:string;xmlUrl?:string;value?:number;data?:AsaasRecord[]};
// Deliberately no production switch. Homologation cannot create real commitments.
export async function asaasStaging(path:string,credential:string,body?:unknown,method=body?'POST':'GET',transport:typeof fetch=fetch):Promise<AsaasRecord>{
 if(!/^\/(checkouts|invoices|subscriptions|payments)(\/|\?|$)/.test(path))throw new Error('Recurso de homologação inválido.');
 const response=await transport(`https://api-sandbox.asaas.com/v3${path}`,{method,headers:{access_token:credential,'content-type':'application/json','User-Agent':'Vinha/1.0'},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(15000)});
 if(!response.ok)throw new Error(`Asaas recusou a operação (HTTP ${response.status}). Consulte o painel de homologação.`);
 return response.json<AsaasRecord>();
}
export function sandboxCheckoutUrl(record:AsaasRecord){
 const provided=httpsUrl(record.link);if(provided&&new URL(provided).hostname==='sandbox.asaas.com')return provided;
 if(!record.id)throw new Error('Provedor não retornou identificador.');
 return `https://sandbox.asaas.com/checkoutSession/show/${encodeURIComponent(record.id)}`;
}
