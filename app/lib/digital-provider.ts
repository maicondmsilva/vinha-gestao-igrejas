import {mercadoDigitalSnapshot,type DigitalSnapshot} from './finance-f4.ts';
import {openReceiver,receiverContext} from './receiver-vault.ts';
import type {OperationsClient} from './supabase/operations.ts';
export type DigitalConnection={org:string;unit:string;provider:string;environment:'sandbox'|'production';externalId:string;beneficiaries:string[];sealed:string;methods?:string[];paymentsEnabled?:boolean;webhookConfigured?:boolean};
export async function digitalConnection(client:OperationsClient,receiver:string){const r=await client.rpc('finance_digital_connection',{p_receiver:receiver});if(r.error||!r.data?.sealed)throw Error('Conexão indisponível.');return r.data as DigitalConnection}
/** Only a read-only lookup; the caller's payload is never a financial proof. */
export async function digitalProviderRead(c:DigitalConnection,id:string,transport:typeof fetch=fetch):Promise<DigitalSnapshot>{
 if(!/^[a-zA-Z0-9_-]{1,100}$/.test(id)||c.provider!=='mercado_pago')throw Error('Provedor não homologado para esta operação.');
 const secret=openReceiver<{access_token:string;user_id:string}>(c.sealed,receiverContext(c.org,c.unit,c.provider,c.environment));if(secret.user_id!==c.externalId||!secret.access_token)throw Error('Titular divergente.');
 const r=await transport('https://api.mercadopago.com/v1/payments/'+encodeURIComponent(id),{headers:{Authorization:'Bearer '+secret.access_token,accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Consulta não confirmada.');const raw=await r.text();if(raw.length>131072)throw Error('Resposta inválida.');
 const d=mercadoDigitalSnapshot(JSON.parse(raw),c.environment);if(d.externalId!==id||d.receiverExternalId!==c.externalId)throw Error('Titular ou transação divergente.');return d;
}
export async function digitalSync(client:OperationsClient,receiver:string,c:DigitalConnection,id:string,transport:typeof fetch=fetch){const snapshot=await digitalProviderRead(c,id,transport),r=await client.rpc('finance_digital_ingest',{p_receiver:receiver,p_snapshot:snapshot});if(r.error)throw Error('Pagamento não registrado. Confira o pedido, a classificação e a conexão antes de repetir.');return r.data}
