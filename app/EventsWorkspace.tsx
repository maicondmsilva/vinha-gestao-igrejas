"use client";
import MemberAgendaAdmin from './MemberAgendaAdmin';
import MemberServicesAdmin from './MemberServicesAdmin';
export default function EventsWorkspace({unitId}:{unitId:string}){return <div className="content"><h1>Cultos e eventos</h1><p>Agenda, inscrições e confirmação de entrada integradas ao aplicativo da igreja. Para ingresso pago, configure o preço enquanto o evento estiver em rascunho.</p><MemberAgendaAdmin key={unitId} unitId={unitId}/><details><summary>Ingressos pagos e recebimentos</summary><MemberServicesAdmin mode="events"/></details></div>}
