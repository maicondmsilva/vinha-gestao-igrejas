'use client';
import {useEffect,useState} from 'react';
import EventInformationPanel from '../../../EventInformationPanel';
import {programmingRead,type EventDetailData} from '../../../ProgrammingTools';
import '../../../programming.css';
import '../../../event-workspace.css';
export default function EventTeamPage(){
 const [data,setData]=useState<(EventDetailData&{canPublish:boolean})|null>(null),[error,setError]=useState(''),[revision,setRevision]=useState(0),[unit,setUnit]=useState('');
 useEffect(()=>{const c=new AbortController(),q=new URLSearchParams(location.search),u=q.get('unit')||'',id=location.pathname.split('/').at(-2)?.replace(/^e-/,'')||'';setUnit(u);setError('');programmingRead<EventDetailData&{canPublish:boolean}>('/api/event-information?'+new URLSearchParams({unit:u,event:id,action:'read'}),c.signal).then(setData).catch(e=>{if(!c.signal.aborted)setError(e.message)});return()=>c.abort()},[revision]);
 return <main className="ev-workspace" style={{padding:'32px 20px'}}><p className="section-over">VINHA / EQUIPE ORGANIZADORA</p><h1>{data?.event.title||'Informações do encontro'}</h1><p>Use sua conta da Vinha. O acesso depende do vínculo ativo e da designação para este evento.</p>{error&&<p role="alert" className="program-error">{error} Entre na sua conta no painel e abra este link novamente.</p>}{data&&!error&&<EventInformationPanel key={data.event.id+':'+data.event.version} unit={unit} detail={data} canManage={data.canPublish} saved={()=>setRevision(n=>n+1)}/>}<a href="/painel">Abrir o painel da Vinha</a></main>;
}
