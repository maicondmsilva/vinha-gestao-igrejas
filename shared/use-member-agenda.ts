import {useEffect,useRef,useState} from 'react';
import type {TicketOrder} from './event-tickets';
import {agendaError,type AgendaEvent,type InboxItem,type MemberTicket} from './member-agenda';
import type {ChurchRpc} from './member-church';
export function useMemberAgenda(rpc:ChurchRpc,org:string,unit:string,authenticated:boolean,past=false,active=true){
 const [commerceOrders,setCommerceOrders]=useState<TicketOrder[]>([]);
 const [events,setEvents]=useState<AgendaEvent[]>([]),[tickets,setTickets]=useState<MemberTicket[]>([]),[inbox,setInbox]=useState<InboxItem[]>([]),[available,setAvailable]=useState(true),[loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[error,setError]=useState(''),[privateError,setPrivateError]=useState(''),[revision,setRevision]=useState(0);
 const client=useRef(rpc),epoch=useRef(0),mutation=useRef(false);client.current=rpc;
 useEffect(()=>setNotice(''),[org,unit,authenticated]);
 useEffect(()=>{let live=true,sequence=0;epoch.current++;mutation.current=false;setBusy(false);setEvents([]);setCommerceOrders([]);setTickets([]);setInbox([]);setError('');setPrivateError('');
  async function load(initial:boolean){const seq=++sequence;if(initial)setLoading(true);
   const request=(name:string,args:Record<string,unknown>)=>Promise.resolve(client.current.rpc(name,args)).catch(()=>({data:null,error:{message:'connection'}}));
   const [agenda,own,messages,commerce]=await Promise.all([unit?request('member_agenda',{p_org:org,p_unit:unit,p_past:past}):null,authenticated?request('member_agenda_self',{p_org:org,p_action:'tickets'}):null,authenticated?request('member_agenda_self',{p_org:org,p_action:'inbox',p_unit:unit||null}):null,authenticated?request('member_event_ticket_orders',{p_org:org}):null]);
   if(!live||seq!==sequence)return;setLoading(false);
   if(agenda){const d=agenda.data as {unitId:string;available:boolean;items:AgendaEvent[]}|null;if(agenda.error||d?.unitId!==unit||!Array.isArray(d.items)){setEvents([]);setError('Não foi possível consultar a agenda. Atualize para tentar novamente.')}else{setEvents(d.items);setAvailable(d.available);setError('')}}
   if(authenticated){const commerceData=commerce?.data as {items:TicketOrder[]}|null;setCommerceOrders(!commerce?.error&&Array.isArray(commerceData?.items)?commerceData.items:[]);const t=own?.data as {items:MemberTicket[]}|null,n=messages?.data as {items:InboxItem[]}|null;if(own?.error||messages?.error||!Array.isArray(t?.items)||!Array.isArray(n?.items)){setTickets([]);setInbox([]);setPrivateError('Não foi possível consultar seus tickets e notificações. Confira a conta e atualize.')}else{setTickets(t.items);setInbox(n.items);setPrivateError('')}}
  }
  if(active)void load(true);else setLoading(false);
  const timer=active?setInterval(()=>void load(false),60000):null;
  return()=>{live=false;sequence++;epoch.current++;if(timer)clearInterval(timer)}
 },[org,unit,authenticated,past,active,revision]);
 async function command(action:'register'|'cancel'|'read',id?:string,keys?:string[]){if(!authenticated){setNotice('Entre na conta para continuar.');return false}if(mutation.current)return false;mutation.current=true;setBusy(true);setNotice('');const version=epoch.current;
  try{const r=await client.current.rpc('member_agenda_self',{p_org:org,p_action:action,p_unit:unit||null,p_id:id||null,p_data:action==='read'?{keys:keys||[]}: {}});if(version!==epoch.current)return false;if(r.error)throw Error(agendaError(r.error.message));if(!(r.data as {ok?:boolean})?.ok)throw Error('Resultado não confirmado. Atualize antes de repetir.');if(action==='cancel')setTickets([]);if(action==='read')setInbox(items=>items.map(n=>keys?.includes(n.message_key)?{...n,read:true}:n));setNotice(action==='register'?'Inscrição gratuita confirmada. Consulte Meus tickets.':action==='cancel'?'Inscrição cancelada. O código anterior não é mais válido.':'Leitura registrada.');setRevision(n=>n+1);return true}catch(e){if(version===epoch.current)setNotice(e instanceof Error?e.message:'Falha de conexão. Atualize antes de repetir.');return false}finally{if(version===epoch.current){mutation.current=false;setBusy(false)}}
 }
 return {commerceOrders,events,tickets,inbox,available,loading,busy,notice,error,privateError,unread:inbox.filter(n=>!n.read).length,command,refresh:()=>setRevision(n=>n+1)};
}
