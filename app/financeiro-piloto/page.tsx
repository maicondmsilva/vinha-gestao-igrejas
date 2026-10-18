'use client';
import {useEffect,useState,type FormEvent} from 'react';
import {ledgerCurrency as currency} from '../lib/ledger-pilot';
import './ledger-pilot.css';
type Unit={id:string;name:string};
type Balance={accountId:string;name:string;kind:string;balanceCents:string};
type Journal={id:string;effective_date:string;memo:string;reversal_of:string|null};
type Snapshot={balances:Balance[];journals:Journal[];closedThrough:string|null;pagination:{page:number;total:number;limit:number}};
const initial:Snapshot={balances:[],journals:[],closedThrough:null,pagination:{page:1,total:0,limit:25}};
const kinds:Record<string,string>={asset:'Banco / caixa',income:'Receita',expense:'Despesa'};
export default function LedgerPilot(){
 const[units,setUnits]=useState<Unit[]>([]),[unit,setUnit]=useState(''),[date,setDate]=useState(()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())),[page,setPage]=useState(1),[snapshot,setSnapshot]=useState(initial),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(false),[revision,setRevision]=useState(0),[pending,setPending]=useState<Record<string,unknown>|null>(null);
 const[scope,setScope]=useState<{tenant:string}|null>(null);
 useEffect(()=>{setScope({tenant:new URLSearchParams(window.location.search).get('tenant')||''})},[]);
 const tenant=scope?.tenant||'';
 const endpoint=(params:Record<string,string>={})=>'/api/church-ledger?'+new URLSearchParams({...params,...(tenant?{tenant}:{})});
 useEffect(()=>{if(!scope)return;const abort=new AbortController();fetch(endpoint(),{signal:abort.signal,cache:'no-store'}).then(async r=>{const data=await r.json() as {units?:Unit[];error?:string};if(!r.ok)throw Error(data.error||'Acesso indisponível.');if(!abort.signal.aborted){setUnits(data.units||[]);setUnit(data.units?.[0]?.id||'')}}).catch(e=>{if(!abort.signal.aborted)setNotice(e.message)});return()=>abort.abort()},[scope,tenant]);
 useEffect(()=>{if(!scope||!unit)return;const abort=new AbortController();setLoading(true);setSnapshot(initial);fetch(endpoint({unitId:unit,date,page:String(page)}),{signal:abort.signal,cache:'no-store'}).then(async r=>{const data=await r.json() as Snapshot&{error?:string};if(!r.ok)throw Error(data.error||'Não foi possível consultar.');if(!abort.signal.aborted)setSnapshot(data)}).catch(e=>{if(!abort.signal.aborted)setNotice(e.message)}).finally(()=>{if(!abort.signal.aborted)setLoading(false)});return()=>abort.abort()},[scope,tenant,unit,date,page,revision]);
 async function send(command:Record<string,unknown>){
  setBusy(true);setNotice('');
  if(['post','reverse'].includes(String(command.action)))setPending(command);
  try{const response=await fetch(endpoint(),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(command)});const result=await response.json() as {error?:string;id?:string;ok?:boolean};
   if(!response.ok){if(response.status===503&&['post','reverse'].includes(String(command.action)))setPending(command);else setPending(null);throw Error(result.error||'Operação recusada.')}
   if(result.ok!==true)throw Error('Resultado não confirmado.');setPending(null);setNotice('Operação confirmada pelo banco.');setRevision(x=>x+1);
  }catch(e){if(e instanceof TypeError&&['post','reverse'].includes(String(command.action)))setPending(command);setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}
 }
 function submit(event:FormEvent<HTMLFormElement>,action:string){event.preventDefault();const fields=Object.fromEntries(new FormData(event.currentTarget));void send({...fields,action,unitId:unit,...(['post','reverse'].includes(action)?{requestId:crypto.randomUUID()}:{})})}
 const disabled=busy||loading||!scope||!unit||!!pending;
 const card={background:'#fff',border:'1px solid #dce6df',borderRadius:16,padding:24,marginBottom:20};
 const field={display:'grid',gap:6,marginBottom:14} as const;
 return <main className="ledger-pilot" style={{maxWidth:1100,margin:'32px auto',padding:20,color:'#173d30'}}>
  <a href={'/painel'+(tenant?'?tenant='+encodeURIComponent(tenant):'')}>← Voltar ao painel</a>
  <h1>Livro financeiro — homologação</h1><p>Ambiente de testes. Não emite cobranças, notas fiscais ou pagamentos. Não substitui a conciliação bancária e a revisão contábil.</p>
  {notice&&<p role="status" style={{...card,background:'#fff7df'}}>{notice}</p>}
  {pending&&<aside style={card}><h2>Resultado ainda não confirmado</h2><p>Não crie outro lançamento. Consulte o histórico ou reenvie o mesmo pedido para impedir duplicidade.</p><p>Identificador: <code>{String(pending.requestId)}</code></p><button type="button" disabled={busy} onClick={()=>void send(pending)}>Reenviar o mesmo pedido</button></aside>}
  <section style={card}><h2>Consulta por unidade</h2><label style={field}>Unidade<select value={unit} disabled={busy||!!pending} onChange={e=>{setUnit(e.target.value);setPage(1);setNotice('')}}><option value="">Selecione</option>{units.map(u=><option value={u.id} key={u.id}>{u.name}</option>)}</select></label><label style={field}>Saldo e movimentos até<input type="date" value={date} disabled={busy} onChange={e=>{setDate(e.target.value);setPage(1)}}/></label><button type="button" disabled={busy||!unit} onClick={()=>setRevision(x=>x+1)}>Atualizar consulta</button><p>{loading?'Carregando…':`Fechado até: ${snapshot.closedThrough&&snapshot.closedThrough!=='-infinity'?snapshot.closedThrough:'nenhum período'}`}</p>
   <ul>{snapshot.balances.map(b=><li key={b.accountId}>{b.name} · {kinds[b.kind]||b.kind}: {currency(b.balanceCents)}</li>)}</ul><p>Sinais contábeis: débito positivo e crédito negativo. Receita negativa não significa prejuízo.</p>
  </section>
  <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(280px,1fr))',gap:20}}>
   <section style={card}><h2>Nova conta ou categoria</h2><form onSubmit={e=>submit(e,'account')}><label style={field}>Nome<input name="name" required minLength={2} maxLength={100}/></label><label style={field}>Tipo<select name="kind"><option value="asset">Banco / caixa</option><option value="income">Receita (ex.: ofertas)</option><option value="expense">Despesa</option></select></label><button disabled={disabled} type="submit">Criar conta</button></form></section>
   <section style={card}><h2>Novo lançamento / transferência</h2><form onSubmit={e=>submit(e,'post')}><label style={field}>Data<input name="date" type="date" required defaultValue={date}/></label><label style={field}>Descrição<input name="memo" required minLength={2} maxLength={300}/></label><label style={field}>Valor em reais (ex.: 1234,56)<input name="amount" inputMode="decimal" pattern="[0-9]+(,[0-9]{1,2})?" required/></label>{[['debit','Conta debitada'],['credit','Conta creditada']].map(([name,label])=><label key={name} style={field}>{label}<select name={name} required><option value="">Selecione</option>{snapshot.balances.map(b=><option key={b.accountId} value={b.accountId}>{b.name} · {kinds[b.kind]}</option>)}</select></label>)}<p>Transferência: use duas contas de banco/caixa. Peça orientação contábil para receita e despesa.</p><button disabled={disabled} type="submit">Confirmar lançamento</button></form></section>
  </div>
  <section style={card}><h2>Movimentos confirmados</h2>{!loading&&!snapshot.journals.length&&<p>Nenhum movimento nesta consulta.</p>}{snapshot.journals.map(j=><article key={j.id} style={{borderTop:'1px solid #dce6df',padding:'16px 0'}}><p>{j.effective_date} · {j.memo}{j.reversal_of?' · Estorno':''}</p><small>ID: {j.id}</small>{!j.reversal_of&&<details><summary>Estornar sem apagar o original</summary><form onSubmit={e=>submit(e,'reverse')}><input type="hidden" name="originalId" value={j.id}/><label style={field}>Data do estorno<input name="date" type="date" required defaultValue={date}/></label><label style={field}>Motivo<input name="memo" required minLength={2} maxLength={300}/></label><button disabled={disabled} type="submit">Confirmar estorno</button></form></details>}</article>)}<nav aria-label="Paginação financeira"><button type="button" disabled={busy||loading||page<=1} onClick={()=>setPage(x=>x-1)}>Anterior</button> Página {page} <button type="button" disabled={busy||loading||page*25>=snapshot.pagination.total} onClick={()=>setPage(x=>x+1)}>Próxima</button></nav></section>
  <section style={card}><h2>Fechar período</h2><p>Após confirmar, não será possível lançar retroativamente nesse período. Fechamento não significa conciliação de extrato concluída.</p><form onSubmit={e=>submit(e,'close')}><label style={field}>Fechar até<input name="date" type="date" required/></label><label style={field}><span><input type="checkbox" required/> Revisei os lançamentos e confirmo o bloqueio do período.</span></label><button disabled={disabled} type="submit">Confirmar fechamento</button></form></section>
 </main>;
}
