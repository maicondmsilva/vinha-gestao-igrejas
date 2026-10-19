/** Server-side preparation only. This is not a payment confirmation or a subscription. */
export type MercadoPreferenceInput={orderId:string;title:string;amountCents:number;name:string;email:string;callback:string;success:string;pending:string;failure:string;expiresAt:number};
function publicHttps(value:string){
 const url=new URL(value);
 if(url.protocol!=='https:'||url.username||url.password||url.hash||!url.hostname.includes('.')||url.hostname==='localhost'||url.hostname.endsWith('.localhost')||url.hostname.endsWith('.local')||/^[\d.]+$/.test(url.hostname)||url.hostname.includes(':'))throw Error('Use um endereço público HTTPS válido.');
 return url.href;
}
export function mercadoPreferencePayload(input:MercadoPreferenceInput){
 if(!/^[a-zA-Z0-9_-]{1,100}$/.test(input.orderId)||!input.title.trim()||input.title.length>250||!input.name.trim()||input.name.length>200||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)||input.email.length>254)throw Error('Revise a referência e os dados do pagador.');
 if(!Number.isSafeInteger(input.amountCents)||input.amountCents<=0||input.amountCents>999999999)throw Error('Valor de cobrança inválido.');
 if(!Number.isSafeInteger(input.expiresAt)||input.expiresAt<=Date.now()||input.expiresAt>Date.now()+86400000)throw Error('Validade de checkout inválida.');
 const callback=publicHttps(input.callback),success=publicHttps(input.success),pending=publicHttps(input.pending),failure=publicHttps(input.failure);
 if([pending,failure,callback].some(url=>new URL(url).origin!==new URL(success).origin))throw Error('Os retornos devem pertencer ao mesmo domínio da operação.');
 return{items:[{id:input.orderId,title:input.title.trim(),quantity:1,currency_id:'BRL',unit_price:input.amountCents/100}],payer:{name:input.name.trim(),email:input.email},external_reference:input.orderId,notification_url:callback,back_urls:{success,pending,failure},auto_return:'approved',expires:true,expiration_date_to:new Date(input.expiresAt).toISOString()};
}
export function mercadoCheckoutResult(body:unknown){
 if(!body||typeof body!=='object'||Array.isArray(body))throw Error('Resposta de checkout inválida.');
 const data=body as Record<string,unknown>;
 if(typeof data.id!=='string'||!data.id.trim()||data.id.length>200||typeof data.init_point!=='string')throw Error('Mercado Pago não retornou identificador e link válidos.');
 const url=new URL(data.init_point);
 if(url.protocol!=='https:'||url.username||url.password||!['www.mercadopago.com.br','mercadopago.com.br'].includes(url.hostname)||url.port||url.hash||url.pathname!=='/checkout/v1/redirect')throw Error('Link de checkout Mercado Pago inválido.');
 // Never invent a link or fall back to sandbox_init_point from a legacy flow.
 if(url.searchParams.get('pref_id')!==data.id)throw Error('Link de checkout não corresponde à referência recebida.');
 return{providerPaymentId:data.id,checkoutUrl:url.href};
}
