'use client';

import Link from 'next/link';
import {FormEvent, useCallback, useEffect, useState} from 'react';
import './app-chat.css';

type Person = {id:string; full_name:string};
type Channel = {id:string; name:string; scope_type:string; visibility:string; last_message?:string; unread_count:number};
type Message = {id:string; sender_person_id:string; sender_name:string; body:string; created_at:number};
type ChatData = {channels:Channel[]; people:Person[]; actorPersonId?:string};

export default function AppChat(){
  const [data,setData]=useState<ChatData>({channels:[],people:[]});
  const [active,setActive]=useState<Channel|null>(null);
  const [messages,setMessages]=useState<Message[]>([]);
  const [notice,setNotice]=useState('');

  const load=useCallback(async()=>{
    const response=await fetch('/api/chat');
    const result=await response.json();
    if(!response.ok){setNotice(result.error||'Não foi possível abrir as conversas.');return;}
    setNotice('');setData(result);
    const requested=new URLSearchParams(location.search).get('conversa');
    setActive(current=>current||result.channels.find((item:Channel)=>item.id===requested)||result.channels[0]||null);
  },[]);

  const open=useCallback(async()=>{
    if(!active)return;
    const response=await fetch(`/api/chat?conversationId=${encodeURIComponent(active.id)}`);
    const result=await response.json();
    if(!response.ok){setNotice(result.error);return;}
    setMessages(result.messages||[]);
    await fetch('/api/chat',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({action:'read',conversationId:active.id})});
  },[active]);

  useEffect(()=>{void load()},[load]);
  useEffect(()=>{void open()},[open]);

  async function send(event:FormEvent<HTMLFormElement>){
    event.preventDefault();
    if(!active)return;
    const form=event.currentTarget;
    const body=String(new FormData(form).get('body')||'');
    const response=await fetch('/api/chat',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:'send',conversationId:active.id,body})});
    const result=await response.json();
    if(!response.ok){setNotice(result.error);return;}
    await fetch('/api/chat/notify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({messageId:result.id})});
    form.reset();await open();await load();
  }

  async function direct(targetPersonId:string){
    const response=await fetch('/api/chat/direct',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({targetPersonId})});
    const result=await response.json();
    if(!response.ok){setNotice(result.error);return;}
    await load();
    setActive({id:result.id,name:data.people.find(item=>item.id===targetPersonId)?.full_name||'Conversa privada',scope_type:'direct',visibility:'members',unread_count:0});
  }

  const ownName=data.people.find(item=>item.id===data.actorPersonId)?.full_name||'';
  return <main className="mobile-chat-page"><header><Link href="/painel">← Painel</Link><span>Aplicativo personalizado</span></header><section className="mobile-chat"><aside><div className="mobile-chat-title"><span><small>COMUNIDADE</small><h1>Conversas</h1></span><Link href="/app-notificacoes">●</Link></div><h3>CANAIS E GRUPOS</h3>{data.channels.map(channel=><button className={active?.id===channel.id?'active':''} key={channel.id} onClick={()=>setActive(channel)}><i>{channel.scope_type==='direct'?'♙':channel.scope_type==='schedule'?'✓':'#'}</i><span><b>{channel.scope_type==='direct'?channel.name.replace(ownName,'').replace(' e ','')||channel.name:channel.name}</b><small>{channel.last_message||'Toque para abrir'}</small></span>{channel.unread_count>0&&<em>{channel.unread_count}</em>}</button>)}<h3>NOVA CONVERSA</h3>{data.people.filter(person=>person.id!==data.actorPersonId).slice(0,5).map(person=><button key={person.id} onClick={()=>direct(person.id)}><i>{person.full_name.split(' ').map(part=>part[0]).join('').slice(0,2)}</i><span><b>{person.full_name}</b><small>Mensagem privada</small></span></button>)}</aside><div className="mobile-conversation">{notice&&!active?<div className="mobile-chat-empty"><i>!</i><h2>Acesso ao chat indisponível</h2><p>{notice}</p></div>:active?<><header><button onClick={()=>setActive(null)}>‹</button><i>{active.scope_type==='direct'?'♙':'#'}</i><span><b>{active.name}</b><small>{active.scope_type==='schedule'?'Equipe da escala':'Canal protegido'}</small></span></header>{notice&&<div className="mobile-chat-notice">{notice}</div>}<div className="mobile-messages">{messages.map(message=><article className={message.sender_person_id===data.actorPersonId?'mine':''} key={message.id}><small>{message.sender_name}</small><p>{message.body}</p><time>{new Date(message.created_at).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}</time></article>)}</div><form onSubmit={send}><input name="body" placeholder="Escreva uma mensagem" required/><button>➤</button></form></>:<div className="mobile-chat-empty"><i>◌</i><h2>Suas conversas</h2><p>Escolha um canal ou inicie uma mensagem privada.</p></div>}</div><nav><Link href="/app-voluntario">✓<small>Escalas</small></Link><span className="active">◌<small>Conversas</small></span><Link href="/app-notificacoes">●<small>Avisos</small></Link></nav></section></main>;
}
