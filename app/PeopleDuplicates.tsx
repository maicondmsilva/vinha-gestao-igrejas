'use client';
import {useCallback,useEffect,useState} from 'react';
import {reasonLabels} from './lib/people-tools';
import './people-tools.css';

type Card={id:string;name:string;email:string;phone:string;birthDate:string|null;cpf:string;journey:string;status:string;createdAt:string;login:boolean;unit:string|null;cells:number;finance:number};
type Pair={a:Card;b:Card;reasons:string[]};
const br=(d?:string|null)=>d?d.slice(0,10).split('-').reverse().join('/'):'—';

/** Pessoas › Duplicados: pares parecidos, escolha de qual cadastro fica e unificação. */
export default function PeopleDuplicates({unitId,onCount,onChanged}:{unitId:string;onCount?:(n:number)=>void;onChanged?:()=>void}){
 const[pairs,setPairs]=useState<Pair[]|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(''),[notice,setNotice]=useState(''),[rev,setRev]=useState(0);
 const tenant=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';
 useEffect(()=>{if(!/^[0-9a-f-]{36}$/i.test(unitId))return;const c=new AbortController();
  fetch('/api/people/duplicates?'+new URLSearchParams({unit:unitId,...(tenant?{tenant}:{})}),{cache:'no-store',signal:c.signal})
   .then(async r=>{const d=await r.json() as {pairs?:Pair[];error?:string};if(!r.ok)throw Error(d.error||'Não foi possível procurar duplicados.');setError('');setPairs(d.pairs||[]);onCount?.((d.pairs||[]).length)})
   .catch(e=>{if(!c.signal.aborted)setError(e instanceof Error?e.message:'Falha de conexão.')});
  return()=>c.abort()},[unitId,tenant,rev,onCount]);
 const act=useCallback(async(action:'merge'|'dismiss',keep:Card,remove:Card)=>{
  if(action==='merge'&&!confirm(`Unificar os cadastros?\n\nFica: ${keep.name}\nSai: ${remove.name}\n\nCélulas, escalas, lançamentos, família e histórico de "${remove.name}" passam para "${keep.name}". Dados que faltam são completados. Esta ação não pode ser desfeita.`))return;
  setBusy(keep.id+remove.id);setNotice('');
  try{const r=await fetch('/api/people/duplicates'+(tenant?'?tenant='+encodeURIComponent(tenant):''),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({unit:unitId,action,keep:keep.id,remove:remove.id})});
   const d=await r.json() as {error?:string};if(!r.ok)throw Error(d.error||'Não foi possível concluir.');
   setNotice(action==='merge'?`Cadastros unificados. ${keep.name} ficou com o histórico dos dois.`:'Pronto. Este par não aparece mais como duplicado.');setRev(v=>v+1);if(action==='merge')onChanged?.();
  }catch(e){setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy('')}
 },[unitId,tenant,onChanged]);
 const card=(c:Card,other:Card,pairBusy:boolean)=><div className="pdup-card">
  <b>{c.name}</b>
  <dl><dt>E-mail</dt><dd>{c.email||'—'}</dd><dt>Celular</dt><dd>{c.phone||'—'}</dd><dt>Nascimento</dt><dd>{br(c.birthDate)}</dd><dt>CPF</dt><dd>{c.cpf||'—'}</dd>
   <dt>Etapa</dt><dd>{c.journey}</dd><dt>Cadastro</dt><dd>{br(c.createdAt)}{c.unit?' · '+c.unit:''}</dd></dl>
  <p className="pdup-tags">{c.login&&<em>Usa o aplicativo</em>}{c.cells>0&&<em>{c.cells} célula(s)</em>}{c.finance>0&&<em>{c.finance} lançamento(s)</em>}</p>
  <button type="button" className="pd-primary" disabled={pairBusy||(other.login&&c.login)} onClick={()=>void act('merge',c,other)}>Manter este cadastro</button>
 </div>;
 if(error)return <div className="pd-card pdup-empty" role="alert">{error}</div>;
 if(!pairs)return <div className="pd-card pdup-empty" role="status">Procurando cadastros parecidos…</div>;
 return <section className="pdup" aria-label="Cadastros duplicados">
  <p className="pdup-help">Comparamos nome, celular, CPF e data de nascimento. Escolha qual cadastro fica: o outro é removido e tudo o que estava nele passa para o que ficou.</p>
  {notice&&<p className="pdup-notice" role="status">{notice}</p>}
  {!pairs.length?<div className="pd-card pdup-empty"><b>Nenhum possível duplicado</b><p>Os cadastros desta igreja não têm nomes, celulares ou CPFs repetidos.</p></div>:
   <ul className="pdup-list">{pairs.map(p=>{const k=p.a.id+p.b.id,isBusy=busy===k||busy===p.b.id+p.a.id;return <li key={k} className="pd-card">
    <header><span>{p.reasons.map(r=><em key={r}>{reasonLabels[r]||r}</em>)}</span>
     <button type="button" className="pd-link" disabled={isBusy} onClick={()=>void act('dismiss',p.a,p.b)}>São pessoas diferentes</button></header>
    <div className="pdup-pair">{card(p.a,p.b,isBusy)}{card(p.b,p.a,isBusy)}</div>
    {p.a.login&&p.b.login&&<p className="pdup-warn">As duas pessoas usam o aplicativo. Para unificar, retire primeiro o acesso de uma delas em Usuários.</p>}
   </li>})}</ul>}
 </section>;
}
