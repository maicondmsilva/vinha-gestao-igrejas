'use client';
import {useEffect,useState} from 'react';
import {eventDate,timelineGroups,timelineIcons} from './lib/people-tools';
import './people-tools.css';

type Event={at:string;kind:string;title:string;detail:string|null};

/** Ficha da pessoa › Histórico: cadastro, visitas, decisão, batismo, células, transferências, app e escalas. */
export default function PersonTimeline({person}:{person:string}){
 const[events,setEvents]=useState<Event[]|null>(null),[error,setError]=useState(''),[all,setAll]=useState(false);
 useEffect(()=>{const c=new AbortController();const t=new URLSearchParams(location.search).get('tenant');
  fetch('/api/people/timeline?'+new URLSearchParams({id:person,...(t?{tenant:t}:{})}),{cache:'no-store',signal:c.signal})
   .then(async r=>{const d=await r.json() as {events?:Event[];error?:string};if(!r.ok)throw Error(d.error||'Não foi possível carregar o histórico.');setEvents(d.events||[])})
   .catch(e=>{if(!c.signal.aborted)setError(e instanceof Error?e.message:'Falha de conexão.')});
  return()=>c.abort()},[person]);
 if(error)return <p className="pt-empty" role="alert">{error}</p>;
 if(!events)return <p className="pt-empty" role="status">Carregando histórico…</p>;
 if(!events.length)return <p className="pt-empty">Nenhum registro ainda.</p>;
 const shown=all?events:events.slice(0,12);
 return <div className="pt">
  {timelineGroups(shown).map(g=><div key={g.label} className="pt-month"><h4>{g.label}</h4><ol>{g.items.map((e,i)=><li key={i} className={'pt-'+e.kind}>
   <i aria-hidden="true">{timelineIcons[e.kind]||'•'}</i><div><b>{e.title}</b>{e.detail&&<span>{e.detail}</span>}<small>{eventDate(e.at)}</small></div></li>)}</ol></div>)}
  {events.length>12&&<button type="button" className="pt-more" onClick={()=>setAll(v=>!v)}>{all?'Mostrar menos':`Ver todo o histórico (${events.length})`}</button>}
 </div>;
}
