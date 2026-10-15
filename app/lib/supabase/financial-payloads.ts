// Pure payload builders: no credentials, HTTP calls, or card details.
export type CompanyProfile={legalName:string;taxId:string;email:string;city:string;state:string;municipalRegistration:string;logoUrl:string;serviceCode:string;serviceName:string;description:string;taxes:Record<string,unknown>;fiscalReviewed:boolean};
export function validDate(value:string){const d=new Date(`${value}T12:00:00Z`);return /^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===value}
export function validCnpj(value:string){
 const s=value.replace(/\D/g,'');if(s.length!==14||/^(\d)\1+$/.test(s))return false;
 const digit=(base:string,weights:number[])=>{const n=base.split('').reduce((sum,x,i)=>sum+Number(x)*weights[i],0)%11;return n<2?0:11-n};
 const a=digit(s.slice(0,12),[5,4,3,2,9,8,7,6,5,4,3,2]),b=digit(s.slice(0,12)+a,[6,5,4,3,2,9,8,7,6,5,4,3,2]);return s.endsWith(`${a}${b}`);
}
export function httpsUrl(value:unknown){if(!value)return null;try{const u=new URL(String(value));return u.protocol==='https:'&&!u.username&&!u.password?u.href:null}catch{return null}}
function amount(value:number){if(!Number.isSafeInteger(value)||value<1)throw new Error('Valor financeiro inválido.');return value/100}
export function recurringPayload(input:{id:string;amountCents:number;firstDueDate:string;origin:string;name:string;email:string;taxId:string},now=Date.now()){
 if(!validDate(input.firstDueDate)||new Date(`${input.firstDueDate}T23:59:59-03:00`).getTime()<=now)throw new Error('Informe uma primeira cobrança futura.');
 const origin=httpsUrl(input.origin);if(!origin)throw new Error('Endereço de retorno inválido.');
 if(!input.name||!input.taxId||!/^\S+@\S+\.\S+$/.test(input.email))throw new Error('Complete os dados do pagador.');
 const callback=`${new URL(origin).origin}/admin-vinha/financeiro-integracoes`;
 return{billingTypes:['CREDIT_CARD'],chargeTypes:['RECURRENT'],minutesToExpire:60,externalReference:input.id,
 callback:{successUrl:`${callback}?retorno=recebido`,cancelUrl:`${callback}?retorno=cancelado`,expiredUrl:`${callback}?retorno=expirado`},
 items:[{name:'Assinatura mensal Vinha · homologação',description:'Autorização recorrente em ambiente de testes',quantity:1,value:amount(input.amountCents)}],
 customerData:{name:input.name,email:input.email,cpfCnpj:input.taxId.replace(/\D/g,'')},
 subscription:{cycle:'MONTHLY',nextDueDate:`${input.firstDueDate} 12:00:00`}};
}
export function fiscalPayload(input:{id:string;paymentId:string;amountCents:number;effectiveDate:string;company:CompanyProfile}){
 const c=input.company;
 if(!validCnpj(c.taxId)||!c.legalName||!c.city||!c.fiscalReviewed)throw new Error('Valide os dados da Vinha com a contabilidade antes de emitir.');
 if(!c.serviceCode||!c.serviceName||!c.description||!c.taxes||Array.isArray(c.taxes)||typeof c.taxes!=='object'||!Object.keys(c.taxes).length)throw new Error('Informe o serviço e os tributos aprovados pela contabilidade.');
 if(!validDate(input.effectiveDate)||!/^pay_[a-zA-Z0-9_]+$/.test(input.paymentId))throw new Error('Data ou cobrança Asaas inválida. O identificador do checkout não é uma cobrança fiscal.');
 return{payment:input.paymentId,externalReference:input.id,serviceDescription:c.description,observations:'Homologação Vinha — documento de teste sem valor fiscal',
 value:amount(input.amountCents),deductions:0,effectiveDate:input.effectiveDate,municipalServiceCode:c.serviceCode,municipalServiceName:c.serviceName,updatePayment:false,taxes:c.taxes};
}
const escapeHtml=(value:string)=>value.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export function billingEmailHtml(title:string,content:string,logo?:string){const url=httpsUrl(logo);return `<div style="background:#f4f7f3;padding:32px;font-family:Arial,sans-serif;color:#173d30"><div style="max-width:560px;margin:auto;background:#fff;border-radius:16px;padding:32px">${url?`<img src="${escapeHtml(url)}" alt="Vinha" style="max-width:160px;max-height:70px">`:'<p style="font-size:28px;font-weight:bold">Vinha</p>'}<h1 style="font-size:22px">${escapeHtml(title)}</h1><p style="line-height:1.7">${escapeHtml(content)}</p><hr style="border:0;border-top:1px solid #dfe8e1"><small>Equipe Vinha · Gestão que frutifica</small></div></div>`}
