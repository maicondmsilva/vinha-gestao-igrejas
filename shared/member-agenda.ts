export type AgendaEvent={shared?:boolean;has_tickets?:boolean;public_path?:string;price_cents?:string;id:string;title:string;description:string;kind:'event'|'service';starts_at:string;ends_at:string;location:string;address:string;capacity:number;remaining:number;status:'draft'|'published'|'cancelled';version:number;registrations?:number};
export type MemberTicket={id:string;event_id:string;unit_id:string;name:string;status:'confirmed'|'cancelled';checked_in_at:string|null;version:number;title:string;starts_at:string;ends_at:string;location:string;address:string;event_status:string;code:string|null};
export type InboxItem={message_key:string;title:string;body:string;occurred_at:string;target:'content'|'agenda'|'ticket'|'profile'|'church'|'prayers'|'testimonies'|'groups'|'learning'|'kids'|'cells';target_id:string;read:boolean};
export function agendaError(message:string){
 if(message.includes('member_event_full'))return 'As vagas deste evento acabaram. Atualize a agenda.';
 if(message.includes('member_registration_identity'))return 'Complete seu cadastro e aguarde a conferência da igreja antes de se inscrever.';
 if(message.includes('member_event_changed')||message.includes('member_inbox_changed'))return 'As informações mudaram. Atualize a lista antes de repetir.';
 if(message.includes('member_cancel_closed'))return 'Não é possível cancelar pelo aplicativo após o início ou o check-in. Procure a equipe da igreja.';
 if(message.includes('member_checkin_closed'))return 'Check-in disponível de duas horas antes do início até seis horas após o término.';
 if(message.includes('member_event_closed'))return 'Este evento não está aberto para esta operação. Atualize a agenda.';
 if(message.includes('member_ticket_invalid'))return 'Ticket inválido, cancelado ou pertencente a outro evento.';
 if(message.includes('invalid_member_agenda'))return 'Revise os dados, as datas e a capacidade do evento.';
 return 'Operação não confirmada ou acesso indisponível. Atualize antes de repetir.';
}
export function agendaDate(value:string){const d=new Date(value);return Number.isNaN(d.getTime())?'Data indisponível':d.toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'})}
export function agendaLocal(value:string){const d=new Date(value);if(Number.isNaN(d.getTime()))return '';const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(d);const part=(name:string)=>parts.find(p=>p.type===name)?.value||'';return part('year')+'-'+part('month')+'-'+part('day')+'T'+part('hour')+':'+part('minute')}
export function ticketState(t:MemberTicket,now=Date.now()){return t.event_status==='cancelled'?'Evento cancelado':t.status==='cancelled'?'Inscrição cancelada':t.checked_in_at?'Entrada confirmada':new Date(t.ends_at).getTime()<now?'Encerrado':'Confirmado'}
