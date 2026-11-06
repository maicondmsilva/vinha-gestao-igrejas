import {mercadoPreferencePayload,mercadoCheckoutResult} from '../api/payments/mercado-pago-checkout.ts';
import {openReceiver,receiverContext} from './receiver-vault.ts';
import {receiverId} from './finance-receivers.ts';
import type {DigitalConnection} from './digital-provider.ts';
import type {OperationsClient} from './supabase/operations.ts';

export class CheckoutPreparationError extends Error{readonly notSent:boolean;readonly status:number;readonly stage:string;readonly reason:string;constructor(notSent:boolean,status:number,stage:string,reason=''){super('Checkout preparation '+stage+' HTTP '+status);this.notSent=notSent;this.status=status;this.stage=stage;this.reason=reason}}
export function checkoutPreparationIssue(e:unknown){return e instanceof CheckoutPreparationError?{retry:e.notSent,message:'Mercado Pago recusou a preparação do pagamento (HTTP '+e.status+(e.reason?' · '+e.reason:'')+'). '+(e.notSent?'Nenhuma cobrança foi criada nesta tentativa. Confira a conexão e a configuração da conta antes de preparar novamente.':'Mantenha o pedido em conferência; não crie outro pagamento.')}:null}
/** Bounded server diagnostics; never return this text to public checkout clients. */
export function checkoutProviderDiagnostic(body:unknown,secrets:string[]){
 if(!body||typeof body!=='object'||Array.isArray(body))return 'empty provider detail';
 const d=body as {error?:unknown;message?:unknown;cause?:unknown};
 let text=JSON.stringify({error:typeof d.error==='string'?d.error.slice(0,100):'',message:typeof d.message==='string'?d.message.slice(0,2000):'',cause:Array.isArray(d.cause)?d.cause.slice(0,5).map(x=>x&&typeof x==='object'?{code:String(x.code||'').slice(0,100),description:String(x.description||'').slice(0,500)}:{}):[]});
 for(const value of secrets.filter(x=>x.length>2).sort((a,b)=>b.length-a.length))text=text.split(value).join('[redacted]');
 return text.replace(/[^\s@"<>]+@[^\s@"<>]+/g,'[email]').replace(/Bearer\s+[^\s"]+/gi,'[credential]').replace(/[A-Za-z0-9_-]{24,}/g,'[identifier]').replace(/\d{6,}/g,'[number]').slice(0,1200);
}
export function checkoutErrorReason(body:unknown){
 if(!body||typeof body!=='object'||Array.isArray(body))return '';
 const d=body as {error?:unknown;message?:unknown;cause?:unknown};
 const values=[d.error,d.message,...(Array.isArray(d.cause)?d.cause.slice(0,10).flatMap(x=>x&&typeof x==='object'?[(x as {code?:unknown}).code,(x as {description?:unknown}).description]:[]):[])].filter((x):x is string=>typeof x==='string').map(x=>x.slice(0,4096).toLowerCase()).join(' ');
 const codes=['collector_does_not_comply_with_current_regulation','invalid_expiration_date_from','invalid_expiration_date_to','invalid_payment_methods','invalid_access_token','invalid_collector_id','invalid_collector_email','invalid_auto_return','auto_return_invalid','invalid_back_urls','invalid_payer_email','invalid_items','invalid_scope','invalid_client','invalid_token','invalid_date','invalid_request','forbidden'];
 for(const code of codes)if(values.includes(code))return code;
 for(const [pattern,code] of [[/collector.*(regulation|validation|comply)/,'collector_does_not_comply_with_current_regulation'],[/live credentials/,'live_credentials_rejected'],[/payer.*collector|collector.*payer/,'payer_collector_conflict'],[/expiration_date_from/,'invalid_expiration_date_from'],[/expiration_date_to/,'invalid_expiration_date_to'],[/expiration|invalid date/,'invalid_date'],[/excluded_payment|payment_methods|payment type/,'invalid_payment_methods'],[/back_urls|back_url|auto_return/,'invalid_back_urls'],[/notification_url/,'invalid_notification_url'],[/payer.*email|email.*payer/,'invalid_payer_email'],[/items|unit_price/,'invalid_items']] as const)if(pattern.test(values))return code;
 return values.includes('bad_request')?'bad_request':'';
}
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
 if(c.provider!=='mercado_pago'||(c.environment==='production'&&!(c.paymentsEnabled===true&&c.webhookConfigured===true&&Array.isArray(c.methods)&&c.methods.length>0&&c.methods.every(m=>['pix','boleto','card'].includes(m)))))throw Error('Checkout não habilitado para esta igreja e ambiente.');
}
/** Exactly one POST. The durable reservation must already be in dispatching state. */
export async function createDigitalPreference(c:DigitalConnection,r:CheckoutReservation,origin:string,transport:typeof fetch=fetch,returnPath?:string){
 enabled(c);origin=checkoutOrigin(origin);receiverId(r.id);receiverId(r.order);receiverId(r.receiver);
 if(r.state!=='dispatching'||!/^\d{1,9}$/.test(r.gross))throw Error('Tentativa não reservada.');
 const secret=openReceiver<{access_token:string;user_id:string}>(c.sealed,receiverContext(c.org,c.unit,c.provider,c.environment));
 if(secret.user_id!==c.externalId||!secret.access_token)throw Error('Titular divergente.');
 // Event checkouts return with the ticket order id, so the buyer lands back on their own order.
 const returns=origin+(returnPath&&/^\/pagamento\/retorno\?pedido=[0-9a-f-]{36}$/.test(returnPath)?returnPath:'/pagamento/retorno?pedido='+encodeURIComponent(r.order));
 const base=mercadoPreferencePayload({orderId:r.order,title:r.title,amountCents:Number(r.gross),name:r.name,email:r.email,callback:origin+'/api/finance-digital/webhook/'+r.receiver+'?environment='+c.environment,success:returns,pending:returns,failure:returns,expiresAt:Date.parse(r.expiresAt)});
 let restrictions:{excluded_payment_types:{id:string}[];excluded_payment_methods:{id:string}[]}|undefined;
 if(c.methods){
  const methodsResponse=await transport('https://api.mercadopago.com/v1/payment_methods',{method:'GET',headers:{Authorization:'Bearer '+secret.access_token,accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(15000)});
  if(!methodsResponse.ok)throw new CheckoutPreparationError(true,methodsResponse.status,'methods');
  const raw=await methodsResponse.text();if(raw.length>262144)throw Error('Métodos inválidos.');const methods=JSON.parse(raw);
  if(!Array.isArray(methods)||!methods.length||methods.length>500||methods.some(m=>!m||typeof m.id!=='string'||!/^[a-zA-Z0-9_-]{1,100}$/.test(m.id)||typeof m.payment_type_id!=='string'||typeof m.status!=='string'))throw Error('Métodos inválidos.');
  const allowed=(m:{id:string;payment_type_id:string;status:string})=>m.status==='active'&&((c.methods!.includes('card')&&['credit_card','debit_card'].includes(m.payment_type_id))||(c.methods!.includes('pix')&&m.id==='pix')||(c.methods!.includes('boleto')&&m.payment_type_id==='ticket'));
  if(!methods.some(allowed))throw Error('Nenhum método selecionado está disponível nesta conta.');
  // Mercado Pago never allows excluding its wallet balance; selected external methods stay restricted.
  const allowedType=(type:string)=>type==='account_money'||(c.methods!.includes('card')&&['credit_card','debit_card'].includes(type))||(c.methods!.includes('pix')&&type==='bank_transfer')||(c.methods!.includes('boleto')&&type==='ticket');
  restrictions={excluded_payment_types:[...new Set<string>(methods.map(m=>m.payment_type_id))].filter(type=>!allowedType(type)).map(id=>({id})),excluded_payment_methods:methods.filter(m=>m.payment_type_id!=='account_money'&&allowedType(m.payment_type_id)&&!allowed(m)).map(m=>({id:m.id}))};
 }
 const payload={...base,...(restrictions?{payment_methods:restrictions}:{})};
 const response=await transport('https://api.mercadopago.com/checkout/preferences',{method:'POST',headers:{Authorization:'Bearer '+secret.access_token,'Content-Type':'application/json',accept:'application/json'},body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(15000)});
 if(!response.ok){let reason='';try{const detail=await response.json();reason=checkoutErrorReason(detail);console.warn('vinha_checkout_provider_rejected',response.status,checkoutProviderDiagnostic(detail,[secret.access_token,r.email,r.name,...r.name.split(/\s+/),c.externalId]))}catch{}throw new CheckoutPreparationError([400,401,403,422].includes(response.status),response.status,'preference',reason)}
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
