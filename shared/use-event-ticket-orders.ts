import {useEffect,useState} from 'react';
import type {ChurchRpc} from './member-church';
import type {TicketOrder} from './event-tickets';
export function useEventTicketOrders(rpc:ChurchRpc,org:string){const [items,setItems]=useState<TicketOrder[]>([]),[error,setError]=useState(''),[revision,setRevision]=useState(0);useEffect(()=>{let live=true;setItems([]);setError('');Promise.resolve(rpc.rpc('member_event_ticket_orders',{p_org:org})).then(r=>{if(!live)return;if(r.error){setError('Entre na sua conta para consultar tickets e reservas.');return}setItems((r.data as {items:TicketOrder[]}).items||[])}).catch(()=>{if(live)setError('Não foi possível atualizar os pedidos.')});return()=>{live=false}},[rpc,org,revision]);return{items,error,refresh:()=>setRevision(v=>v+1)}}
