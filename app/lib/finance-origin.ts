export type DigitalPayment={receipt:string;state:string;principal:string;interest:string;fine:string;discount:string;gross:string;fee:string;refund:string;net:string;history:{kind:string;amount:string;date:string|null}[]};
export type FinanceOrigin={event_name?:string;event_number?:string;event_mode?:string;digital_kind?:string;digital_payment?:DigitalPayment;display_description?:string;annotation_notes?:string;annotation_version?:number};
export function financeEntryDescription(e:{description:string}&FinanceOrigin){return e.display_description||e.description}
export function financeOriginLabel(e:FinanceOrigin){return e.event_name?`${e.event_mode==='sale'?'Venda':'Evento'}${e.event_number?' '+e.event_number:''} · ${e.event_name}`:''}
