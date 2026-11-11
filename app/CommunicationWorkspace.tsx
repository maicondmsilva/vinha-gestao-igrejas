"use client";
import {useEffect,useState} from 'react';
import PublishingWorkspace from './PublishingWorkspace';
import PushCampaigns from './PushCampaigns';
import CommunicationMetrics from './CommunicationMetrics';
import CommunityChat from './CommunityChat';
import type {PublishingKind} from '../shared/publishing';
import {currentDashboardQuery} from '../shared/dashboard-route';
export default function CommunicationWorkspace({unitId}:{unitId:string}){
 const [section,setSection]=useState(()=>typeof location==='undefined'?'avisos':currentDashboardQuery().get('secao')||'avisos');
 useEffect(()=>{const sync=()=>setSection(currentDashboardQuery().get('secao')||'avisos');addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[]);
 const kinds:Record<string,PublishingKind|'group'>={avisos:'notice',videos:'video',categorias:'category',grupos:'group',banners:'banner',arquivos:'file'};
 if(section==='push')return <PushCampaigns key={unitId} unit={unitId}/>;
 if(section==='metricas')return <CommunicationMetrics key={unitId} unit={unitId}/>;
 if(section==='chat')return <CommunityChat key={unitId} unit={unitId}/>;
  return <PublishingWorkspace key={unitId+section} unit={unitId} kind={kinds[section]||'notice'}/>;
}
