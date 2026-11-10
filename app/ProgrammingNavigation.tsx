'use client';
import {useEffect,useState} from 'react';
import {programmingHref,programmingSection} from '../shared/programming';
import {dashboardQuery,dashboardUrl} from '../shared/dashboard-route';
export default function ProgrammingNavigation({active}:{active:string}){
 const [open,setOpen]=useState(active==='Cultos e eventos'||active==='Transmissões'),[search,setSearch]=useState(()=>typeof location==='undefined'?'':location.search);
 useEffect(()=>{const sync=()=>setSearch(location.search);sync();addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[active]);
 useEffect(()=>{if(active==='Cultos e eventos'||active==='Transmissões')setOpen(true)},[active]);
 const section=programmingSection(dashboardQuery(typeof location==='undefined'?'/painel':location.pathname,search).get('secao')),live=new URLSearchParams(search);live.set('pagina','transmissoes');live.delete('secao');
 return <div className="program-nav-group"><button type="button" className={active==='Cultos e eventos'||active==='Transmissões'?'active':''} aria-expanded={open} aria-controls="programming-subnav" onClick={()=>setOpen(v=>!v)}><span aria-hidden="true">▦</span> Programação <span className="nav-expander">{open?'▾':'▸'}</span></button>{open&&<div id="programming-subnav" className="program-subnav"><a href={programmingHref('agenda',search)} aria-current={active==='Cultos e eventos'&&section==='agenda'?'page':undefined}>Agenda da igreja</a><p>Eventos</p>{([['proximos','Próximos'],['encerrados','Encerrados'],['todos','Todos e rascunhos']] as const).map(([id,title])=><a key={id} className="program-nav-child" href={programmingHref(id,search)} aria-current={active==='Cultos e eventos'&&section===id?'page':undefined}>{title}</a>)}<a href={programmingHref('categorias',search)} aria-current={active==='Cultos e eventos'&&section==='categorias'?'page':undefined}>Categorias</a><p>Ao vivo</p><a href={'/painel?'+live} aria-current={active==='Transmissões'?'page':undefined}>Transmissões</a></div>}</div>;
}

export function CommunicationNavigation({active,label}:{active:string;label:string}){
 const [open,setOpen]=useState(active==='Comunicação'),[search,setSearch]=useState(()=>typeof location==='undefined'?'':location.search);
 useEffect(()=>{const sync=()=>setSearch(location.search);sync();addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[active]);
 useEffect(()=>{if(active==='Comunicação')setOpen(true)},[active]);
 const section=dashboardQuery(typeof location==='undefined'?'/painel':location.pathname,search).get('secao')||'avisos';
 const href=(s:string)=>dashboardUrl('comunicacao',s,search);
 return <div><button type="button" className={active==='Comunicação'?'active':''} aria-expanded={open} aria-controls="communication-subnav" onClick={()=>setOpen(v=>!v)}><span aria-hidden="true">◌</span>{label}<span className="nav-expander">{open?'▾':'▸'}</span></button>{open&&<div className="program-subnav" id="communication-subnav"><a href={href('avisos')} aria-current={active==='Comunicação'&&section!=='videos'?'page':undefined}>Avisos da igreja</a><a href={href('videos')} aria-current={active==='Comunicação'&&section==='videos'?'page':undefined}>Vídeos e pregações</a></div>}</div>;
}
