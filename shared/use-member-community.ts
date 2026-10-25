import {useEffect,useRef,useState} from 'react';
import type {ChurchRpc} from './member-church';
import {communityError,communityNonce,type CommunityItem,type CommunityKind} from './member-community';
export function useMemberCommunity(rpc:ChurchRpc,org:string,unit:string,authenticated:boolean,kind:CommunityKind,offset=0,active=true){
 const [own,setOwn]=useState<CommunityItem[]>([]),[directory,setDirectory]=useState<CommunityItem[]>([]),[more,setMore]=useState(false),[loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[revision,setRevision]=useState(0);
 const client=useRef(rpc),epoch=useRef(0),mutation=useRef(false),retry=useRef({key:'',nonce:''});client.current=rpc;
 useEffect(()=>{setNotice('');retry.current={key:'',nonce:''}},[org,unit,authenticated,kind]);
 useEffect(()=>{let live=true;const token=++epoch.current;setOwn([]);setDirectory([]);setError('');setMore(false);setBusy(false);mutation.current=false;
  if(!active)return;setLoading(true);
  const request=(name:string,args:Record<string,unknown>)=>Promise.resolve(client.current.rpc(name,args)).catch(()=>({data:null,error:{message:'connection'}}));
  void Promise.all([authenticated?request('member_community_self',{p_org:org,p_unit:unit||null,p_action:kind,p_offset:offset}):null,unit&&(kind==='groups'||kind==='testimonies')?request('member_community_public',{p_org:org,p_unit:unit,p_kind:kind,p_offset:offset}):null]).then(results=>{
   if(!live||token!==epoch.current)return;setLoading(false);let hasMore=false;for(let i=0;i<results.length;i++){const r=results[i];if(!r)continue;const d=r.data as {items:CommunityItem[];more:boolean}|null;if(r.error||!Array.isArray(d?.items)){setError(r.error?communityError(r.error.message):'Não foi possível consultar esta lista.');continue}if(i===0)setOwn(d.items);else setDirectory(d.items);hasMore||=d.more}setMore(hasMore);
  });return()=>{live=false;epoch.current++};
 },[org,unit,authenticated,kind,offset,active,revision]);
 async function command(action:string,row?:CommunityItem,data:Record<string,unknown>={}){if(!authenticated){setNotice('Entre na conta para continuar.');return false}if(mutation.current)return false;mutation.current=true;setBusy(true);setNotice('');const token=epoch.current,key=action+JSON.stringify(data);const payload={...data};if(action.endsWith('.create')){if(retry.current.key!==key)retry.current={key,nonce:communityNonce()};payload.nonce=retry.current.nonce}
  try{const r=await client.current.rpc('member_community_self',{p_org:org,p_unit:unit||null,p_action:action,p_id:row?.id||null,p_version:row?.version||null,p_data:payload});if(token!==epoch.current)return false;if(r.error)throw Error(communityError(r.error.message));if(!(r.data as {ok?:boolean})?.ok)throw Error('Resultado não confirmado. Atualize antes de repetir.');retry.current={key:'',nonce:''};setNotice('Solicitação confirmada. A lista será atualizada.');setRevision(n=>n+1);return true}catch(e){if(token===epoch.current)setNotice(e instanceof Error?e.message:'Falha de conexão.');return false}finally{if(token===epoch.current){mutation.current=false;setBusy(false)}}
 }
 return {own,directory,more,loading,busy,error,notice,command,refresh:()=>setRevision(n=>n+1)};
}
