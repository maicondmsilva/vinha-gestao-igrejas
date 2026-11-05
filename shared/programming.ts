import type {AgendaEvent} from './member-agenda.ts';

export type EventCategory={id:string;name:string;color:string;active:boolean;version:number};
export type ProgrammingEvent=AgendaEvent&{display_id?:number|string;commerce_mode?:'event'|'sale';pickup_at?:string|null;category_id:string|null;category_name:string|null;category_color:string|null;cover_url:string;series_id:string|null;price_cents:string;purpose_id:string|null};
export type ProgrammingSection='agenda'|'proximos'|'encerrados'|'todos'|'categorias'|'vendas';
export const programmingSections:readonly ProgrammingSection[]=['agenda','proximos','encerrados','todos','categorias','vendas'];
export const programmingLabels:Record<ProgrammingSection,string>={vendas:'Vendas e encomendas',agenda:'Agenda da igreja',proximos:'Próximos eventos',encerrados:'Eventos encerrados',todos:'Eventos',categorias:'Categorias de eventos'};
export function programmingSection(value:string|null):ProgrammingSection{return programmingSections.includes(value as ProgrammingSection)?value as ProgrammingSection:'proximos'}
export function programmingHref(section:ProgrammingSection,search:string){const p=new URLSearchParams(search);p.set('pagina','eventos');p.set('secao',section);p.delete('celula');return '/painel?'+p}
export function localDay(value:string|Date=new Date()){return new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value))}
export function shiftDay(day:string,days:number){const d=new Date(day+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+days);return d.toISOString().slice(0,10)}
export function shiftMonth(day:string,months:number){const d=new Date(day+'T12:00:00Z');const date=d.getUTCDate();d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()+months);const last=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).getUTCDate();d.setUTCDate(Math.min(date,last));return d.toISOString().slice(0,10)}
export function calendarDays(day:string){const first=day.slice(0,7)+'-01',weekday=new Date(first+'T12:00:00Z').getUTCDay();return Array.from({length:42},(_,i)=>shiftDay(first,i-weekday))}
export function calendarRange(day:string,view:'month'|'week'|'day'){if(view==='month'){const days=calendarDays(day);return{from:days[0],to:shiftDay(days[41],1)}}if(view==='day'){return{from:day,to:shiftDay(day,1)}}const weekday=new Date(day+'T12:00:00Z').getUTCDay(),from=shiftDay(day,-weekday);return{from,to:shiftDay(from,7)}}
export function eventsOnDay(events:ProgrammingEvent[],day:string){const from=Date.parse(day+'T00:00:00-03:00'),to=Date.parse(shiftDay(day,1)+'T00:00:00-03:00');return events.filter(e=>Date.parse(e.starts_at)<to&&Date.parse(e.ends_at)>from)}
export function eventStatus(e:AgendaEvent,now=Date.now()){return e.status==='cancelled'?'Cancelado':e.status==='draft'?'Rascunho':Date.parse(e.ends_at)<now?'Encerrado':Date.parse(e.starts_at)<=now?'Em andamento':'Publicado'}
export function coverUrl(value:unknown){if(typeof value==='string'&&/^\/api\/event-images\/[0-9a-f-]{36}$/.test(value))return value;if(value==='')return '';if(typeof value!=='string'||value.length>2000)return null;try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password?u.href:null}catch{return null}}
