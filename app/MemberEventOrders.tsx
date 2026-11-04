'use client';
import {useEventTicketOrders} from '../shared/use-event-ticket-orders';
import {ticketMoney,ticketState} from '../shared/event-tickets';
import type {ChurchRpc} from '../shared/member-church';
export default function MemberEventOrders({rpc,org}:{rpc:ChurchRpc;org:string}){const m=useEventTicketOrders(rpc,org);return <section><h3>Tickets e reservas dos eventos</h3>{m.error&&<p role="alert">{m.error}</p>}{m.items.map(o=><article key={o.id}><h3>{o.title}</h3><p>{o.eventStatus==='cancelled'?'Evento cancelado':ticketState(o.state)} · {ticketMoney(o.total)}</p><p>{o.items.map(i=>i.name+' · '+i.ticket).join(' / ')}</p><a href={'/eventos/e-'+o.event+'?pedido='+o.id}>Consultar pedido e tickets →</a></article>)}{!m.error&&!m.items.length&&<p>Nenhum pedido neste modelo de inscrição.</p>}<button type="button" onClick={m.refresh}>Atualizar tickets e reservas</button></section>}
