'use client';
import {useEffect,useState} from 'react';
import {journeys,relationLabels,relations,type Relation} from './lib/family';
import './family-links.css';

type Item={id:string;person:string;name:string;relation:Relation;age:number|null;journey:string|null;unit:string|null;same_household:boolean;marriage_date:string|null;version:number};
type Found={id:string;name:string;status:string};
type Draft={id?:string;version?:number;related?:string;relatedName:string;relation:Relation|'';same_household:boolean;copy_address:boolean;marriage_date:string;quick:boolean;name:string;birth_date:string;journey:string};
const blank:Draft={relatedName:'',relation:'',same_household:false,copy_address:false,marriage_date:'',quick:false,name:'',birth_date:'',journey:'Membro'};
const initials=(n:string)=>n.trim().split(/\s+/).slice(0,2).map(p=>p[0]?.toUpperCase()||'').join('')||'?';

function url(path:string){const t=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';return path+(t?(path.includes('?')?'&':'?')+'tenant='+encodeURIComponent(t):'')}
async function call<T>(path:string,body?:unknown):Promise<T>{
 const r=await fetch(url(path),body?{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}:{cache:'no-store'});
 const d=await r.json().catch(()=>({})) as T&{error?:string};
 if(!r.ok)throw Error(d.error||'Não foi possível concluir.');
 return d;
}

/** Pessoas: família da pessoa (cônjuge, pais, filhos…), com o vínculo inverso mantido pelo banco. */
export default function FamilyLinks({person,editable=false,onOpen}:{person:string;editable?:boolean;onOpen?:(id:string)=>void}){
 const[items,setItems]=useState<Item[]|null>(null),[canEdit,setCanEdit]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false);
 const[draft,setDraft]=useState<Draft|null>(null),[q,setQ]=useState(''),[found,setFound]=useState<Found[]|null>(null),[reload,setReload]=useState(0);
 useEffect(()=>{let live=true;call<{items:Item[];canEdit:boolean}>('/api/people/family?person='+person).then(d=>{if(live){setError('');setItems(d.items);setCanEdit(d.canEdit)}}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}},[person,reload]);
 const edit=editable&&canEdit;
 const set=<K extends keyof Draft>(k:K,v:Draft[K])=>setDraft(d=>d?{...d,[k]:v}:d);

 async function search(){if(q.trim().length<2)return;setBusy(true);try{const d=await call<{people:Found[]}>('/api/people?limit=8&q='+encodeURIComponent(q.trim()));setFound(d.people.filter(p=>p.id!==person&&!items?.some(i=>i.person===p.id)))}catch(e){setError(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}
 async function save(){if(!draft||!draft.relation){setError('Escolha o parentesco.');return}setBusy(true);setError('');
  try{
   const common={relation:draft.relation,same_household:draft.same_household,copy_address:draft.same_household&&draft.copy_address};
   if(draft.quick)await call('/api/people/family',{action:'quick_create',data:{person,name:draft.name,birth_date:draft.birth_date||null,journey:draft.journey,...common}});
   else await call('/api/people/family',{action:'set',data:{...(draft.id?{id:draft.id,version:draft.version}:{}),person,related:draft.related,...common,marriage_date:draft.relation==='conjuge'?draft.marriage_date||null:null}});
   setNotice(draft.id?'Vínculo atualizado.':'Familiar adicionado.');setDraft(null);setFound(null);setQ('');setReload(x=>x+1);
  }catch(e){setError(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}
 async function remove(i:Item){if(!confirm(`Remover ${i.name} da família? Os dois cadastros continuam.`))return;setBusy(true);setError('');
  try{await call('/api/people/family',{action:'remove',data:{id:i.id,version:i.version}});setNotice('Vínculo removido.');setReload(x=>x+1)}catch(e){setError(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}

 return <div className="fl">
  {error&&<p className="fl-error" role="alert">{error}</p>}
  {notice&&<p className="fl-notice" role="status">{notice}</p>}
  {items===null?!error&&<p className="fl-muted">Carregando família…</p>:!items.length&&!draft?<p className="fl-muted">Nenhum familiar ligado{edit?'. Adicione cônjuge, filhos, pais e outros parentes.':'.'}</p>:
   <ul className="fl-list">{items.map(i=><li key={i.id}>
    <i aria-hidden>{initials(i.name)}</i>
    <div><button type="button" className="fl-name" onClick={()=>onOpen?.(i.person)} disabled={!onOpen}>{i.name}</button>
     <small>{relationLabels[i.relation]}{i.age!==null?' · '+i.age+(i.age===1?' ano':' anos'):''}{i.journey?' · '+i.journey:''}{i.unit?' · '+i.unit:''}</small>
     <span className="fl-tags">{i.same_household&&<em>Mora junto</em>}{i.relation==='conjuge'&&i.marriage_date&&<em>Casamento {i.marriage_date.split('-').reverse().join('/')}</em>}</span></div>
    {edit&&<span className="fl-actions"><button type="button" disabled={busy} onClick={()=>{setDraft({...blank,id:i.id,version:i.version,related:i.person,relatedName:i.name,relation:i.relation,same_household:i.same_household,marriage_date:i.marriage_date||''});setNotice('')}}>Editar</button><button type="button" className="danger" disabled={busy} onClick={()=>void remove(i)}>Remover</button></span>}
   </li>)}</ul>}
  {edit&&!draft&&<button type="button" className="fl-add" onClick={()=>{setDraft({...blank});setNotice('');setError('')}}>+ Adicionar familiar</button>}
  {draft&&<div className="fl-form">
   {!draft.id&&!draft.related&&!draft.quick?<>
    <label>Buscar em Pessoas<span className="fl-search"><input value={q} onChange={e=>setQ(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();void search()}}} placeholder="Nome, e-mail ou CPF" maxLength={100}/><button type="button" disabled={busy||q.trim().length<2} onClick={()=>void search()}>Buscar</button></span></label>
    {found&&<ul className="fl-found">{found.map(f=><li key={f.id}><span>{f.name}<small>{f.status}</small></span><button type="button" onClick={()=>setDraft({...draft,related:f.id,relatedName:f.name})}>Escolher</button></li>)}{!found.length&&<li className="fl-muted">Ninguém encontrado.</li>}</ul>}
    <button type="button" className="fl-link" onClick={()=>setDraft({...draft,quick:true,name:q.trim()})}>Cadastrar rápido (ex.: filho pequeno)</button>
   </>:<>
    {draft.quick?<div className="fl-grid">
     <label className="fl-wide">Nome do familiar<input value={draft.name} onChange={e=>set('name',e.target.value)} maxLength={160} required/></label>
     <label>Nascimento<input type="date" value={draft.birth_date} onChange={e=>set('birth_date',e.target.value)}/></label>
     <label>Etapa<select value={draft.journey} onChange={e=>set('journey',e.target.value)}>{journeys.map(j=><option key={j}>{j}</option>)}</select></label>
    </div>:<p className="fl-chosen">Familiar: <b>{draft.relatedName}</b></p>}
    <div className="fl-grid">
     <label>Parentesco ({draft.quick?draft.name||'familiar':draft.relatedName} é…)<select value={draft.relation} onChange={e=>set('relation',e.target.value as Relation)}><option value="">Escolha</option>{relations.map(r=><option key={r} value={r}>{relationLabels[r]}</option>)}</select></label>
     {draft.relation==='conjuge'&&!draft.quick&&<label>Data de casamento<input type="date" value={draft.marriage_date} onChange={e=>set('marriage_date',e.target.value)}/></label>}
     <label className="fl-check"><input type="checkbox" checked={draft.same_household} onChange={e=>set('same_household',e.target.checked)}/>Mora junto</label>
     {draft.same_household&&<label className="fl-check"><input type="checkbox" checked={draft.copy_address} onChange={e=>set('copy_address',e.target.checked)}/>Copiar o endereço desta pessoa</label>}
    </div>
   </>}
   <div className="fl-form-actions"><button type="button" onClick={()=>{setDraft(null);setFound(null);setError('')}}>Cancelar</button>{(draft.id||draft.related||draft.quick)&&<button type="button" className="primary" disabled={busy} onClick={()=>void save()}>{busy?'Salvando…':'Salvar vínculo'}</button>}</div>
  </div>}
 </div>;
}
