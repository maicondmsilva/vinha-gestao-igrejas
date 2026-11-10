// Preparation/validation only. No transport, credentials, database writes or card data.
export type TestSubscriptionDraft={requestId:string;amountCents:number;payerEmail:string;firstChargeAt:string;returnUrl:string};
export function mercadoTestSubscriptionDraft(input:TestSubscriptionDraft,now=Date.now()){
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.requestId))throw Error('Referência inválida.');
 if(!Number.isSafeInteger(input.amountCents)||input.amountCents<1||input.amountCents>999999999)throw Error('Valor inválido.');
 if(!/^[a-zA-Z0-9._+-]+@testuser\.com$/.test(input.payerEmail)||input.payerEmail.length>254)throw Error('Use somente o e-mail do comprador fictício do Mercado Pago.');
 const first=new Date(input.firstChargeAt);
 if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(input.firstChargeAt)||!Number.isFinite(first.getTime())||first.toISOString()!==input.firstChargeAt||first.getTime()<=now+3600000)throw Error('Informe uma primeira cobrança futura, com margem superior a uma hora.');
 const back=new URL(input.returnUrl);
 // No production destination is permitted in this test draft. An isolated callback
 // deployment is still a prerequisite; this does not enable external submission.
 if(back.origin!=='https://teste.vinhaigrejas.com.br'||back.pathname!=='/pagamentos/assinatura/retorno'||back.search||back.hash||back.username||back.password)throw Error('Retorno exclusivo da homologação exigido.');
 return{reason:'Vinha — assinatura fictícia de homologação',external_reference:input.requestId,payer_email:input.payerEmail,auto_recurring:{frequency:1,frequency_type:'months',transaction_amount:input.amountCents/100,currency_id:'BRL',start_date:first.toISOString()},back_url:back.href,status:'pending'};
}
export function validateMercadoSubscriptionSnapshot(value:unknown,expected:TestSubscriptionDraft){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Resposta inválida.');
 const body=value as Record<string,unknown>,rec=body.auto_recurring as Record<string,unknown>|undefined;
 if(typeof body.id!=='string'||!body.id||body.id.length>200||body.external_reference!==expected.requestId||body.payer_email!==expected.payerEmail||!rec||typeof rec!=='object'||Array.isArray(rec)||rec.currency_id!=='BRL'||typeof rec.transaction_amount!=='number'||!Number.isFinite(rec.transaction_amount)||rec.transaction_amount<=0||Math.abs(rec.transaction_amount*100-expected.amountCents)>0.000001||rec.frequency!==1||rec.frequency_type!=='months'||rec.start_date!==expected.firstChargeAt)throw Error('Assinatura divergente do pedido.');
 if(!['pending','authorized','paused','cancelled'].includes(String(body.status)))throw Error('Estado da assinatura não reconhecido.');
 if(body.live_mode!==false)throw Error('Modo de teste não comprovado pela resposta.');
 // This is not settlement evidence, even if the authorization was accepted.
 return{id:body.id,status:String(body.status),paymentConfirmed:false as const};
}
export function mercadoCredentialSummary(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Resposta da conta inválida.');
 const body=value as Record<string,unknown>;
 if(!(typeof body.id==='number'&&Number.isSafeInteger(body.id)&&body.id>0)||body.site_id!=='MLB')throw Error('Conta brasileira não comprovada.');
 return{credentialAccepted:true,testIdentityConfirmed:Array.isArray(body.tags)&&body.tags.includes('test_user')};
}
// Format check only; neither prefix proves that the account is a test seller.
// Accepted solely by read-only diagnostic tools, never by a payment permission gate.
export function mercadoDiagnosticToken(value:string){
 const token=value.trim();
 if(!/^(?:TEST-|APP_USR-)[A-Za-z0-9_-]{10,4000}$/.test(token))throw Error('Informe o Access Token, não a Public Key.');
 return token;
}
