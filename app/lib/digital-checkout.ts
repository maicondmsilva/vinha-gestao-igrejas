import {mercadoPreferencePayload,mercadoCheckoutResult} from '../api/payments/mercado-pago-checkout.ts';
import {openReceiver,receiverContext} from './receiver-vault.ts';
import {receiverId} from './finance-receivers.ts';
import type {DigitalConnection} from './digital-provider.ts';
import type {OperationsClient} from './supabase/operations.ts';

export type CheckoutReservation={id:string;order:string;receiver:string;gross:string;title:string;name:string;email:string;expiresAt:string;state:string;checkoutUrl?:string};
/** A configured origin, never Host/Forwarded headers or a URL supplied by the payer. */
export function checkoutOrigin(value:string){
 const u=new URL(value);
 if(u.protocol!=='https:'||u.username||u.password||u.port||u.pathname!=='/'||u.search||u.hash||!['app.vinhaigrejas.com.br','teste.vinhaigrejas.com.br'].includes(u.hostname))throw Error('Domínio de checkout não configurado.');
 return u.origin;
}
export function checkoutCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Pedido inválido.');const d=value as Record<string,unknown>;
 if(Object.keys(d).some(k=>!['unit','order','name'].includes(k))||typeof d.name!=='string'||d.name.trim().length<2||d.name.length>160)throw Error('Revise os dados do pagador.');
 return{unit:receiverId(d.unit),order:receiverId(d.order),name:d.name.trim()};
}
function enabled(c:DigitalConnection){
 if(c.provider!=='mercado_pago'||(c.environment==='production'&&process.env.FINANCE_MP_LIVE_CHECKOUT_ENABLED!=='true'))throw Error('Checkout não homologado para este ambiente.');
}
/** Exactly one POST. The durable reservation must already be in dispatching state. */
export async function createDigitalPreference(c:DigitalConnection,r:CheckoutReservation,origin:string,transport:typeof fetch=fetch){
 enabled(c);origin=checkoutOrigin(origin);receiverId(r.id);receiverId(r.order);receiverId(r.receiver);
 if(r.state!=='dispatching'||!/^\d{1,9}$/.test(r.gross))throw Error('Tentativa não reservada.');
 const secret=openReceiver<{access_token:string;user_id:string}>(c.sealed,receiverContext(c.org,c.unit,c.provider,c.environment));
 if(secret.user_id!==c.externalId||!secret.access_token)throw Error('Titular divergente.');
 const returns=origin+'/pagamento/retorno?pedido='+encodeURIComponent(r.order);
 const payload=mercadoPreferencePayload({orderId:r.order,title:r.title,amountCents:Number(r.gross),name:r.name,email:r.email,callback:origin+'/api/finance-digital/webhook/'+r.receiver+'?environment='+c.environment,success:returns,pending:returns,failure:returns,expiresAt:Date.parse(r.expiresAt)});
 const response=await transport('https://api.mercadopago.com/checkout/preferences',{method:'POST',headers:{Authorization:'Bearer '+secret.access_token,'Content-Type':'application/json',accept:'application/json'},body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(15000)});
 if(!response.ok)throw Error('Resultado externo não confirmado.');
 const raw=await response.text();if(raw.length>131072)throw Error('Resposta inválida.');const d=JSON.parse(raw);
 if(String(d.collector_id)!==c.externalId||d.external_reference!==r.order||!Array.isArray(d.items)||d.items.length!==1||d.items[0].id!==r.order||d.items[0].quantity!==1||d.items[0].currency_id!=='BRL'||String(d.items[0].unit_price)!==String(Number(r.gross)/100))throw Error('Preferência divergente.');
 return mercadoCheckoutResult(d);
}
/** An ambiguous network/DB result is never retried by creating a second preference. */
export async function dispatchDigitalCheckout(server:OperationsClient,scope:{org:string;unit:string;attempt:string;receiver:string},c:DigitalConnection,origin:string,transport:typeof fetch=fetch){
 enabled(c);origin=checkoutOrigin(origin);
 if(c.org!==scope.org||!c.beneficiaries.includes(scope.unit))throw Error('Conexão fora do escopo.');
 const claim=await server.rpc('finance_checkout_delivery',{p_org:scope.org,p_unit:scope.unit,p_id:scope.attempt,p_action:'claim',p_data:{}});
 if(claim.error||!claim.data)throw Error('Tentativa indisponível.');const r=claim.data as CheckoutReservation;
 if(r.id!==scope.attempt||r.receiver!==scope.receiver)throw Error('Tentativa divergente.');
 if(r.state==='ready')return{state:'ready',checkoutUrl:r.checkoutUrl};
 if(r.state!=='dispatching')throw Error('Resultado pendente de conferência.');
 try{
  const result=await createDigitalPreference(c,r,origin,transport);
  const saved=await server.rpc('finance_checkout_delivery',{p_org:scope.org,p_unit:scope.unit,p_id:scope.attempt,p_action:'complete',p_data:{preference:result.providerPaymentId,url:result.checkoutUrl}});
  if(saved.error)throw Error('Resultado não persistido.');return{state:'ready',checkoutUrl:result.checkoutUrl};
 }catch{
  try{await server.rpc('finance_checkout_delivery',{p_org:scope.org,p_unit:scope.unit,p_id:scope.attempt,p_action:'uncertain',p_data:{}})}catch{/* Preserve the durable dispatching state if the database itself is unavailable. */}
  throw Error('Não foi possível confirmar o checkout. A tentativa foi retida para conferência; não gere outra cobrança.');
 }
}
