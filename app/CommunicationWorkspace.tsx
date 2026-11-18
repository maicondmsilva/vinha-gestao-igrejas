"use client";
import {lazy,Suspense,useEffect,useState,type ReactNode} from 'react';
import PublishingWorkspace from './PublishingWorkspace';
import PushCampaigns from './PushCampaigns';
import CommunicationMetrics from './CommunicationMetrics';
import CommunityChat from './CommunityChat';
// Conteúdo do app que antes ficava em Configurações › Serviços e segurança.
const MinistryMediaAdmin=lazy(()=>import('./MinistryMediaAdmin'));
const MemberCommunityAdmin=lazy(()=>import('./MemberCommunityAdmin'));
const MemberLearningAdmin=lazy(()=>import('./MemberLearningAdmin'));
import type {PublishingKind} from '../shared/publishing';
import {currentDashboardQuery} from '../shared/dashboard-route';
export default function CommunicationWorkspace({unitId}:{unitId:string}){
 const [section,setSection]=useState(()=>typeof location==='undefined'?'avisos':currentDashboardQuery().get('secao')||'avisos');
 useEffect(()=>{const sync=()=>setSection(currentDashboardQuery().get('secao')||'avisos');addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[]);
 const kinds:Record<string,PublishingKind|'group'>={avisos:'notice',videos:'video',categorias:'category',grupos:'group',banners:'banner',arquivos:'file',paginas:'page',series:'series'};
 if(section==='push')return <PushCampaigns key={unitId} unit={unitId}/>;
 if(section==='metricas')return <CommunicationMetrics key={unitId} unit={unitId}/>;
 if(section==='chat')return <CommunityChat key={unitId} unit={unitId}/>;
 const app=(node:ReactNode,title:string,text:string)=><section className="content"><header className="page-head"><div style={{display:"block"}}><p className="section-over">COMUNICAÇÃO</p><h1>{title}</h1><p>{text}</p></div></header><Suspense fallback={<p role="status">Carregando…</p>}>{node}</Suspense></section>;
 if(section==='abertura')return app(<MinistryMediaAdmin key={unitId} unitId={unitId} mode="all"/>,'Mídia do app','Vídeos e transmissões da biblioteca de mídia. A abertura do app é definida pela Vinha.');
 if(section==='comunidade')return app(<MemberCommunityAdmin key={unitId}/>,'Comunidade do app','Ministérios e departamentos que aparecem no app e os pedidos dos membros.');
 if(section==='jornadas')return app(<MemberLearningAdmin key={unitId}/>,'Jornadas e leitura','Planos de leitura e jornadas de estudo publicados no app.');
  return <PublishingWorkspace key={unitId+section} unit={unitId} kind={kinds[section]||'notice'}/>;
}
