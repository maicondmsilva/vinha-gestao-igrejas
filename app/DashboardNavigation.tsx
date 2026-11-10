'use client';
import {useEffect,useState,type MouseEvent} from 'react';
import {useMinistryLanguage} from './MinistryLanguage';
import {cellSections,type LanguageKey} from './lib/ministry-language';
import {financeSections,financeLabel} from './lib/finance-f1';
import {communicationPages,kidsPages,programmingPages,dashboardGroup,dashboardHref} from '../shared/dashboard-menu';
import {dashboardQuery} from '../shared/dashboard-route';
type Entry={label:string;page:string;section?:string};
export default function DashboardNavigation({active,navigate}:{active:string;navigate:(label:string,section?:string)=>void}){
 const {t}=useMinistryLanguage(),[expanded,setExpanded]=useState(()=>dashboardGroup(active)),[search,setSearch]=useState(()=>typeof location==='undefined'?'':location.search);
 useEffect(()=>{setExpanded(dashboardGroup(active))},[active]);
 useEffect(()=>{const sync=()=>setSearch(location.search);sync();addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[active]);
 const q=dashboardQuery(typeof location==='undefined'?'/painel':location.pathname,search),current=q.get('secao')||'',page=q.get('pagina')||'inicio';
 const entries:({label:string;icon:string;key:LanguageKey;children?:Entry[]})[]=[
  {label:'Visão geral',icon:'⌂',key:'inicio'},{label:'Pessoas',icon:'♙',key:'pessoas'},{label:'Famílias e termos',icon:'⌁',key:'familias'},
  {label:'Aplicativo do membro',icon:'▣',key:'aplicativo'},{label:'Área Kids',icon:'★',key:'kids',children:kidsPages.map(([section,label])=>({label,page:'kids',section}))},
  {label:'Programação',icon:'▦',key:'eventos',children:[...programmingPages.map(([section,label])=>({label,page:'eventos',section})),{label:'Ao vivo · Canais',page:'transmissoes',section:'canais'},{label:'Ao vivo · Transmissões',page:'transmissoes',section:'transmissoes'}]},
  {label:'Células',icon:'⌾',key:'celulas',children:cellSections.map(section=>({label:t(('celulas.'+section) as LanguageKey),page:'celulas',section}))},
  {label:'Escalas',icon:'✓',key:'escalas',children:[['geral','Visão geral'],['calendario','Calendário e escalas'],['equipes','Equipes e funções'],['pendencias','Pendências e trocas'],['relatorios','Relatórios']].map(([section,label])=>({label,page:'escalas',section}))},{label:'Louvor',icon:'♫',key:'louvor'},
  {label:'Comunicação',icon:'◌',key:'comunicacao',children:communicationPages.map(([section,label])=>({label,page:'comunicacao',section}))},
  {label:'Financeiro',icon:'R$',key:'financeiro',children:financeSections.map(([section])=>({label:financeLabel(section),page:'financeiro',section}))},
  {label:'Relatórios',icon:'▤',key:'relatorios'},
  {label:'Configurações',icon:'⚙',key:'configuracoes',children:[['identidade','Identidade e cadastro'],['igrejas','Igrejas e unidades'],['usuarios','Usuários e permissões'],['servicos','Serviços e segurança']].map(([section,label])=>({label,page:'configuracoes',section}))}
 ];
 const labels:Record<string,string>={inicio:'Visão geral',pessoas:'Pessoas',familias:'Famílias e termos',aplicativo:'Aplicativo do membro',kids:'Área Kids',eventos:'Cultos e eventos',transmissoes:'Transmissões',celulas:'Células',escalas:'Escalas',louvor:'Louvor',comunicacao:'Comunicação',financeiro:'Financeiro',relatorios:'Relatórios',configuracoes:'Configurações'};
 const chosen=(e:Entry)=>page===e.page&&(current===e.section||!current&&e.section===({escalas:'geral',eventos:'proximos',kids:'overview',financeiro:'geral',celulas:'geral',comunicacao:'avisos',transmissoes:'transmissoes',configuracoes:'identidade'} as Record<string,string>)[e.page]);
 function follow(e:MouseEvent<HTMLAnchorElement>,entry:Entry){if(e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;e.preventDefault();navigate(labels[entry.page],entry.section)}
 return <nav aria-label="Módulos da Vinha">{entries.map(entry=>{const group=entry.label,open=expanded===group,isActive=dashboardGroup(active)===group;return <div key={group}><button type="button" className={isActive?'active':''} aria-expanded={entry.children?open:undefined} aria-controls={entry.children?'nav-'+entry.key:undefined} onClick={()=>{if(entry.children){setExpanded(open&&isActive?'':group);if(!isActive){const first=entry.children[0];navigate(labels[first.page],first.section)}}else{setExpanded('');navigate(group)}}}><span aria-hidden="true">{entry.icon}</span>{group==='Programação'?group:t(entry.key)}{entry.children&&<span className="nav-expander" aria-hidden="true">{open?'▾':'▸'}</span>}</button>{entry.children&&open&&<div id={'nav-'+entry.key} className="program-subnav">{entry.children.map(child=><a key={child.page+child.section} href={dashboardHref(search,child.page,child.section)} onClick={e=>follow(e,child)} aria-current={chosen(child)?'page':undefined}>{child.label}</a>)}</div>}</div>})}</nav>;
}
