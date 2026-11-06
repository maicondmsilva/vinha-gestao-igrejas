export type FinanceOrigin={event_name?:string;event_number?:string;event_mode?:string;digital_kind?:string;display_description?:string;annotation_notes?:string;annotation_version?:number};
export function financeEntryDescription(e:{description:string}&FinanceOrigin){return e.display_description||e.description}
export function financeOriginLabel(e:FinanceOrigin){return e.event_name?`${e.event_mode==='sale'?'Venda':'Evento'}${e.event_number?' '+e.event_number:''} · ${e.event_name}`:''}
