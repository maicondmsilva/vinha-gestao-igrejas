'use client';
import {useEffect,useState} from 'react';
import {hierarchyAcceptanceMessage} from '../lib/hierarchy-governance';
import '../admin-vinha/faturamento/billing.css';
import '../admin-vinha/hierarquia/approvals.css';
type Row={id:string;parent_church_id:string;child_church_id:string;parent_name:string;child_name:string;billing_mode:string;status:string;parent_approved_at?:number;child_approved_at?:number;parent_approval_requires_renewal?:boolean;child_approval_requires_renewal?:boolean};
export default function MyLinks(){
 const[items,setItems]=useState<Row[]>([]),[churchId,setChurchId]=useState(''),[canApprove,setCanApprove]=useState(false),[notice,setNotice]=useState(''),[busy,setBusy]=useState<string|null>(null);
 const load=async()=>{const r=await fetch('/api/hierarchy/requests',{cache:'no-store'}),d=await r.json();if(!r.ok)throw new Error(d.error||'Não foi possível carregar os vínculos.');setItems(d.items||[]);setChurchId(d.churchId);setCanApprove(d.canApprove)};
 useEffect(()=>{void load().catch(error=>setNotice(error instanceof Error?error.message:'Falha de conexão. Tente novamente.'))},[]);
 const decide=async(id:string,decision:'approve'|'reject')=>{
  if(busy)return;setBusy(id);
  try{const r=await fetch('/api/hierarchy/requests',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({id,decision})}),d=await r.json();if(!r.ok)throw new Error(d.error||'Não foi possível registrar a resposta.');setNotice(hierarchyAcceptanceMessage(d));await load()}
  catch(error){setNotice(error instanceof Error?error.message:'Falha de conexão. Tente novamente.');try{await load()}catch{/* Preserve the original failure and the ability to retry. */}}
  finally{setBusy(null)}
 };
 return <main className="approval-page"><header><a href="/painel">← Voltar ao painel</a><i>V</i><span><b>Solicitações de vínculo</b><small>Vinha · Hierarquia ministerial</small></span></header>{notice&&<div className="billing-notice" role="status">{notice}</div>}<section><h1>Confirme com segurança</h1><p>O vínculo só será ativado depois que os responsáveis da sede e da igreja filha aceitarem e mantiverem o acesso necessário.</p>{items.length===0?<div className="approval-empty">Você não possui solicitações de vínculo.</div>:items.map(x=>{
  const isParent=churchId===x.parent_church_id,approved=isParent?x.parent_approved_at:x.child_approved_at,renewal=isParent?x.parent_approval_requires_renewal:x.child_approval_requires_renewal,pending=x.status==='pending';
  return <article key={x.id}><div className="approval-flow"><span><small>SEDE</small><b>{x.parent_name}</b></span><i>→</i><span><small>IGREJA FILHA</small><b>{x.child_name}</b></span></div><p>Cobrança: <b>{x.billing_mode==='centralized'?'o CNPJ da sede será responsável':'cada igreja continuará pagando individualmente'}</b>.</p>{pending&&renewal&&<p>O aceite anterior precisa ser renovado por um gestor atual deste ministério. Nenhum vínculo foi ativado.</p>}<div className="approval-actions">{!pending?<em>{x.status==='approved'?'✓ Vínculo aprovado':'Solicitação recusada'}</em>:!canApprove?<em>Somente administrador ou pastor pode responder.</em>:<><button type="button" disabled={busy!==null} className="reject" onClick={()=>void decide(x.id,'reject')}>Recusar</button>{approved&&!renewal?<em>✓ Seu aceite já foi registrado. Aguardando a outra parte.</em>:<button type="button" disabled={busy!==null} onClick={()=>void decide(x.id,'approve')}>{busy===x.id?'Registrando…':renewal?'Renovar aceite':'Aceitar vínculo'}</button>}</>}</div></article>
 })}</section></main>
}
