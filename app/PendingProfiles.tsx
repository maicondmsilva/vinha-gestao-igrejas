'use client';
import './pending-profiles.css';
import {useEffect,useMemo,useState} from 'react';
import {profileChanges,profileJourneys} from '../shared/member-profile-diff';
import {memberFields} from '../shared/member-profile';
import {settingsUrl} from './lib/settings-navigation';

type Candidate={id:string;name:string;unit:string|null;journey:string|null;status:string;email:boolean;cpf:boolean;current:boolean};
type Item={id:string;kind:'registration'|'update';unit_name:string;person_name:string|null;person_id:string|null;journey:string|null;payload:Record<string,string>;baseline:Record<string,string>|null;created_at:string;can_approve:boolean;identity_match?:{email:boolean;cpf:boolean;linked:boolean};candidates:Candidate[]};
const label=(field:string)=>memberFields.find(([id])=>id===field)?.[1]||field;
const initials=(name:string)=>name.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()||'?';
const journeyOf=(j:string|null)=>j==='Em integração'||j==='Visitante'?j:'Membro';
const nameOf=(i:Item)=>i.payload.full_name||i.person_name||'Sem nome';
const dateOf=(iso:string)=>new Date(iso).toLocaleDateString('pt-BR');
/** Candidato sugerido: o único que confere por e-mail e CPF; senão, o já indicado no pedido. */
function suggested(i:Item){const both=i.candidates.filter(c=>!c.current&&c.email&&c.cpf);return both.length===1?both[0].id:i.person_id||''}

/** Pessoas › Perfis pendentes: cadastros e alterações enviados pelo aplicativo. */
export default function PendingProfiles(){
 const [items,setItems]=useState<Item[]>([]),[revision,setRevision]=useState(0),[notice,setNotice]=useState(''),[filter,setFilter]=useState(''),[open,setOpen]=useState<Item|null>(null);
 useEffect(()=>{const c=new AbortController();fetch(settingsUrl('/api/member-profile-review'),{cache:'no-store',signal:c.signal}).then(async r=>{if(r.status===403){setItems([]);return}const d=await r.json() as {items?:Item[];error?:string};if(!r.ok)throw Error(d.error||'Não foi possível carregar os perfis pendentes.');setItems(d.items||[])}).catch(e=>{if(!c.signal.aborted)setNotice(e.message)});return()=>c.abort()},[revision]);
 const shown=useMemo(()=>items.filter(i=>!filter||journeyOf(i.journey)===filter),[items,filter]);
 if(!items.length&&!notice)return null;
 const groups:[string,string,Item[]][]=[['registration','Novos cadastros',shown.filter(i=>i.kind==='registration')],['update','Alterações de perfil',shown.filter(i=>i.kind!=='registration')]];
 return <section className="pending-profiles" aria-labelledby="pending-profiles-title">
  <header><div><p>Pessoas</p><h2 id="pending-profiles-title">Perfis pendentes <span>{items.length}</span></h2><small>Cadastros e alterações enviados pelo aplicativo. Nada muda no cadastro até a aprovação.</small></div>
   <div className="pending-filter" role="group" aria-label="Filtrar por tipo de perfil"><button type="button" aria-pressed={!filter} onClick={()=>setFilter('')}>Todos</button>{profileJourneys.map(([j,l])=><button key={j} type="button" aria-pressed={filter===j} onClick={()=>setFilter(j)}>{l}</button>)}</div></header>
  {notice&&<p className="pending-notice" role="status">{notice}</p>}
  {groups.map(([id,title,list])=><div key={id} className="pending-group"><h3>{title} <span>{list.length}</span></h3>
   {list.length?<div className="pending-cards">{list.map(i=><article key={i.id}><span className="pending-church">{i.unit_name}</span><i aria-hidden="true">{initials(nameOf(i))}</i><b>{nameOf(i)}</b><small>{journeyOf(i.journey)} · enviado em {dateOf(i.created_at)}</small>
    <button type="button" onClick={()=>{setNotice('');setOpen(i)}}>{i.can_approve?(i.kind==='registration'?'Analisar cadastro':'Analisar alteração'):'Ver pedido'}</button></article>)}</div>:<p className="pending-empty">Nada pendente{filter?' neste tipo':''}.</p>}</div>)}
  {open&&<ReviewSheet item={open} close={()=>setOpen(null)} done={msg=>{setOpen(null);setNotice(msg);setRevision(n=>n+1)}}/>}
 </section>;
}

function ReviewSheet({item,close,done}:{item:Item;close:()=>void;done:(msg:string)=>void}){
 const changes=profileChanges(item.payload,item.baseline||{});
 const [approved,setApproved]=useState<string[]>(changes.filter(c=>c.status!=='same').map(c=>c.field).concat(item.kind==='registration'&&!changes.some(c=>c.field==='full_name'&&c.status!=='same')&&item.payload.full_name?['full_name']:[]));
 const [journey,setJourney]=useState(journeyOf(item.journey)),[person,setPerson]=useState(suggested(item)),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const others=item.candidates.filter(c=>!c.current);
 async function send(fields:string[]){
  if(reason.trim().length<5){setError('Escreva um motivo com pelo menos cinco caracteres.');return}
  if(fields.length&&item.kind==='registration'&&!fields.includes('full_name')){setError('Para aprovar um novo cadastro, aprove também o nome completo.');return}
  setBusy(true);setError('');
  try{const r=await fetch(settingsUrl('/api/member-profile-review'),{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:item.id,fields,reason:reason.trim(),person:fields.length&&item.kind==='registration'&&person&&person!==item.person_id?person:'',journey:fields.length?journey:''})}),d=await r.json() as {error?:string};
   if(!r.ok)throw Error(d.error||'Não foi possível confirmar.');
   done(!fields.length?'Pedido recusado. O cadastro não foi alterado.':fields.length===changes.length?'Perfil aprovado.':'Perfil aprovado em parte: só as mudanças marcadas foram aplicadas.');
  }catch(e){setError(e instanceof Error?e.message:'Atualize e tente de novo.')}finally{setBusy(false)}
 }
 const toggle=(f:string)=>setApproved(a=>a.includes(f)?a.filter(x=>x!==f):[...a,f]);
 return <div className="pending-backdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget&&!busy)close()}}>
  <section className="pending-sheet" role="dialog" aria-modal="true" aria-labelledby="pending-sheet-title">
   <header><i aria-hidden="true">{initials(nameOf(item))}</i><div><h2 id="pending-sheet-title">{nameOf(item)}</h2><small>{item.kind==='registration'?'Novo cadastro':'Alteração de perfil'} · {item.unit_name} · {dateOf(item.created_at)}</small></div><button type="button" className="pending-close" aria-label="Fechar" disabled={busy} onClick={close}>×</button></header>
   <div className="pending-sheet-body">
    <label className="pending-type">Tipo de perfil<select value={journey} disabled={busy||!item.can_approve} onChange={e=>setJourney(e.target.value as typeof journey)}>{profileJourneys.map(([j,l])=><option key={j} value={j}>{l}</option>)}</select></label>
    {item.kind==='registration'&&<fieldset className="pending-link" disabled={busy||!item.can_approve}><legend>Ligar a conta do aplicativo a</legend>
     {item.person_id&&<label className={person===item.person_id?'on':''}><input type="radio" name="person" checked={person===item.person_id} onChange={()=>setPerson(item.person_id||'')}/><span><b>{item.candidates.find(c=>c.current)?.status==='pending'?'Novo cadastro de membro':'Cadastro indicado no pedido'}</b><small>{item.candidates.find(c=>c.current)?.status==='pending'?'Cria o membro com os dados aprovados.':item.candidates.find(c=>c.current)?.name}</small></span></label>}
     {others.map(c=><label key={c.id} className={person===c.id?'on':''}><input type="radio" name="person" checked={person===c.id} onChange={()=>setPerson(c.id)}/><span><b>{c.name}</b><small>{[c.unit,c.journey].filter(Boolean).join(' · ')}</small></span><em>{c.email&&c.cpf?'E-mail e CPF conferem':c.email?'E-mail confere':'CPF confere'}</em>{c.email&&c.cpf&&others.filter(x=>x.email&&x.cpf).length===1&&<em className="suggested">Sugerido</em>}</label>)}
     {!others.length&&<p>Nenhum membro com o mesmo e-mail ou CPF. Ao aprovar, o membro é criado.</p>}
    </fieldset>}
    <div className="pending-fields" role="list">{changes.map(c=><div key={c.field} role="listitem" className={'pending-field '+c.status+(approved.includes(c.field)?' on':'')}>
     <div><span>{label(c.field)}</span>{c.status==='same'?<p><strong>{c.value}</strong></p>:<p><s>{c.before||'Não informado'}</s><b aria-hidden="true">→</b><strong>{c.value||'Remover'}</strong></p>}</div>
     {c.status==='same'?<em>Sem mudança</em>:<label className="pending-switch"><input type="checkbox" checked={approved.includes(c.field)} disabled={busy||!item.can_approve} onChange={()=>toggle(c.field)}/><i aria-hidden="true"/><span>{approved.includes(c.field)?'Aprovar':'Não aprovar'}</span></label>}
    </div>)}</div>
    {item.can_approve?<label className="pending-reason">Motivo da decisão<textarea value={reason} maxLength={1000} disabled={busy} onChange={e=>setReason(e.target.value)} placeholder="Ex.: dados conferidos com o documento na recepção"/></label>:<p className="pending-readonly">Você pode ver este pedido, mas não aprovar.</p>}
    {error&&<p className="pending-error" role="alert">{error}</p>}
   </div>
   {item.can_approve&&<footer><button type="button" className="pending-reject" disabled={busy} onClick={()=>{if(confirm('Recusar todo o pedido? Nenhum dado será alterado.'))void send([])}}>Recusar tudo</button><span>{approved.filter(f=>changes.some(c=>c.field===f&&c.status!=='same')).length} de {changes.filter(c=>c.status!=='same').length} mudanças aprovadas</span><button type="button" className="pending-approve" disabled={busy||!approved.length} onClick={()=>void send(approved)}>{busy?'Confirmando…':'Aprovar perfil'}</button></footer>}
  </section>
 </div>;
}
