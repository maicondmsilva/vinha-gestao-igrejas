export type BillingEvent='upcoming'|'overdue'|'paid';
type InvoiceState={status:string;due_at:number;paid_at?:number|null};
const day=86400000;
export function billingEvent(invoice:InvoiceState,now=Date.now()):BillingEvent|null{
 // Do not send historical receipts merely because notifications were enabled later.
 if(invoice.status==='paid')return invoice.paid_at&&invoice.paid_at>=now-day&&invoice.paid_at<=now?'paid':null;
 if(invoice.status!=='open')return null;
 return invoice.due_at<now?'overdue':invoice.due_at<=now+3*day?'upcoming':null;
}
export function billingEventApplicable(invoice:InvoiceState,event:string,now=Date.now()){return billingEvent(invoice,now)===event}
