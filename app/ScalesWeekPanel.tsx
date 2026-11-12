'use client';
import './scales-week.css';
import {useEffect,useState} from 'react';
import {formatInZone,panelTimezone,toLocalDay} from '../shared/timezone';

type Service={id:string;title:string;starts_at:string;arrival_at:string;location:string;status:'draft'|'published'|'closed'|'cancelled';assigned:number;vacancies:number};
type Pending={id:string;service_id:string;title:string;name:string;team:string;role:string;deadline:string;replacements:number};
const statusLabel:Record<Service['status'],string>={draft:'Rascunho',published:'Publicada',closed:'Encerrada',cancelled:'Cancelada'};
function url(path:string,params:Record<string,string>){const p=new URLSearchParams(params);const t=new URLSearchParams(location.search).get('tenant');if(t)p.set('tenant',t);return path+'?'+p}
async function get<T>(path:string,params:Record<string,string>,signal:AbortSignal){const r=await fetch(url(path,params),{signal,cache:'no-store'});const d=await r.json().catch(()=>({})) as T&{error?:string};if(!r.ok)throw Error(d.error||'Não foi possível consultar.');return d}

/** Escalas › Visão geral: próximos 14 dias, vagas abertas, rascunhos e pendências. */
export default function ScalesWeekPanel({unitId,openService,newScale,canPlan}:{unitId:string;openService:(id:string)=>void;newScale:()=>void;canPlan:boolean}){
 const [now]=useState(()=>Date.now()),[items,setItems]=useState<Service[]|null>(null),[pending,setPending]=useState<{items:Pending[];total:number}|null>(null),[error,setError]=useState(''),[rev,setRev]=useState(0);
 const zone=panelTimezone();
 useEffect(()=>{const c=new AbortController();const today=toLocalDay(new Date(),zone),end=toLocalDay(new Date(Date.now()+13*864e5),zone);
  get<{items:Service[]}>('/api/scales-planning',{unit:unitId,action:'list',from:today,to:end,team:'',status:'all',search:'',page:'1'},c.signal).then(d=>{setItems(d.items.filter(s=>s.status!=='cancelled'));setError('')}).catch(e=>{if(!c.signal.aborted)setError(e.message)});
  get<{items:Pending[];total:number}>('/api/scales-operations',{unit:unitId,action:'pending',page:'1'},c.signal).then(setPending).catch(()=>{if(!c.signal.aborted)setPending({items:[],total:0})});
  return()=>c.abort()},[unitId,zone,rev]);
 if(error)return <p role="alert" className="sw-error">{error} <button type="button" onClick={()=>setRev(n=>n+1)}>Tentar novamente</button></p>;
 if(!items)return <p className="sw-muted" role="status">Montando o painel…</p>;
 const open=items.reduce((n,s)=>n+Math.max(0,s.vacancies-s.assigned),0),drafts=items.filter(s=>s.status==='draft').length,week=items.filter(s=>new Date(s.starts_at).getTime()<now+7*864e5);
 const full=items.filter(s=>s.vacancies>0&&s.assigned>=s.vacancies).length;
 return <div className="sw">
  <div className="sw-kpis">
   <article><small>Próximos 7 dias</small><b>{week.length}</b><span>{week.length===1?'escala':'escalas'}</span></article>
   <article className={open?'warn':''}><small>Vagas abertas (14 dias)</small><b>{open}</b><span>{open?'precisam de voluntários':'tudo preenchido'}</span></article>
   <article className={drafts?'warn':''}><small>Rascunhos</small><b>{drafts}</b><span>{drafts?'ainda não avisados à equipe':'nada para publicar'}</span></article>
   <article className={pending?.total?'alert':''}><small>Pendências</small><b>{pending?.total??'—'}</b><span>respostas e trocas aguardando</span></article>
  </div>
  <div className="sw-grid">
   <section className="sw-services" aria-labelledby="sw-next"><header><h3 id="sw-next">Próximas escalas</h3>{canPlan&&<button type="button" className="sw-primary" onClick={newScale}>＋ Nova escala</button>}</header>
    {!items.length?<div className="sw-empty"><b>Nenhuma escala nos próximos 14 dias</b><p>{canPlan?'Crie a escala do próximo culto ou repita uma escala existente.':'Quando a equipe publicar as escalas, elas aparecem aqui.'}</p></div>
     :<div className="sw-cards">{items.map(s=>{const pct=s.vacancies?Math.round(s.assigned/s.vacancies*100):100,missing=Math.max(0,s.vacancies-s.assigned);
      return <button key={s.id} type="button" className={'sw-card '+s.status} onClick={()=>openService(s.id)}>
       <span className="sw-day"><b>{formatInZone(s.starts_at,zone,{day:'2-digit'})}</b><small>{formatInZone(s.starts_at,zone,{month:'short'}).replace('.','')}</small></span>
       <span className="sw-info"><b>{s.title}</b><small>{formatInZone(s.starts_at,zone,{weekday:'long'})} · {formatInZone(s.starts_at,zone,{hour:'2-digit',minute:'2-digit'})}{s.location?` · ${s.location}`:''}</small>
        <span className="sw-bar" role="img" aria-label={`${s.assigned} de ${s.vacancies} vagas preenchidas`}><i style={{width:pct+'%'}} className={missing?'':'done'}/></span>
        <span className="sw-foot"><em className={'sw-chip '+s.status}>{statusLabel[s.status]}</em><small>{s.vacancies?`${s.assigned} de ${s.vacancies} vagas`:'sem vagas definidas'}{missing?` · faltam ${missing}`:''}</small></span></span>
      </button>})}</div>}
    {full>0&&<p className="sw-muted">{full} de {items.length} escalas já estão completas.</p>}
   </section>
   <section className="sw-pending" aria-labelledby="sw-pend"><header><h3 id="sw-pend">Aguardando resposta</h3></header>
    {!pending?<p className="sw-muted">Consultando…</p>:!pending.items.length?<p className="sw-muted">Ninguém pendente. Todos responderam às escalas.</p>
     :<ul>{pending.items.slice(0,6).map(p=><li key={p.id}><button type="button" onClick={()=>openService(p.service_id)}><b>{p.name}</b><small>{p.title} · {p.team} · {p.role}</small><em className={p.replacements?'swap':'wait'}>{p.replacements?'Pediu troca':'Sem resposta'}</em></button></li>)}</ul>}
    {pending&&pending.total>6&&<p className="sw-muted">E mais {pending.total-6} em Pendências e trocas.</p>}
   </section>
  </div>
 </div>;
}
