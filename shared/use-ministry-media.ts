import {useEffect,useRef,useState} from 'react';
import type {ChurchRpc} from './member-church';
import type {MinistryMedia} from './ministry-media';
export function useMinistryMedia(rpc:ChurchRpc,org:string,unit:string,kind:'video'|'live',authenticated:boolean){
 const [items,setItems]=useState<MinistryMedia[]>([]),[history,setHistory]=useState<{media_id:string;position_seconds:number;favorite:boolean}[]>([]),[loading,setLoading]=useState(false),[error,setError]=useState(''),[page,setPage]=useState(0),[revision,setRevision]=useState(0);const epoch=useRef(0);
 useEffect(()=>{setPage(0)},[org,unit,kind]);
 useEffect(()=>{let live=true,sequence=0;epoch.current++;setItems([]);setHistory([]);setError('');if(!org||!unit)return;setLoading(true);
  async function load(){const seq=++sequence;try{const r=await rpc.rpc('member_media',{p_org:org,p_unit:unit,p_kind:kind,p_offset:page*20});if(!live||seq!==sequence)return;if(r.error||!Array.isArray((r.data as {items?:unknown})?.items))throw Error();setItems((r.data as {items:MinistryMedia[]}).items);if(authenticated){const h=await rpc.rpc('member_media_self',{p_org:org,p_unit:unit,p_action:'history'});if(!live||seq!==sequence)return;if(!h.error)setHistory((h.data as {items:typeof history}).items)}}catch{if(live&&seq===sequence){setItems([]);setError('Não foi possível consultar a mídia da igreja. Atualize para tentar novamente.')}}finally{if(live&&seq===sequence)setLoading(false)}}
  void load();const timer=setInterval(()=>void load(),60000);return()=>{live=false;epoch.current++;clearInterval(timer)};
 },[rpc,org,unit,kind,page,authenticated,revision]);
 return{items,history,loading,error,page,setPage,refresh:()=>setRevision(v=>v+1)};
}
