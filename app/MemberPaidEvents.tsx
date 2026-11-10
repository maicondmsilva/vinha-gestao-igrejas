'use client';
import type {ChurchRpc} from '../shared/member-church';
import {usePaidEvents} from '../shared/use-paid-events';
import {memberMoney} from '../shared/member-services';
export default function MemberPaidEvents({rpc,org,unit}:{rpc:ChurchRpc;org:string;unit:string}){
 const m=usePaidEvents(rpc,org,unit);return <section className="member-agenda"><h3>Eventos com ingresso pago</h3>{m.notice&&<p role="status">{m.notice}</p>}{m.items.map(e=><article key={e.id}><h4>{e.title} · {memberMoney(e.amount)}</h4><p>Uma inscrição por conta. A vaga é reservada por 30 minutos. Pagamento atrasado pode exigir conferência.</p><button type="button" disabled={m.busy} onClick={()=>void m.buy(e.id,crypto.randomUUID())}>Reservar ingresso pago</button></article>)}{m.orders.map(o=><p key={o.id}>Pedido {o.id}: {o.state==='confirmed'?'Ticket confirmado':o.state==='payment_review'?'Pagamento em conferência pela igreja':o.state==='cancelled'?'Cancelado':'Aguardando pagamento'}.</p>)}<button type="button" disabled={m.busy} onClick={m.refresh}>Atualizar ingressos pagos</button></section>;
}
