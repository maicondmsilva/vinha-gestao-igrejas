'use client';
import {useEffect,useMemo,useState} from 'react';
import Link from 'next/link';
import './processing.css';

type Job={id:string;channel:string;status:string;recipient_name?:string;subject?:string;body:string;attempts?:number;last_error?:string;created_at:number;next_attempt_at?:number};
const labels:Record<string,string>={queued:'Na fila',retry:'Nova tentativa',failed:'Falhou',delivered:'Entregue',waiting_configuration:'Aguardando configuração'};
const channels:Record<string,string>={push:'Push',email:'E-mail',whatsapp:'WhatsApp'};

export default function NotificationProcessing(){
 const [jobs,setJobs]=useState<Job[]>([]),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 const load=async()=>{const r=await fetch('/api/notifications',{cache:'no-store'});if(r.ok)setJobs((await r.json()).jobs||[])};
 useEffect(()=>{load()},[]);
 const counts=useMemo(()=>jobs.reduce((a,j)=>(a[j.status]=(a[j.status]||0)+1,a),{} as Record<string,number>),[jobs]);
 const process=async()=>{setBusy(true);setMessage('');const r=await fetch('/api/notifications/process',{method:'POST'}),d=await r.json();setMessage(r.ok?`${d.delivered||0} entregue(s), ${d.retry||0} reagendada(s) e ${d.failed||0} falha(s).`:d.error||'Não foi possível processar a fila.');await load();setBusy(false)};
 const retry=async(id:string)=>{setBusy(true);const r=await fetch('/api/notifications',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({action:'retry',id})});if(!r.ok)setMessage((await r.json()).error||'Não foi possível reagendar.');else setMessage('Notificação devolvida para a fila.');await load();setBusy(false)};
 return <main className="processing-center">
  <header><div><Link href="/configuracoes/notificacoes">← Central de notificações</Link><span><strong>Processamento e entregas</strong><small>Acompanhe a fila e as respostas dos provedores</small></span></div><button disabled={busy} onClick={process}>{busy?'Processando…':'▶ Processar agora'}</button></header>
  {message&&<div className="processing-message">{message}</div>}
  <section className="processing-stats">
   {[['queued','Na fila'],['retry','Reagendadas'],['delivered','Entregues'],['failed','Falhas'],['waiting_configuration','Sem provedor']].map(([key,label])=><article key={key}><small>{label}</small><strong>{counts[key]||0}</strong></article>)}
  </section>
  <section className="processing-panel"><div className="panel-title"><div><h1>Histórico de envios</h1><p>Uma entrega só é confirmada depois da resposta positiva do provedor.</p></div><Link href="/configuracoes/notificacoes/provedores">Configurar provedores</Link></div>
   <div className="job-list">{jobs.length===0?<div className="empty">Nenhuma notificação processada ainda.</div>:jobs.map(j=><article className="job" key={j.id}>
    <div className={`channel ${j.channel}`}>{j.channel==='email'?'✉':j.channel==='whatsapp'?'◉':'●'}</div>
    <div className="job-copy"><div><strong>{j.recipient_name||'Destinatário'}</strong><span>{channels[j.channel]||j.channel}</span></div><b>{j.subject||j.body}</b><small>Criada em {new Date(j.created_at).toLocaleString('pt-BR')} · Tentativas: {j.attempts||0}{j.next_attempt_at?` · Próxima: ${new Date(j.next_attempt_at).toLocaleString('pt-BR')}`:''}</small>{j.last_error&&<em>{j.last_error}</em>}</div>
    <aside><span className={`status ${j.status}`}>{labels[j.status]||j.status}</span>{['failed','waiting_configuration'].includes(j.status)&&<button disabled={busy} onClick={()=>retry(j.id)}>Tentar novamente</button>}</aside>
   </article>)}</div>
  </section>
  <section className="processing-note"><i>↻</i><div><strong>Tentativas automáticas</strong><p>Erros temporários são reagendados com intervalos crescentes. Após cinco tentativas sem sucesso, o envio fica disponível para análise e nova tentativa manual.</p></div></section>
 </main>
}
