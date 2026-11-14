import {useCallback,useEffect,useRef,useState} from 'react';
import type {ChurchRpc} from '../../shared/member-church';

/** Eventos salvos da conta (servidor), com troca otimista e volta atrás se a gravação falhar. */
export function useSavedEvents(rpc:ChurchRpc,org:string,authenticated:boolean){
 const [ids,setIds]=useState<string[]>([]),busy=useRef(false);
 useEffect(()=>{let live=true;setIds([]);if(!authenticated)return;
  void Promise.resolve(rpc.rpc('member_saved_events',{p_org:org,p_action:'list',p_event:null})).then(r=>{if(live&&!r.error)setIds(((r.data as {items?:string[]})?.items)||[])}).catch(()=>undefined);
  return()=>{live=false}},[rpc,org,authenticated]);
 const toggle=useCallback((id:string)=>{if(busy.current)return;busy.current=true;const had=ids.includes(id),before=ids;setIds(had?ids.filter(x=>x!==id):[id,...ids]);
  void Promise.resolve(rpc.rpc('member_saved_events',{p_org:org,p_action:had?'remove':'save',p_event:id})).then(r=>{if(r.error)setIds(before);else setIds(((r.data as {items?:string[]})?.items)||[])}).catch(()=>setIds(before)).finally(()=>{busy.current=false})},[rpc,org,ids]);
 return {ids,toggle};
}
