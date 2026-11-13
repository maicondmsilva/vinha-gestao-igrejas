'use client';
import {useEffect,useState} from 'react';
import {birthdayMessage,dayLabel,ranges,whatsappLink,type BirthdayItem} from './lib/birthdays';

type Data={today:string;counts:{today:number;week:number;month:number};items:BirthdayItem[];church:string};

/** Pessoas › Aniversariantes do dia, da semana e do mês (nascimento e casamento), com atalho de mensagem. */
export default function PeopleBirthdays({unitId,onOpen}:{unitId:string;onOpen:(personId:string)=>void}){
 const[range,setRange]=useState<string>('today'),[data,setData]=useState<Data|null>(null),[open,setOpen]=useState(true),[denied,setDenied]=useState(false);
 useEffect(()=>{if(!/^[0-9a-f-]{36}$/i.test(unitId))return;const c=new AbortController();const t=new URLSearchParams(location.search).get('tenant');
  fetch('/api/people/birthdays?'+new URLSearchParams({unit:unitId,range,...(t?{tenant:t}:{})}),{cache:'no-store',signal:c.signal})
   .then(async r=>{if(r.status===403){setDenied(true);return}if(!r.ok)return;setDenied(false);setData(await r.json() as Data)}).catch(()=>undefined);
  return()=>c.abort()},[unitId,range]);
 if(denied||!data)return null;
 const n=data.counts[range as keyof Data['counts']]??0;
 return <section className="pb" aria-labelledby="pb-title">
  <header><button type="button" className="pb-toggle" aria-expanded={open} onClick={()=>setOpen(v=>!v)}><h2 id="pb-title">Aniversariantes</h2><span>{data.counts.today?`${data.counts.today} hoje`:'Ninguém hoje'} · {data.counts.week} nos próximos 7 dias</span></button>
   {open&&<div className="pb-seg" role="group" aria-label="Período">{ranges.map(([v,l])=><button key={v} type="button" aria-pressed={range===v} onClick={()=>setRange(v)}>{l} <b>{data.counts[v]}</b></button>)}</div>}</header>
  {open&&(!n?<p className="pb-empty">Nenhum aniversário neste período.</p>:<ul className="pb-list">{data.items.map(i=>{const link=whatsappLink(i.phone,birthdayMessage(i,data.church));return <li key={i.person+i.kind}>
   <span className={'pb-day'+(i.date===data.today?' now':'')}>{dayLabel(i.date,data.today)}</span>
   <div><button type="button" className="pb-name" onClick={()=>onOpen(i.person)}>{i.name}</button><small>{i.kind==='wedding'?`💍 ${i.years} anos de casamento`:`🎂 ${i.years} anos`}{i.journey?' · '+i.journey:''}</small></div>
   {link?<a className="pb-msg" href={link} target="_blank" rel="noopener noreferrer" aria-label={'Mandar mensagem para '+i.name}>Mensagem</a>:<span className="pb-nophone">Sem celular</span>}
  </li>})}</ul>)}
 </section>;
}
