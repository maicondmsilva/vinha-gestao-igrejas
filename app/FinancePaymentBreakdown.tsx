import {financeMoney} from './lib/finance-f1';
import type {DigitalPayment,FinanceComposition} from './lib/finance-origin';
const labels:Record<string,string>={gross:'Recebimento (valor que entrou na conta)',fee:'Ajuste de taxa',refund:'Devolução (valor que saiu da conta)',fee_credit:'Taxa devolvida'};
export default function FinancePaymentBreakdown({payment}:{payment:DigitalPayment}){
 return <section className="f1-payment-breakdown"><h3>Composição do recebimento</h3><div className="f1-form-grid">{[['Valor principal',payment.principal],['Juros',payment.interest],['Multa',payment.fine],['Desconto',payment.discount],['Bruto confirmado',payment.gross],['Taxas administrativas',payment.fee],['Devolvido ao comprador',payment.refund],['Saldo após taxas e devoluções',payment.net]].map(([label,value])=><label key={label}>{label}<input readOnly value={financeMoney(value)}/></label>)}</div><p className="f1-note">Valores informados pelo provedor. Na devolução, a taxa só volta se o provedor devolver.</p><details><summary>Histórico dos valores confirmados</summary><ul>{payment.history.map((item,i)=><li key={i}>{item.date?.split('-').reverse().join('/')} · {labels[item.kind]||item.kind}: {financeMoney(item.amount)}</li>)}</ul></details></section>;
}
/** Composition of a settlement launch: the amount already is what moved in the account. */
export function FinanceCompositionBreakdown({composition:c,kind}:{composition:FinanceComposition;kind:string}){
 const fee=BigInt(c.fee||'0'),rows:[string,string][]=[['Valor original',c.base],['Juros',c.interest],['Multa',c.fine],['Desconto',c.discount],[fee<BigInt(0)?'Taxa devolvida':'Taxa',(fee<BigInt(0)?-fee:fee).toString()],[kind==='income'?'Valor que entrou na conta':'Valor que saiu da conta',c.net]];
 return <section className="f1-payment-breakdown"><h3>Composição do lançamento</h3><div className="f1-form-grid">{rows.map(([label,value])=><label key={label}>{label}<input readOnly value={financeMoney(value)}/></label>)}</div><p className="f1-note">Juros, multa, desconto e taxa são informativos: o valor do lançamento já é o que movimentou a conta.</p></section>;
}
