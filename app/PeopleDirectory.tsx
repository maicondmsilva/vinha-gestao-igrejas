'use client';
import {useMinistryLanguage} from './MinistryLanguage';
import {useEffect,useState} from 'react';
import './people-directory.css';
import type {Person} from './DashboardApp';
import MemberChurchAdmin from './MemberChurchAdmin';
import PendingProfiles from './PendingProfiles';
type Pagination={page:number;limit:number;total:number;pages:number};
export default function PeopleDirectory({unitId,onAdd,onSelect,revision=0}:{unitId:string;onAdd:()=>void;onSelect:(person:Person)=>void;revision?:number}){
 const {t}=useMinistryLanguage();
 const[q,setQ]=useState(''),[status,setStatus]=useState(''),[group,setGroup]=useState(''),[showFilters,setShowFilters]=useState(false),[page,setPage]=useState(1),[people,setPeople]=useState<Person[]>([]),[pagination,setPagination]=useState<Pagination>({page:1,limit:25,total:0,pages:1}),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const tenant=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';
 const [counts,setCounts]=useState<Record<string,number|null>>({all:null,Membro:null,'Em integração':null,Visitante:null});
 useEffect(()=>{setPage(1)},[q,status,group,unitId]);
 useEffect(()=>{
  const controller=new AbortController();const timer=setTimeout(()=>{setLoading(true);setError('');const params=new URLSearchParams({page:String(page),limit:'25'});if(q.trim())params.set('q',q.trim());if(status)params.set('status',status);if(group.trim())params.set('group',group.trim());if(/^[0-9a-f]{8}-/i.test(unitId))params.set('unitId',unitId);if(tenant)params.set('tenant',tenant);
   fetch('/api/people?'+params,{signal:controller.signal}).then(async response=>{const data=await response.json() as {error?:string;people?:Person[];pagination?:Pagination};if(!response.ok)throw new Error(data.error||'Não foi possível carregar os membros.');if(!Array.isArray(data.people)||!data.pagination)throw new Error('Resposta inválida ao carregar membros.');if(controller.signal.aborted)return;setPeople(data.people);setPagination(data.pagination);if(page>data.pagination.pages)setPage(data.pagination.pages)}).catch(reason=>{if(!controller.signal.aborted){setPeople([]);setError(reason instanceof Error?reason.message:'Falha de conexão.')}}).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  },200);return()=>{clearTimeout(timer);controller.abort()};
 },[q,status,group,page,unitId,tenant,revision]);
 useEffect(()=>{const c=new AbortController();const base=new URLSearchParams({page:'1',limit:'1'});if(/^[0-9a-f]{8}-/i.test(unitId))base.set('unitId',unitId);if(tenant)base.set('tenant',tenant);
  Promise.all(['','Membro','Em integração','Visitante'].map(v=>{const p=new URLSearchParams(base);if(v)p.set('status',v);return fetch('/api/people?'+p,{signal:c.signal}).then(r=>r.ok?r.json():null).then((d:{pagination?:Pagination}|null)=>d?.pagination?.total??null).catch(()=>null)}))
   .then(([all,m,i,v])=>{if(!c.signal.aborted)setCounts({all,Membro:m,'Em integração':i,Visitante:v})});return()=>c.abort()},[unitId,tenant,revision]);
 const pages=Array.from({length:Math.min(5,pagination.pages)},(_,index)=>Math.max(1,Math.min(page-2,pagination.pages-4))+index);
 const statusTabs:[string,string,number|null][]=[['','Todos',counts.all],['Membro','Membros',counts.Membro],['Em integração','Em integração',counts['Em integração']],['Visitante','Visitantes',counts.Visitante]];
 const initials=(p:Person)=>p.initials||p.name.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase();
 return <div className="content pd">
  <header className="pd-head"><div><p>Comunidade</p><h1>{t('pessoas')}</h1><small>Membros, pessoas em integração e visitantes da igreja selecionada.</small></div>
   <div className="pd-actions"><a className="pd-secondary" href={`/onboarding/importar-membros${tenant?`?tenant=${encodeURIComponent(tenant)}`:''}`}>Importar planilha</a><button className="pd-primary" type="button" onClick={onAdd}>＋ Nova pessoa</button></div></header>
  <PendingProfiles/><MemberChurchAdmin/>
  <nav className="pd-kpis" aria-label="Filtrar por etapa">{statusTabs.map(([v,label,n])=><button key={label} type="button" aria-pressed={status===v} onClick={()=>setStatus(v)}><small>{label}</small><b>{n===null?'—':n}</b></button>)}</nav>
  <section className="pd-card">
   <div className="pd-tools"><label className="pd-search"><span className="sr-only">Buscar pessoa</span><input maxLength={100} value={q} onChange={event=>setQ(event.target.value)} placeholder="Buscar por nome, e-mail ou telefone"/></label>
    <button type="button" className={'pd-secondary'+(showFilters||group?' on':'')} aria-expanded={showFilters} onClick={()=>setShowFilters(value=>!value)}>Filtros{group?' (1)':''}</button></div>
   {showFilters&&<div className="pd-filters"><label>Grupo ou ministério (nome exato)<input maxLength={160} value={group} onChange={event=>setGroup(event.target.value)}/></label><button type="button" className="pd-link" onClick={()=>{setQ('');setStatus('');setGroup('')}}>Limpar filtros</button></div>}
   {error&&<div className="pd-empty" role="alert">{error}<button type="button" className="pd-link" onClick={()=>setQ(current=>current+' ')}>Tentar novamente</button></div>}
   <div className="pd-table" aria-busy={loading}>
    <div className="pd-row pd-th" aria-hidden="true"><span>Pessoa</span><span>Contato</span><span>Etapa</span><span>Grupo</span><span>Desde</span></div>
    {loading&&!people.length?<div className="pd-empty" role="status">Carregando pessoas…</div>:people.map(person=><button type="button" className="pd-row" key={person.id} onClick={()=>onSelect(person)}>
     <span className="pd-person"><i aria-hidden="true">{initials(person)}</i><span><b>{person.name}</b><small>{person.code?'Nº '+person.code:''}{person.code&&person.email?' · ':''}{person.email}</small></span></span>
     <span className="pd-contact">{person.phone||'—'}</span>
     <span><em className={'pd-pill '+(person.status==='Membro'?'member':person.status==='Visitante'?'visitor':'integration')}>{person.status}</em></span>
     <span className="pd-group">{person.group}</span><span className="pd-since">{person.since}</span></button>)}
    {!loading&&!error&&!people.length&&<div className="pd-empty"><b>Nenhuma pessoa encontrada</b><p>{q||status||group?'Ajuste a busca ou os filtros.':'Cadastre a primeira pessoa ou importe uma planilha.'}</p></div>}
   </div>
   <footer className="pd-foot"><span>{loading?'Carregando…':`${pagination.total} ${pagination.total===1?'pessoa':'pessoas'}${pagination.pages>1?` · página ${page} de ${pagination.pages}`:''}`}</span>
    {pagination.pages>1&&<div><button type="button" aria-label="Página anterior" disabled={loading||page===1} onClick={()=>setPage(value=>Math.max(1,value-1))}>‹</button>{pages.map(number=><button type="button" key={number} disabled={loading} aria-current={page===number?'page':undefined} onClick={()=>setPage(number)}>{number}</button>)}<button type="button" aria-label="Próxima página" disabled={loading||page>=pagination.pages} onClick={()=>setPage(value=>Math.min(pagination.pages,value+1))}>›</button></div>}</footer>
  </section>
 </div>
}
