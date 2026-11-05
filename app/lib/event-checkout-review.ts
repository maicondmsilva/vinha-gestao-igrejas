import {openReceiver,receiverContext} from './receiver-vault.ts';
import {mercadoCheckoutResult} from '../api/payments/mercado-pago-checkout.ts';
import type {DigitalConnection} from './digital-provider';
export type ReviewOrder={id:string;order:string;receiver:string;gross:string;state:string;active:boolean;expiresAt:string};
export async function inspectDigitalCheckout(c:DigitalConnection,r:ReviewOrder,transport:typeof fetch=fetch){
 let secret:{access_token:string;user_id:string};try{secret=openReceiver(c.sealed,receiverContext(c.org,c.unit,c.provider,c.environment))}catch{throw Error('Credencial protegida indisponível. Reconecte a conta recebedora com suas credenciais de produção. Não envie credenciais pelo chat.')}
 if(secret.user_id!==c.externalId||c.provider!=='mercado_pago'||!secret.access_token)throw Error('Conta recebedora não corresponde à credencial protegida.');
 async function get(path:string,stage:string){const res=await transport('https://api.mercadopago.com'+path,{method:'GET',headers:{Authorization:'Bearer '+secret.access_token,accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(12000)});if(!res.ok)throw Error(stage+' não autorizado pelo provedor (HTTP '+res.status+'). Revise a conexão da conta recebedora.');const text=await res.text();if(text.length>262144)throw Error('Resposta externa excede o limite.');return JSON.parse(text)}
 const user=await get('/users/me','Acesso à conta');if(String(user.id)!==c.externalId)throw Error('Titular externo divergente.');
 const methods=await get('/v1/payment_methods','Consulta de meios de pagamento');if(!Array.isArray(methods)||methods.length>500)throw Error('Métodos externos inválidos.');
 const available=[...new Set(methods.filter(m=>m.status==='active').map(m=>m.id==='pix'?'Pix':m.payment_type_id==='ticket'?'Boleto':['credit_card','debit_card'].includes(m.payment_type_id)?'Cartão':null).filter(Boolean))];
 const found=await get('/checkout/preferences/search?external_reference='+encodeURIComponent(r.order)+'&limit=10','Consulta de checkout');
 if(!Array.isArray(found.elements)||found.elements.length>10||!Number.isInteger(found.total)||found.total<0)throw Error('Pesquisa externa inválida.');
 if(found.total!==1||found.elements.length!==1)return{note:(found.total===0?'Nenhum checkout localizado.':'Mais de um checkout localizado.')+' O pedido permanece retido; não gere outra cobrança. Meios ativos no provedor: '+available.join(', ')+'.',ready:false as const};
 const id=found.elements[0]?.id;if(typeof id!=='string'||!/^[A-Za-z0-9_-]{1,200}$/.test(id))throw Error('Identificador externo inválido.');
 const d=await get('/checkout/preferences/'+encodeURIComponent(id),'Consulta do link');
 if(String(d.collector_id)!==c.externalId||d.external_reference!==r.order||!Array.isArray(d.items)||d.items.length!==1||d.items[0].id!==r.order||d.items[0].quantity!==1||d.items[0].currency_id!=='BRL'||String(d.items[0].unit_price)!==String(Number(r.gross)/100)||d.expires!==true||!Number.isFinite(Date.parse(d.expiration_date_to))||Date.parse(d.expiration_date_to)>Date.parse(r.expiresAt)+1000)throw Error('Checkout localizado diverge da conta, referência, valor ou prazo. Mantenha o pedido em conferência.');
 if(!r.active||Date.parse(d.expiration_date_to)<=Date.now())return{note:'Checkout localizado, mas o prazo do pedido já encerrou. Nenhuma nova cobrança foi criada.',ready:false as const};
 return{...mercadoCheckoutResult(d),ready:true as const,note:'Link existente recuperado e verificado. Nenhuma nova cobrança foi criada.'};
}
