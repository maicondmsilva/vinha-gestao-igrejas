export type TicketQuestion={id:string;label:string;kind:'text'|'email'|'date'|'cpf'|'phone'|'number'|'select'|'select_other'|'boolean';required:boolean;options:string[]};
export type TicketType={id:string;name:string;mode:'free'|'paid'|'reservation';price:string;starts:string;ends:string;perUser:number|null;perCpf:number|null;remaining:number|null};
export type TicketCatalog={commerceMode?:'event'|'sale';pickupAt?:string;pickupUntil?:string;pickupLocation?:string;enabled:boolean;allowGuests:boolean;authenticated:boolean;canPay:boolean;showRemaining:boolean;remaining:number|null;types:TicketType[];questions:TicketQuestion[]};
export type TicketParticipant={type:string;name:string;email:string;cpf:string;phone:string;answers:Record<string,string>};
export type TicketOrder={commerceMode?:'event'|'sale';ok:boolean;id:string;event:string;state:string;expires:string;subtotal:string;discount:string;total:string;buyerName:string;buyerEmail:string;checkoutState:string;checkoutUrl?:string;questions:TicketQuestion[];items:(TicketParticipant&{id:string;ticket:string;price:string;code:string|null;checkedIn:string|null})[];title?:string;starts?:string;eventStatus?:string};
export const ticketMoney=(value:string|number)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(Number(value)/100);
export const ticketState=(value:string)=>({holding:'Aguardando pagamento',reserved:'Reserva aguardando pagamento',confirmed:'Confirmado',cancelled:'Cancelado',expired:'Prazo encerrado',payment_review:'Pagamento em conferência'}[value]||'Em acompanhamento');
export const ticketMode=(value:string)=>({free:'Gratuito',paid:'Pago',reservation:'Reserva'}[value]||value);
const object=(v:unknown):v is Record<string,unknown>=>!!v&&typeof v==='object'&&!Array.isArray(v);
const text=(v:unknown,n:number)=>typeof v==='string'&&v.length<=n;
export function ticketBuyerValid(v:unknown){if(!object(v)||Object.keys(v).some(k=>!['buyerName','buyerEmail','emailConfirmation','items','coupon','intent','expectedTotal','revision','emailConsent'].includes(k)))return false;
 if('emailConsent' in v&&typeof v.emailConsent!=='boolean')return false;
 if(!text(v.buyerName,160)||String(v.buyerName).trim().length<2||!text(v.buyerEmail,254)||!text(v.emailConfirmation,254)||!text(v.coupon,40)||!['pay','reserve'].includes(String(v.intent))||!Array.isArray(v.items)||v.items.length<1||v.items.length>20)return false;
 return v.items.every(i=>object(i)&&Object.keys(i).length===6&&['type','name','email','cpf','phone','answers'].every(k=>k in i)&&text(i.type,36)&&text(i.name,160)&&String(i.name).trim().length>=2&&text(i.email,254)&&text(i.cpf,18)&&text(i.phone,22)&&object(i.answers)&&Object.keys(i.answers).length<=30&&Object.values(i.answers).every(a=>text(a,1000)));}

export function ticketCsv(rows:string[][]){return '\uFEFF'+rows.map(row=>row.map(v=>'"'+((/^[\s\u0000-\u001f]*[=+@-]/.test(v)?"'":'')+v).replaceAll('"','""')+'"').join(';')).join('\r\n')}
