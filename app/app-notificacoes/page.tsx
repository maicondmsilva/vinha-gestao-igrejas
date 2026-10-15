'use client';

import {useCallback, useEffect, useState} from 'react';
import './inbox.css';

type Item={id:string;event_code:string;subject?:string;body:string;entity_type?:string;entity_id?:string;sent_at?:number;created_at:number;read_at?:number};
const icon=(item:Item)=>item.event_code.includes('schedule')?'✓':item.event_code.includes('event')?'◇':'●';
const target=(item:Item)=>item.entity_type?.includes('schedule')?'/app-voluntario':item.entity_type?.includes('chat')?`/app-chat?conversa=${item.entity_id}`:item.entity_type?.includes('event')?`/eventos/${item.entity_id}`:'#';

export default function AppInbox(){
  const [data,setData]=useState<{items:Item[];unread:number}>({items:[],unread:0});
  const [notice,setNotice]=useState('');
  const load=useCallback(async()=>{const response=await fetch('/api/app/inbox');const result=await response.json();if(!response.ok){setNotice(result.error);return;}setNotice('');setData(result)},[]);
  useEffect(()=>{void load()},[load]);
  async function read(id?:string){const response=await fetch('/api/app/inbox',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({action:id?'read':'read-all',id})});const result=await response.json();if(!response.ok){setNotice(result.error);return;}await load()}
  return <main className="app-inbox-page"><header><a href="/painel">← Voltar ao painel</a><span>Aplicativo personalizado</span></header><section className="inbox-shell"><div className="inbox-top"><div><p>APLICATIVO</p><h1>Notificações</h1><small>{data.unread?`${data.unread} mensagem(ns) não lida(s)`:'Você está em dia'}</small></div></div>{notice&&<div className="inbox-notice">{notice}</div>}<div className="inbox-actions"><button onClick={()=>read()}>✓ Marcar todas como lidas</button></div><div className="inbox-list">{data.items.length?data.items.map(item=><article key={item.id} className={!item.read_at?'unread':''} onClick={()=>!item.read_at&&read(item.id)}><i>{icon(item)}</i><div><span><b>{item.subject||'Comunicado da igreja'}</b>{!item.read_at&&<em>NOVA</em>}</span><p>{item.body}</p><small>{new Date(item.sent_at||item.created_at).toLocaleString('pt-BR')}</small></div>{target(item)!=='#'&&<a href={target(item)}>Abrir ›</a>}</article>):<div className="inbox-empty"><i>{notice?'!':'✓'}</i><h2>{notice?'Acesso indisponível':'Nenhuma notificação'}</h2><p>{notice||'Convites, lembretes e comunicados aparecerão aqui.'}</p></div>}</div><nav><a href="/app-voluntario">✓<small>Escalas</small></a><span className="active">●<small>Avisos</small>{data.unread>0&&<b>{data.unread}</b>}</span><a href="/painel">⌂<small>Início</small></a></nav></section></main>;
}
