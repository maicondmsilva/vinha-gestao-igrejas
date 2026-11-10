import {useEffect,useRef,useState} from 'react';
import {churchError,type ChurchRpc,type ChurchState,type PublicPost} from './member-church';
export function useMemberChurch(rpc:ChurchRpc,org:string){
 const [state,setState]=useState<ChurchState|null>(null),[selected,setSelected]=useState(''),[posts,setPosts]=useState<PublicPost[]>([]),[busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[loading,setLoading]=useState(false),[revision,setRevision]=useState(0);
 const client=useRef(rpc);client.current=rpc;
 useEffect(()=>{let live=true;setState(null);setNotice('');client.current.rpc('member_church',{p_org:org,p_action:'state'}).then(r=>{if(!live)return;if(r.error)setNotice(churchError(r.error.message));else{const s=r.data as ChurchState;setState(s);setSelected(s.selectedUnit||'')}});return()=>{live=false}},[org,revision]);
 useEffect(()=>{let live=true;setPosts([]);setLoading(!!selected);if(selected)client.current.rpc('member_public_feed',{p_org:org,p_unit:selected}).then(r=>{if(!live)return;setLoading(false);if(r.error)setNotice('Não foi possível consultar os conteúdos públicos desta igreja.');else{const d=r.data as {unitId:string;items:PublicPost[]};if(d.unitId===selected)setPosts(d.items||[])}});return()=>{live=false}},[org,selected,revision]);
 async function command(action:'select'|'request'|'cancel',unit?:string,id?:string){if(busy||!state)return;const previous=selected;setBusy(true);setNotice('');if(action==='select'){setPosts([]);setSelected(unit||'')}
  try{const r=await client.current.rpc('member_church',{p_org:org,p_action:action,p_unit:unit||null,p_id:id||null});if(r.error)throw Error(churchError(r.error.message));const s=r.data as ChurchState;if(!s?.ok)throw Error('Resultado não confirmado. Atualize a consulta.');setState(s);setSelected(s.selectedUnit||'');setNotice(action==='select'?'Conteúdo público selecionado. Seu vínculo oficial não foi alterado.':action==='request'?'Transferência enviada para aprovação. Seu vínculo oficial permanece na igreja atual.':'Solicitação cancelada. O vínculo oficial não mudou.')}
  catch(e){if(action==='select')setSelected(previous);setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}
 }
 return {state,selected,posts,busy,notice,loading,command,refresh:()=>setRevision(n=>n+1)};
}
