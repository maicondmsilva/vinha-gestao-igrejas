"use client";
import {useEffect,useState} from 'react';
import PublishingWorkspace from './PublishingWorkspace';
import PushCampaigns from './PushCampaigns';
import CommunicationMetrics from './CommunicationMetrics';
import type {PublishingKind} from '../shared/publishing';
export default function CommunicationWorkspace({unitId}:{unitId:string}){
 const [section,setSection]=useState(()=>typeof location==='undefined'?'avisos':new URLSearchParams(location.search).get('secao')||'avisos');
 useEffect(()=>{const sync=()=>setSection(new URLSearchParams(location.search).get('secao')||'avisos');addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[]);
 const kinds:Record<string,PublishingKind|'group'>={avisos:'notice',videos:'video',categorias:'category',grupos:'group',banners:'banner',arquivos:'file'};
 if(section==='push')return <PushCampaigns key={unitId} unit={unitId}/>;
 if(section==='metricas')return <CommunicationMetrics key={unitId} unit={unitId}/>;
  return <PublishingWorkspace key={unitId+section} unit={unitId} kind={kinds[section]||'notice'}/>;
}
