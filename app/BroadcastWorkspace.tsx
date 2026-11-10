'use client';
import {useEffect,useState} from 'react';
import PublishingWorkspace from './PublishingWorkspace';
export default function BroadcastWorkspace({unit}:{unit:string}){const [section,setSection]=useState(()=>typeof location==='undefined'?'transmissoes':new URLSearchParams(location.search).get('secao')||'transmissoes');useEffect(()=>{const sync=()=>setSection(new URLSearchParams(location.search).get('secao')||'transmissoes');addEventListener('popstate',sync);return()=>removeEventListener('popstate',sync)},[]);return <PublishingWorkspace key={unit+section} unit={unit} kind={section==='canais'?'channel':'live'}/>}
