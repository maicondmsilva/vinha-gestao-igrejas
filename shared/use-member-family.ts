import {useEffect,useRef,useState} from 'react';
import type {ChurchRpc} from './member-church';
import {familyError,type FamilyKind,type FamilyPage,type FamilySession} from './member-family';
import {learningNonce} from './member-learning';
export function useMemberFamily(rpc:ChurchRpc,org:string,unit:string,authenticated:boolean,kind:FamilyKind,selected='',offset=0,active=true){
 const [page,setPage]=useState<FamilyPage|null>(null),[sessions,setSessions]=useState<FamilySession[]>([]),[sessionMore,setSessionMore]=useState(false),[busy,setBusy]=useState(false),[loading,setLoading]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[revision,setRevision]=useState(0);
 const client=useRef(rpc),epoch=useRef(0),mutation=useRef(false),retry=useRef({key:'',nonce:''});client.current=rpc;
 useEffect(()=>setNotice(''),[org,unit,authenticated,kind,selected]);
 useEffect(()=>{let live=true;const token=++epoch.current;setPage(null);setSessions([]);setSessionMore(false);setError('');setBusy(false);mutation.current=false;if(!active||!authenticated||!unit){setLoading(false);return}setLoading(true);
  const call=(action:string,id:string|null=null)=>Promise.resolve(client.current.rpc('member_family',{p_org:org,p_unit:unit,p_action:action,p_id:id,p_offset:offset})).catch(()=>({data:null,error:{message:'connection'}}));
  void Promise.all([call(kind==='kids'?'kids.list':selected?'cells.detail':'cells.list',kind==='cells'?selected||null:null),kind==='kids'&&selected?call('kids.sessions',selected):null]).then(([a,b])=>{if(!live||token!==epoch.current)return;setLoading(false);if(a.error||b?.error){setError(familyError(a.error?.message||b?.error?.message));return}setPage(a.data as FamilyPage);setSessions((b?.data as {items?:FamilySession[]}|null)?.items||[]);setSessionMore(!!(b?.data as {more?:boolean}|null)?.more)});return()=>{live=false;epoch.current++};
 },[org,unit,authenticated,kind,selected,offset,revision,active]);
 async function command(action:string,id:string|null=null,version:number|null=null,data:Record<string,unknown>={}){if(!authenticated||mutation.current)return false;mutation.current=true;setBusy(true);setNotice('');const token=epoch.current;
  try{const payload={...data};if(['kids.create','kids.edit','cells.leave'].includes(action)){const key=JSON.stringify([action,id,data]);if(retry.current.key!==key)retry.current={key,nonce:learningNonce()};payload.nonce=retry.current.nonce}
   const r=await client.current.rpc('member_family',{p_org:org,p_unit:unit,p_action:action,p_id:id,p_version:version,p_data:payload});if(token!==epoch.current)return false;if(r.error)throw Error(familyError(r.error.message+' '+r.error.code));if(!(r.data as {ok?:boolean})?.ok)throw Error('Resultado não confirmado. Atualize a consulta.');retry.current={key:'',nonce:''};setRevision(n=>n+1);setNotice(action==='kids.reserve'?'Reserva registrada. A entrada só será confirmada presencialmente pela equipe.':action==='kids.pickup'?'Solicitação de retirada registrada na recepção. Aguarde a conferência presencial.':action.endsWith('cancel')?'Solicitação cancelada.':'Solicitação enviada para conferência da igreja.');return true;
  }catch(e){if(token===epoch.current)setNotice(e instanceof Error?e.message:'Falha de conexão.');return false}finally{if(token===epoch.current){mutation.current=false;setBusy(false)}}
 }
 return{page,sessions,sessionMore,busy,loading,error,notice,command,refresh:()=>setRevision(n=>n+1)};
}
