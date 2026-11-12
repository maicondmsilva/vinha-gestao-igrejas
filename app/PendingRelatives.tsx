'use client';
import {useEffect,useState} from 'react';
import {relationLabels,journeys,type Relation} from './lib/family';
import {settingsUrl} from './lib/settings-navigation';

type Candidate={id:string;name:string;birth_date:string|null;journey:string|null};
type Item={id:string;requester:string;unit:string;name:string;birth_date:string|null;relation:Relation;same_household:boolean;createdAt:string;canApprove:boolean;candidates:Candidate[]};
const day=(d:string|null)=>d?d.split('-').reverse().join('/'):'nascimento não informado';

/** Pessoas › Perfis pendentes › Familiares: pedidos de inclusão de familiar vindos do aplicativo. */
export default function PendingRelatives(){
 const[items,setItems]=useState<Item[]>([]),[notice,setNotice]=useState(''),[busy,setBusy]=useState(''),[journey,setJourney]=useState<Record<string,string>>({}),[revision,setRevision]=useState(0);
 useEffect(()=>{const c=new AbortController();fetch(settingsUrl('/api/member-relatives-review'),{cache:'no-store',signal:c.signal}).then(async r=>{if(r.status===403){setItems([]);return}const d=await r.json() as {items?:Item[];error?:string};if(!r.ok)throw Error(d.error||'Não foi possível carregar os pedidos de familiares.');setItems(d.items||[])}).catch(e=>{if(!c.signal.aborted)setNotice(e.message)});return()=>c.abort()},[revision]);
 async function review(i:Item,body:Record<string,string>,ok:string){setBusy(i.id);setNotice('');
  try{const r=await fetch(settingsUrl('/api/member-relatives-review'),{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({id:i.id,...body})});const d=await r.json().catch(()=>({})) as {error?:string};if(!r.ok)throw Error(d.error||'Não foi possível concluir.');setNotice(ok);setRevision(n=>n+1)}
  catch(e){setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy('')}}
 function reject(i:Item){const reason=prompt(`Por que o pedido de ${i.requester} não será aprovado? A pessoa verá este motivo no aplicativo.`);if(reason===null)return;if(reason.trim().length<5){setNotice('Informe o motivo com pelo menos 5 caracteres.');return}void review(i,{decision:'reject',reason:reason.trim()},'Pedido não aprovado. A pessoa foi avisada no aplicativo.')}
 if(!items.length&&!notice)return null;
 return <section className="pending-profiles pending-relatives" aria-labelledby="pending-relatives-title">
  <header><div><p>Pessoas</p><h2 id="pending-relatives-title">Familiares <span>{items.length}</span></h2><small>Pedidos de inclusão de familiar enviados pelo aplicativo. Confira se a pessoa já existe antes de cadastrar.</small></div></header>
  {notice&&<p className="pending-notice" role="status">{notice}</p>}
  <div className="pending-cards">{items.map(i=><article key={i.id}><span className="pending-church">{i.unit}</span>
   <b>{i.name}</b><small>{relationLabels[i.relation]||i.relation} de {i.requester} · {day(i.birth_date)}{i.same_household?' · mora junto':''}</small>
   {i.canApprove?<>
    {i.candidates.map(c=><button type="button" key={c.id} className="suggested" disabled={!!busy} onClick={()=>void review(i,{decision:'approve',person:c.id},'Familiar ligado ao cadastro existente.')}>Ligar a esta pessoa: {c.name} ({day(c.birth_date)})</button>)}
    <label className="pending-type">Etapa do novo cadastro<select value={journey[i.id]||'Visitante'} onChange={e=>setJourney({...journey,[i.id]:e.target.value})}>{journeys.map(j=><option key={j}>{j}</option>)}</select></label>
    <button type="button" disabled={!!busy} onClick={()=>void review(i,{decision:'approve',journey:journey[i.id]||'Visitante'},'Familiar cadastrado e ligado.')}>{busy===i.id?'Salvando…':i.candidates.length?'Cadastrar como pessoa nova':'Aprovar e cadastrar'}</button>
    <button type="button" className="pending-reject" disabled={!!busy} onClick={()=>reject(i)}>Não aprovar</button>
   </>:<small>Aguardando quem pode aprovar nesta igreja.</small>}
  </article>)}</div>
 </section>;
}
