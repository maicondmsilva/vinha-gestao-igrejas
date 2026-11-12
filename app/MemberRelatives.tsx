'use client';
import {useEffect,useState,type FormEvent} from 'react';
import {relationLabels,relations,type Relation} from './lib/family';
import type {ChurchRpc} from '../shared/member-church';

type Relative={name:string;relation:Relation};
type Req={id:string;name:string;relation:Relation;status:string;reason:string|null};
const statusLabel:Record<string,string>={pending:'Em análise',approved:'Aprovado',rejected:'Não aprovado',cancelled:'Cancelado'};
const message=(e:{code?:string}|null)=>e?.code==='42501'?'Envie primeiro o seu cadastro para a igreja.':e?.code==='22023'?'Confira o nome e o parentesco.':e?.code==='54000'?'Você já tem muitos pedidos em análise. Aguarde a igreja.':'Não foi possível concluir agora. Tente de novo.';

/** Aplicativo: minha família (só nome e parentesco) e pedido de inclusão de familiar para a igreja analisar. */
export default function MemberRelatives({rpc,org}:{rpc:ChurchRpc;org:string}){
 const[items,setItems]=useState<Relative[]>([]),[requests,setRequests]=useState<Req[]>([]),[form,setForm]=useState<{name:string;birth:string;relation:Relation|'';home:boolean;nonce:string}|null>(null),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[reload,setReload]=useState(0);
 useEffect(()=>{let live=true;
  Promise.all([rpc.rpc('member_relatives',{p_org:org,p_action:'list',p_data:{}}),rpc.rpc('member_relatives',{p_org:org,p_action:'requests',p_data:{}})]).then(([a,b])=>{if(!live)return;
   if(!a.error)setItems(((a.data as {items?:Relative[]})?.items)||[]);if(!b.error)setRequests(((b.data as {items?:Req[]})?.items)||[])}).catch(()=>undefined);
  return()=>{live=false}},[rpc,org,reload]);
 async function send(e:FormEvent){e.preventDefault();if(!form||!form.relation)return;setBusy(true);setNotice('');
  const r=await rpc.rpc('member_relatives',{p_org:org,p_action:'request',p_data:{nonce:form.nonce,name:form.name.trim(),birth_date:form.birth||null,relation:form.relation,same_household:form.home}});
  setBusy(false);if(r.error){setNotice(message(r.error));return}setForm(null);setNotice('Pedido enviado. A igreja vai conferir e avisar você.');setReload(x=>x+1)}
 const pending=requests.filter(r=>r.status!=='approved');
 return <section className="member-relatives" aria-labelledby="member-relatives-title"><h3 id="member-relatives-title">Minha família</h3>
  {items.length?<ul>{items.map(i=><li key={i.name+i.relation}><b>{i.name}</b> · {relationLabels[i.relation]||i.relation}</li>)}</ul>:<p>Nenhum familiar ligado ao seu cadastro ainda.</p>}
  {notice&&<p role="status">{notice}</p>}
  {!form?<button type="button" onClick={()=>{setNotice('');setForm({name:'',birth:'',relation:'',home:false,nonce:crypto.randomUUID()})}}>Pedir inclusão de familiar</button>:
   <form onSubmit={send}><label>Nome do familiar<input required minLength={2} maxLength={160} value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label>
    <label>Data de nascimento (opcional)<input type="date" value={form.birth} onChange={e=>setForm({...form,birth:e.target.value})}/></label>
    <label>Essa pessoa é meu/minha…<select required value={form.relation} onChange={e=>setForm({...form,relation:e.target.value as Relation})}><option value="">Escolha</option>{relations.map(r=><option key={r} value={r}>{relationLabels[r]}</option>)}</select></label>
    <label><input type="checkbox" checked={form.home} onChange={e=>setForm({...form,home:e.target.checked})}/> Mora comigo</label>
    <button disabled={busy}>{busy?'Enviando…':'Enviar para a igreja'}</button><button type="button" disabled={busy} onClick={()=>setForm(null)}>Cancelar</button></form>}
  {!!pending.length&&<><h4>Pedidos enviados</h4><ul>{pending.map(r=><li key={r.id}>{r.name} · {relationLabels[r.relation]||r.relation} · {statusLabel[r.status]||r.status}{r.reason?' — '+r.reason:''}</li>)}</ul></>}
 </section>;
}
