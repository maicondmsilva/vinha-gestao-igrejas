'use client';
import {useEffect,useState} from 'react';
import {relationLabels,type Relation} from './lib/family';

type Suggestion={person:string;name:string;relation:Relation};
/** Kids: pais, avós e responsáveis legais ligados à criança em Pessoas, como sugestão de responsável. */
export default function KidsFamilySuggestions({child,onUse}:{child:string;onUse:(name:string,personId:string,relationship:string)=>void}){
 const[items,setItems]=useState<Suggestion[]>([]);
 useEffect(()=>{let live=true;const t=new URLSearchParams(location.search).get('tenant');
  fetch('/api/people/family?suggest=1&child='+encodeURIComponent(child)+(t?'&tenant='+encodeURIComponent(t):''),{cache:'no-store'})
   .then(async r=>(r.ok?await r.json():{items:[]}) as {items?:Suggestion[]}).then(d=>{if(live)setItems(d.items||[])}).catch(()=>undefined);
  return()=>{live=false}},[child]);
 if(!items.length)return null;
 return <div className="kids-card kids-family-suggest"><h3>Da família</h3><p className="kids-muted">Ligados à criança em Pessoas. Escolher só preenche o formulário: a autorização continua dependendo da revisão do Kids.</p>
  {items.map(i=><div key={i.person} className="kids-review-row"><div><b>{i.name}</b><p>{relationLabels[i.relation]}</p></div><button type="button" onClick={()=>onUse(i.name,i.person,relationLabels[i.relation])}>Usar como responsável</button></div>)}</div>;
}
