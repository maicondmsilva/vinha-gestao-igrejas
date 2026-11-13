'use client';
import {useEffect,useState} from 'react';
import {followupLabels,followupOrder} from './lib/people-tools';
import {whatsappLink} from './lib/birthdays';
import './people-tools.css';

type Item={person:string;name:string;phone:string;convertedAt:string;days:number;status:string;followup:string|null;followupName:string|null;note:string;cells:string;journey:string};
type Data={today:string;counts:Record<string,number>;items:Item[];church?:string};
type Found={id:string;name:string;phone?:string};
const br=(d:string)=>d?d.split('-').reverse().join('/'):'';
const tenantQuery=()=>{const t=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant');return t?{tenant:t}:{} as Record<string,string>};

/** Busca rápida de uma pessoa da igreja (para registrar decisão ou escolher o responsável). */
export function PersonPicker({unitId,label,onPick,exclude}:{unitId:string;label:string;onPick:(p:Found)=>void;exclude?:string}){
 const[q,setQ]=useState(''),[list,setList]=useState<Found[]>([]);
 useEffect(()=>{if(q.trim().length<2){Promise.resolve().then(()=>setList([]));return}const c=new AbortController();const t=setTimeout(()=>{
  fetch('/api/people?'+new URLSearchParams({q:q.trim(),limit:'6',unitId,...tenantQuery()}),{cache:'no-store',signal:c.signal}).then(r=>r.ok?r.json():null)
   .then((d:{people?:Found[]}|null)=>setList((d?.people||[]).filter(p=>p.id!==exclude))).catch(()=>undefined)},250);return()=>{clearTimeout(t);c.abort()}},[q,unitId,exclude]);
 return <div className="pcv-pick"><label>{label}<input value={q} maxLength={100} onChange={e=>setQ(e.target.value)} placeholder="Digite ao menos 2 letras do nome"/></label>
  {list.length>0&&<ul>{list.map(p=><li key={p.id}><button type="button" onClick={()=>{onPick(p);setQ('');setList([])}}>{p.name}{p.phone?<small> · {p.phone}</small>:null}</button></li>)}</ul>}</div>;
}

/** Pessoas › Novos convertidos: quem decidiu seguir Jesus, quem acompanha e em que etapa está. */
export default function PeopleConverts({unitId,onOpen}:{unitId:string;onOpen:(id:string)=>void}){
 const[days,setDays]=useState('90'),[filter,setFilter]=useState(''),[data,setData]=useState<Data|null>(null),[error,setError]=useState(''),[rev,setRev]=useState(0),
  [editing,setEditing]=useState(''),[adding,setAdding]=useState(false),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false);
 useEffect(()=>{if(!/^[0-9a-f-]{36}$/i.test(unitId))return;const c=new AbortController();
  fetch('/api/people/converts?'+new URLSearchParams({unit:unitId,days,...tenantQuery()}),{cache:'no-store',signal:c.signal})
   .then(async r=>{const d=await r.json() as Data&{error?:string};if(!r.ok)throw Error(d.error||'Não foi possível carregar.');setError('');setData(d)})
   .catch(e=>{if(!c.signal.aborted)setError(e instanceof Error?e.message:'Falha de conexão.')});
  return()=>c.abort()},[unitId,days,rev]);
 async function save(body:Record<string,unknown>,msg:string){
  setBusy(true);setNotice('');
  try{const r=await fetch('/api/people/converts?'+new URLSearchParams(tenantQuery()),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({unit:unitId,...body})});
   const d=await r.json() as {error?:string};if(!r.ok)throw Error(d.error||'Não foi possível salvar.');setNotice(msg);setEditing('');setAdding(false);setRev(v=>v+1);
  }catch(e){setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}
 }
 const items=(data?.items||[]).filter(i=>!filter||(filter==='late'?i.status==='pending'&&i.days>7:i.status===filter));
 const welcome=(i:Item)=>`Olá, ${i.name.split(/\s+/)[0]}! Que alegria a sua decisão por Jesus. Aqui é da ${data?.church||'nossa igreja'}: queremos caminhar com você. Podemos conversar?`;
 return <section className="pcv" aria-label="Novos convertidos">
  <div className="pcv-head"><p>Decisões dos últimos <select aria-label="Período" value={days} onChange={e=>setDays(e.target.value)}><option value="30">30 dias</option><option value="90">90 dias</option><option value="180">6 meses</option><option value="365">12 meses</option></select> e quem ainda espera contato.</p>
   <button type="button" className="pd-primary" onClick={()=>{setAdding(v=>!v);setNotice('')}}>{adding?'Cancelar':'＋ Registrar decisão'}</button></div>
  {adding&&<AddConvert unitId={unitId} today={data?.today||''} busy={busy} save={save}/>}
  {notice&&<p className="pdup-notice" role="status">{notice}</p>}
  {error&&<div className="pd-card pdup-empty" role="alert">{error}</div>}
  {data&&<nav className="pcv-kpis" aria-label="Filtrar acompanhamento">
   {[['','Todos',data.counts.total],['late','Mais de 7 dias sem contato',data.counts.late],...followupOrder.map(s=>[s,followupLabels[s],data.counts[s]] as const)].map(([v,l,n])=>
    <button key={v||'all'} type="button" aria-pressed={filter===v} className={v==='late'&&n?'late':undefined} onClick={()=>setFilter(v as string)}><small>{l}</small><b>{n??0}</b></button>)}</nav>}
  {data&&!items.length&&<div className="pd-card pdup-empty"><b>Ninguém nesta lista</b><p>{filter?'Escolha outro filtro.':'Registre aqui as decisões feitas nos cultos, células e eventos para acompanhar cada pessoa.'}</p></div>}
  {items.length>0&&<ul className="pcv-list">{items.map(i=>{const link=whatsappLink(i.phone,welcome(i));return <li key={i.person} className="pd-card">
   <div className="pcv-row">
    <span className={'pcv-status s-'+i.status}>{followupLabels[i.status]||i.status}</span>
    <div className="pcv-main"><button type="button" className="pb-name" onClick={()=>onOpen(i.person)}>{i.name}</button>
     <small>Decisão em {br(i.convertedAt)} · {i.days===0?'hoje':i.days===1?'há 1 dia':`há ${i.days} dias`}{i.cells?' · Célula: '+i.cells:''}</small>
     <small>{i.followupName?'Acompanha: '+i.followupName:'Sem responsável'}{i.note?' · '+i.note:''}</small></div>
    <div className="pcv-actions">{link&&<a className="pb-msg" href={link} target="_blank" rel="noopener noreferrer" aria-label={'Mandar mensagem para '+i.name}>Mensagem</a>}
     <button type="button" className="pd-secondary" aria-expanded={editing===i.person} onClick={()=>setEditing(v=>v===i.person?'':i.person)}>Acompanhar</button></div>
   </div>
   {editing===i.person&&<EditConvert unitId={unitId} item={i} today={data?.today||''} busy={busy} save={save}/>}
  </li>})}</ul>}
 </section>;
}

function AddConvert({unitId,today,busy,save}:{unitId:string;today:string;busy:boolean;save:(b:Record<string,unknown>,m:string)=>Promise<void>}){
 const[person,setPerson]=useState<Found|null>(null),[date,setDate]=useState(today);
 return <div className="pd-card pcv-form">
  {person?<p className="pcv-chosen"><b>{person.name}</b><button type="button" className="pd-link" onClick={()=>setPerson(null)}>Trocar</button></p>:<PersonPicker unitId={unitId} label="Pessoa" onPick={setPerson}/>}
  <label>Data da decisão<input type="date" value={date||today} max={today} onChange={e=>setDate(e.target.value)}/></label>
  <p className="pcv-hint">A pessoa precisa estar cadastrada. Se for a primeira visita, cadastre em “Nova pessoa” e volte aqui.</p>
  <button type="button" className="pd-primary" disabled={!person||busy} onClick={()=>person&&void save({person:person.id,convertedAt:date||today,status:'pending'},`Decisão de ${person.name} registrada. Agora é só escolher quem vai acompanhar.`)}>Registrar</button>
 </div>;
}

function EditConvert({unitId,item,today,busy,save}:{unitId:string;item:Item;today:string;busy:boolean;save:(b:Record<string,unknown>,m:string)=>Promise<void>}){
 const[status,setStatus]=useState(item.status),[date,setDate]=useState(item.convertedAt),[note,setNote]=useState(item.note),[follow,setFollow]=useState<Found|null>(item.followup?{id:item.followup,name:item.followupName||''}:null);
 return <div className="pcv-form inline">
  <label>Etapa do acompanhamento<select value={status} onChange={e=>setStatus(e.target.value)}>{followupOrder.map(s=><option key={s} value={s}>{followupLabels[s]}</option>)}</select></label>
  <label>Data da decisão<input type="date" value={date} max={today} onChange={e=>setDate(e.target.value)}/></label>
  {follow?<p className="pcv-chosen"><span>Responsável: <b>{follow.name}</b></span><button type="button" className="pd-link" onClick={()=>setFollow(null)}>Trocar</button></p>:<PersonPicker unitId={unitId} label="Quem vai acompanhar" exclude={item.person} onPick={setFollow}/>}
  <label className="wide-note">Observação<textarea maxLength={500} rows={2} value={note} onChange={e=>setNote(e.target.value)} placeholder="Ex.: ligar no sábado; prefere célula perto de casa"/></label>
  <div className="pcv-form-actions">
   <button type="button" className="pd-primary" disabled={busy||!date} onClick={()=>void save({person:item.person,status,convertedAt:date,followup:follow?.id||'',note},'Acompanhamento atualizado.')}>Salvar</button>
   <button type="button" className="pd-link danger" disabled={busy} onClick={()=>{if(confirm(`Tirar ${item.name} da lista de novos convertidos? A data da decisão será apagada.`))void save({person:item.person,convertedAt:''},'Pessoa retirada da lista.')}}>Tirar da lista</button>
  </div>
 </div>;
}
