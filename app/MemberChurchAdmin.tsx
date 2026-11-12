'use client';
import {useEffect,useState,type FormEvent} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import './organization-settings.css';
type Transfer={id:string;full_name:string;source_name:string;target_name:string;created_at:string};
/** Pessoas: pedidos de mudança de igreja feitos pelo portal do membro. Só aparece quando há pedido. */
export default function MemberChurchAdmin(){
 const [items,setItems]=useState<Transfer[]>([]),[busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[revision,setRevision]=useState(0);
 useEffect(()=>{const c=new AbortController();fetch(settingsUrl('/api/member-church-admin'),{cache:'no-store',signal:c.signal}).then(async r=>{const d=await r.json() as {error?:string;items?:Transfer[]};if(!r.ok)throw Error(d.error||'Acesso indisponível.');setItems(d.items||[])}).catch(e=>{if(!c.signal.aborted&&e instanceof Error&&!/acesso|permiss/i.test(e.message))setNotice(e.message)});return()=>c.abort()},[revision]);
 async function send(body:Record<string,unknown>){if(busy)return;setBusy(true);setNotice('');try{const r=await fetch(settingsUrl('/api/member-church-admin'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}),d=await r.json() as {ok?:boolean;error?:string};if(!r.ok||!d.ok)throw Error(d.error||'Operação não confirmada.');setRevision(n=>n+1);setNotice('Decisão registrada. Nenhum cargo ou acesso administrativo foi transferido.')}catch(e){setNotice(e instanceof Error?e.message:'Atualize antes de repetir.')}finally{setBusy(false)}}
 function review(e:FormEvent<HTMLFormElement>,id:string){e.preventDefault();const f=new FormData(e.currentTarget);void send({action:'review',id,data:{decision:f.get('decision'),reason:f.get('reason')}})}
 if(!items.length&&!notice)return null;
 return <section className="organization-card member-transfers"><h2>Transferências de igreja</h2><p>Pedidos feitos pelo aplicativo para mudar de igreja. Só a aprovação transfere o membro. Confira identidade, origem e destino antes de aprovar. Histórico, cargos e acessos específicos não são transferidos.</p>{notice&&<p role="status">{notice}</p>}<button type="button" disabled={busy} onClick={()=>setRevision(n=>n+1)}>Atualizar transferências</button>{items.map(t=><form key={t.id} onSubmit={e=>review(e,t.id)}><h3>{t.full_name}</h3><p>{t.source_name} → {t.target_name}</p><fieldset disabled={busy}><label>Decisão<select name="decision" required defaultValue=""><option value="" disabled>Selecione</option><option value="approved">Aprovar transferência</option><option value="rejected">Recusar transferência</option></select></label><label>Motivo<textarea name="reason" required minLength={5} maxLength={1000}/></label><button type="submit">Confirmar decisão</button></fieldset></form>)}</section>;
}
