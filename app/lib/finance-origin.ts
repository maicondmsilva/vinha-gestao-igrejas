import {financeMoney} from './finance-f1.ts';
export type DigitalPayment={receipt:string;state:string;principal:string;interest:string;fine:string;discount:string;gross:string;fee:string;refund:string;net:string;history:{kind:string;amount:string;date:string|null}[]};
/** Informative composition of one launch: the amount is what moved in the account (net). */
export type FinanceComposition={base:string;interest:string;fine:string;discount:string;fee:string;net:string};
export type FinanceOrigin={composition?:FinanceComposition;event_name?:string;event_number?:string;event_mode?:string;digital_kind?:string;digital_payment?:DigitalPayment;display_description?:string;annotation_notes?:string;annotation_version?:number};
export function financeEntryDescription(e:{description:string}&FinanceOrigin){return e.display_description||e.description}
export function financeOriginLabel(e:FinanceOrigin){return e.event_name?`${e.event_mode==='sale'?'Venda':'Evento'}${e.event_number?' '+e.event_number:''} · ${e.event_name}`:''}
const cents=(v:string)=>financeMoney(v||'0');
/** One short line explaining how the original value became the amount that moved in the account. */
export function financeCompositionText(c:FinanceComposition|undefined,kind:string,digital=false){
 if(!c)return '';
 const fee=BigInt(c.fee||'0'),parts=[`${digital?'Bruto':'Valor original'} ${cents(c.base)}`];
 if(BigInt(c.interest||'0'))parts.push(`Juros ${cents(c.interest)}`);
 if(BigInt(c.fine||'0'))parts.push(`Multa ${cents(c.fine)}`);
 if(BigInt(c.discount||'0'))parts.push(`Desconto ${cents(c.discount)}`);
 if(fee>BigInt(0))parts.push(`Taxa ${cents(c.fee)}`);
 if(fee<BigInt(0))parts.push(`Taxa devolvida ${cents((-fee).toString())}`);
 return parts.length>1?parts.join(' · ')+` · ${kind==='income'?'Líquido':'Total'} ${cents(c.net)}`:'';
}
