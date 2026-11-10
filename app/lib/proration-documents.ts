type CreditReturn={amount_cents:unknown};
export function summarizeProrationDocument(row: {id:string;kind:string;amount_cents:unknown;created_at:string;saas_proration_credit_uses?:{amount_cents:unknown;saas_proration_credit_returns?:CreditReturn[]|CreditReturn|null}[]}) {
 const cents=(value:unknown)=>{if(typeof value==='number'&&!Number.isSafeInteger(value))throw Error('Valor fora da precisão suportada.');const text=String(value);if(!/^\d+$/.test(text))throw Error('Valor inválido.');return BigInt(text)};
 if((row.saas_proration_credit_uses||[]).length>=1000)throw Error('Histórico de crédito exige paginação.');
 const amount=cents(row.amount_cents),used=(row.saas_proration_credit_uses||[]).reduce((sum,item)=>{const consumed=cents(item.amount_cents),raw=item.saas_proration_credit_returns,entries=raw?(Array.isArray(raw)?raw:[raw]):[];if(entries.length>1)throw Error('Devolução duplicada.');const returned=entries.reduce((total,entry)=>total+cents(entry.amount_cents),BigInt(0));if(returned>consumed)throw Error('Devolução de crédito inconsistente.');return sum+consumed-returned},BigInt(0));
 if(!['credit','additional_invoice'].includes(row.kind)||used>amount||(row.kind!=='credit'&&used!==BigInt(0)))throw Error('Documento inconsistente.');
 return{id:row.id,kind:row.kind,createdAt:row.created_at,amountCents:String(amount),usedCents:String(used),remainingCents:row.kind==='credit'?String(amount-used):null,externalChargeCreated:false};
}
