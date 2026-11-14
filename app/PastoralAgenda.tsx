'use client';
import {useCallback,useEffect,useState} from 'react';
import {durationLabel,pastoralKinds,pastoralModes,pastoralStatus} from '../shared/pastoral';
import './pastoral.css';

type Hour={weekday:number;starts:string;ends:string};
type Block={id:string;from:string;to:string;reason:string};
type Attendant={id:string;personId:string;name:string;role:string;about:string;autoConfirm:boolean;durations:number[];kinds:string[];modes:string[];active:boolean;version:number;self:boolean;hours:Hour[];blocks:Block[]};
type Item={id:string;attendantId:string;attendant:string;personId:string;person:string;kind:string;mode:string;startsAt:string;endsAt:string;status:string;origin:string;memberAck:boolean;message:string;link:string;reason:string;notes:string;version:number;address:string};
type Data={timezone:string;canEdit:boolean;canSettings:boolean;attendants:Attendant[];items:Item[]};
type Found={id:string;name:string;phone?:string};
const days=['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'];
const allDurations=[15,30,45,60,90,120];
const tenantQuery=()=>{const t=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant');return t?{tenant:t}:{} as Record<string,string>};
const fmt=(iso:string,o:Intl.DateTimeFormatOptions)=>new Date(iso).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',...o});
const uuid=()=>crypto.randomUUID();

function PersonSearch({unit,label,onPick}:{unit:string;label:string;onPick:(p:Found)=>void}){
 const[q,setQ]=useState(''),[list,setList]=useState<Found[]>([]);
 useEffect(()=>{if(q.trim().length<2){Promise.resolve().then(()=>setList([]));return}const c=new AbortController(),t=setTimeout(()=>{
  fetch('/api/pastoral?'+new URLSearchParams({unit,q:q.trim(),...tenantQuery()}),{cache:'no-store',signal:c.signal}).then(r=>r.ok?r.json() as Promise<{items?:Found[]}>:null).then(d=>setList(d?.items||[])).catch(()=>undefined)},250);
  return()=>{clearTimeout(t);c.abort()}},[q,unit]);
 return <div className="pa-pick"><label>{label}<input value={q} maxLength={80} onChange={e=>setQ(e.target.value)} placeholder="Digite ao menos 2 letras do nome"/></label>
  {list.length>0&&<ul>{list.map(p=><li key={p.id}><button type="button" onClick={()=>{onPick(p);setQ('');setList([])}}>{p.name}{p.phone?<small> · {p.phone}</small>:null}</button></li>)}</ul>}</div>;
}

/** Pessoas › Agenda pastoral: pedidos para confirmar, semana de atendimentos, marcar com membro e configurar quem atende. */
export default function PastoralAgenda({unitId}:{unitId:string}){
 const[data,setData]=useState<Data|null>(null),[error,setError]=useState(''),[notice,setNotice]=useState(''),[rev,setRev]=useState(0),[tab,setTab]=useState<'week'|'pending'|'people'>('week'),[busy,setBusy]=useState(false),[scheduling,setScheduling]=useState(false),[editing,setEditing]=useState<Attendant|'new'|null>(null);
 useEffect(()=>{if(!/^[0-9a-f-]{36}$/i.test(unitId))return;const c=new AbortController();const from=new Date(Date.now()-7*864e5).toISOString(),to=new Date(Date.now()+42*864e5).toISOString();
  fetch('/api/pastoral?'+new URLSearchParams({unit:unitId,from,to,...tenantQuery()}),{cache:'no-store',signal:c.signal}).then(async r=>{const d=await r.json() as Data&{error?:string};if(!r.ok)throw Error(d.error||'Não foi possível carregar.');setError('');setData(d)}).catch(e=>{if(!c.signal.aborted)setError(e instanceof Error?e.message:'Falha de conexão.')});
  return()=>c.abort()},[unitId,rev]);
 const run=useCallback(async(action:string,payload:Record<string,unknown>,done:string)=>{setBusy(true);setError('');setNotice('');try{const r=await fetch('/api/pastoral?'+new URLSearchParams(tenantQuery()),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({unit:unitId,action,data:payload})}),d=await r.json() as {ok?:boolean;error?:string;slots?:unknown};if(!r.ok)throw Error(d.error||'Não confirmado.');if(done){setNotice(done);setRev(n=>n+1)}return d}catch(e){setError(e instanceof Error?e.message:'Não confirmado.');return null}finally{setBusy(false)}},[unitId]);
 if(!data)return <section className="pa-page"><p className="pd-empty">{error||'Carregando a agenda pastoral…'}</p></section>;
 const pending=data.items.filter(i=>i.status==='requested'),now=Date.now(),upcoming=data.items.filter(i=>Date.parse(i.endsAt)>now-6*36e5);
 const byDay=new Map<string,Item[]>();for(const i of upcoming){const k=fmt(i.startsAt,{weekday:'long',day:'2-digit',month:'long'});byDay.set(k,[...(byDay.get(k)||[]),i])}
 const card=(i:Item)=><article key={i.id} className={'pa-item '+i.status}>
  <div className="pa-time"><b>{fmt(i.startsAt,{hour:'2-digit',minute:'2-digit'})}</b><small>{Math.round((Date.parse(i.endsAt)-Date.parse(i.startsAt))/6e4)} min</small></div>
  <div className="pa-body"><strong>{i.person}</strong><span>com {i.attendant} · {pastoralKinds[i.kind]||i.kind} · {pastoralModes[i.mode]||i.mode}</span>
   {i.message&&<em>“{i.message}”</em>}{i.address&&<span>Endereço: {i.address}</span>}{i.link&&<a href={i.link} target="_blank" rel="noreferrer">Link da conversa online</a>}
   {i.notes&&<details><summary>Anotação sigilosa</summary><p>{i.notes}</p></details>}
   <span className={'pa-status '+i.status}>{i.origin==='staff'&&!i.memberAck&&i.status==='confirmed'?'Aguardando o membro confirmar presença':pastoralStatus[i.status]}</span></div>
  <div className="pa-actions">{i.status==='requested'&&<><button type="button" className="pa-go" disabled={busy} onClick={()=>void run('decide',{id:i.id,version:i.version,decision:'confirm',reason:'',link:i.mode==='online'?(prompt('Link da conversa online (opcional, https://…)')||''):''},'Atendimento confirmado. O membro recebe o aviso no app.')}>Confirmar</button>
    <button type="button" disabled={busy} onClick={()=>{const reason=prompt('Motivo (opcional, aparece para o membro)')??'';void run('decide',{id:i.id,version:i.version,decision:'decline',reason:reason.slice(0,200),link:''},'Pedido recusado. O membro pode escolher outro dia.')}}>Recusar</button></>}
   {i.status==='confirmed'&&Date.parse(i.startsAt)<now&&<><button type="button" disabled={busy} onClick={()=>void run('status',{id:i.id,version:i.version,status:'done',reason:''},'Marcado como realizado.')}>Realizado</button><button type="button" disabled={busy} onClick={()=>void run('status',{id:i.id,version:i.version,status:'missed',reason:''},'Marcado como não compareceu.')}>Não veio</button></>}
   {['requested','confirmed'].includes(i.status)&&Date.parse(i.startsAt)>now&&<button type="button" className="pa-quiet" disabled={busy} onClick={()=>{if(confirm('Cancelar este atendimento?'))void run('status',{id:i.id,version:i.version,status:'cancelled',reason:''},'Atendimento cancelado.')}}>Cancelar</button>}
   {data.attendants.find(a=>a.id===i.attendantId)?.self&&<button type="button" className="pa-quiet" disabled={busy} onClick={()=>{const n=prompt('Anotação sigilosa (só você e quem tem permissão veem)',i.notes);if(n!==null)void run('note',{id:i.id,version:i.version,notes:n.slice(0,4000)},'Anotação salva.')}}>Anotação</button>}</div>
 </article>;

 return <section className="pa-page">
  <header className="pa-head"><div><p className="section-over">CUIDADO PASTORAL</p><h2>Agenda pastoral</h2><p>Pedidos de horário feitos pelo app, atendimentos e visitas.</p></div>
   <div className="pa-head-actions">{(data.canEdit||data.attendants.some(a=>a.self))&&<button type="button" className="pa-go" onClick={()=>setScheduling(true)}>＋ Marcar com membro</button>}</div></header>
  <nav className="pd-views" aria-label="Agenda pastoral">{([['week','Próximos atendimentos',null],['pending','Aguardando confirmação',pending.length||null],['people','Quem atende',data.attendants.length]] as const).map(([k,l,n])=><button key={k} type="button" aria-pressed={tab===k} onClick={()=>setTab(k)}>{l}{n?<b>{n}</b>:null}</button>)}</nav>
  {notice&&<p className="program-notice" role="status">{notice}</p>}{error&&<p className="program-error" role="alert">{error}</p>}
  {tab==='pending'&&(pending.length?pending.map(card):<p className="pd-empty">Nenhum pedido aguardando. Quem atende com confirmação automática não passa por aqui.</p>)}
  {tab==='week'&&(byDay.size?[...byDay].map(([d,list])=><div key={d} className="pa-day"><h3>{d}</h3>{list.map(card)}</div>):<p className="pd-empty">Nenhum atendimento nas próximas semanas.</p>)}
  {tab==='people'&&<div className="pa-people">{data.attendants.map(a=><article key={a.id} className="pa-person">
    <header><div><strong>{a.name}</strong><span>{a.role}{a.active?'':' · pausado'}</span></div><span className={'pa-switch'+(a.autoConfirm?' on':'')}>{a.autoConfirm?'Confirmação automática':'Confirmação manual'}</span></header>
    <p>{a.hours.length?a.hours.map(h=>`${days[h.weekday]!.slice(0,3)} ${h.starts}–${h.ends}`).join(' · '):'Sem horários de atendimento ainda.'}</p>
    <p className="pa-muted">Durações: {a.durations.map(durationLabel).join(', ')} · {a.kinds.map(k=>pastoralKinds[k]).join(', ')}</p>
    {a.blocks.length>0&&<p className="pa-muted">Bloqueios: {a.blocks.map(b=>`${b.from.split('-').reverse().join('/')} a ${b.to.split('-').reverse().join('/')}${b.reason?' ('+b.reason+')':''}`).join(' · ')}</p>}
    {(data.canSettings||a.self)&&<button type="button" onClick={()=>setEditing(a)}>Configurar</button>}
   </article>)}
   {!data.attendants.length&&<p className="pd-empty">Ninguém atendendo ainda. Cadastre o pastor ou líder que vai receber pedidos pelo app.</p>}
   {data.canSettings&&<button type="button" className="pa-go" onClick={()=>setEditing('new')}>＋ Adicionar quem atende</button>}</div>}
  {editing&&<AttendantEditor unit={unitId} item={editing==='new'?null:editing} canSettings={data.canSettings} busy={busy} run={run} close={()=>setEditing(null)}/>}
  {scheduling&&<ScheduleForm unit={unitId} attendants={data.attendants.filter(a=>a.active&&(data.canEdit||a.self))} busy={busy} run={run} close={()=>setScheduling(false)}/>}
 </section>;
}

type Run=(action:string,payload:Record<string,unknown>,done:string)=>Promise<unknown>;
function AttendantEditor({unit,item,canSettings,busy,run,close}:{unit:string;item:Attendant|null;canSettings:boolean;busy:boolean;run:Run;close:()=>void}){
 const[person,setPerson]=useState<Found|null>(item?{id:item.personId,name:item.name}:null),[role,setRole]=useState(item?.role||'Pastor'),[about,setAbout]=useState(item?.about||''),[auto,setAuto]=useState(item?.autoConfirm??false),[durations,setDurations]=useState<number[]>(item?.durations||[30,45,60]),
  [kinds,setKinds]=useState<string[]>(item?.kinds||['conversa','aconselhamento','oracao']),[modes,setModes]=useState<string[]>(item?.modes||['presencial']),[active,setActive]=useState(item?.active??true),[hours,setHours]=useState<Hour[]>(item?.hours||[]),[block,setBlock]=useState({from:'',to:'',reason:''});
 const toggle=<T,>(list:T[],v:T,set:(l:T[])=>void)=>set(list.includes(v)?list.filter(x=>x!==v):[...list,v]);
 async function save(){if(!person)return;const id=item?.id||uuid();
  if(canSettings){const ok=await run('save_attendant',{id,person:person.id,role:role.trim()||'Pastor',about:about.trim(),autoConfirm:auto,durations,kinds,modes,active,version:item?.version||0},'');if(!ok)return}
  const ok=await run('hours',{attendant:id,hours},'Configuração salva. O app já mostra os dias livres.');if(ok)close()}
 return <div className="pa-overlay" role="dialog" aria-modal="true" aria-label="Configurar quem atende"><div className="pa-modal">
  <h3>{item?'Configurar '+item.name:'Adicionar quem atende'}</h3>
  {canSettings&&<>{person?<p><b>{person.name}</b> {!item&&<button type="button" className="pa-quiet" onClick={()=>setPerson(null)}>trocar</button>}</p>:<PersonSearch unit={unit} label="Pessoa que vai atender" onPick={setPerson}/>}
   <div className="pa-grid"><label>Função que o membro vê<input value={role} maxLength={40} onChange={e=>setRole(e.target.value)} placeholder="Pastor, Líder, Secretaria"/></label><label>Apresentação curta<input value={about} maxLength={300} onChange={e=>setAbout(e.target.value)} placeholder="Ex.: aconselhamento de casais"/></label></div>
   <label className="pa-toggle"><input type="checkbox" checked={auto} onChange={e=>setAuto(e.target.checked)}/><span><b>Confirmação automática</b>{auto?' ligada: o pedido do membro já entra confirmado.':' desligada: você confirma cada pedido.'}</span></label>
   <fieldset><legend>Durações que o membro pode escolher</legend>{allDurations.map(d=><label key={d} className="pa-chip"><input type="checkbox" checked={durations.includes(d)} onChange={()=>toggle(durations,d,setDurations)}/>{durationLabel(d)}</label>)}</fieldset>
   <fieldset><legend>Assuntos</legend>{Object.entries(pastoralKinds).map(([k,l])=><label key={k} className="pa-chip"><input type="checkbox" checked={kinds.includes(k)} onChange={()=>toggle(kinds,k,setKinds)}/>{l}</label>)}</fieldset>
   <fieldset><legend>Onde atende</legend>{Object.entries(pastoralModes).map(([k,l])=><label key={k} className="pa-chip"><input type="checkbox" checked={modes.includes(k)} onChange={()=>toggle(modes,k,setModes)}/>{k==='visita'?'Visita em casa':l}</label>)}</fieldset>
   <label className="pa-toggle"><input type="checkbox" checked={active} onChange={e=>setActive(e.target.checked)}/><span>Recebendo pedidos</span></label></>}
  <fieldset><legend>Horários da semana</legend>{hours.map((h,i)=><div key={i} className="pa-hour"><select value={h.weekday} onChange={e=>setHours(hours.map((x,j)=>j===i?{...x,weekday:Number(e.target.value)}:x))}>{days.map((d,k)=><option key={k} value={k}>{d}</option>)}</select>
    <input type="time" value={h.starts} onChange={e=>setHours(hours.map((x,j)=>j===i?{...x,starts:e.target.value}:x))}/><span>até</span><input type="time" value={h.ends} onChange={e=>setHours(hours.map((x,j)=>j===i?{...x,ends:e.target.value}:x))}/>
    <button type="button" className="pa-quiet" aria-label="Remover faixa" onClick={()=>setHours(hours.filter((_,j)=>j!==i))}>✕</button></div>)}
   <button type="button" onClick={()=>setHours([...hours,{weekday:2,starts:'14:00',ends:'18:00'}])}>＋ Adicionar faixa</button></fieldset>
  {item&&<fieldset><legend>Bloquear dias (férias, viagens)</legend><div className="pa-hour"><input type="date" value={block.from} onChange={e=>setBlock({...block,from:e.target.value})}/><span>até</span><input type="date" value={block.to} onChange={e=>setBlock({...block,to:e.target.value})}/><input value={block.reason} maxLength={120} placeholder="Motivo (interno)" onChange={e=>setBlock({...block,reason:e.target.value})}/>
    <button type="button" disabled={busy||!block.from||!block.to} onClick={()=>void run('block',{attendant:item.id,...block},'Dias bloqueados.').then(ok=>{if(ok)close()})}>Bloquear</button></div>
   {item.blocks.map(b=><p key={b.id} className="pa-muted">{b.from.split('-').reverse().join('/')} a {b.to.split('-').reverse().join('/')} {b.reason} <button type="button" className="pa-quiet" onClick={()=>void run('unblock',{attendant:item.id,id:b.id},'Bloqueio removido.').then(ok=>{if(ok)close()})}>remover</button></p>)}</fieldset>}
  <footer><button type="button" onClick={close}>Voltar</button><button type="button" className="pa-go" disabled={busy||!person||!durations.length||!kinds.length||!modes.length} onClick={()=>void save()}>{busy?'Salvando…':'Salvar'}</button></footer>
 </div></div>;
}

function ScheduleForm({unit,attendants,busy,run,close}:{unit:string;attendants:Attendant[];busy:boolean;run:Run;close:()=>void}){
 const[att,setAtt]=useState(attendants[0]?.id||''),[person,setPerson]=useState<Found|null>(null),[kind,setKind]=useState('visita'),[mode,setMode]=useState('visita'),[minutes,setMinutes]=useState(60),[date,setDate]=useState(''),[slots,setSlots]=useState<{startsAt:string;label:string}[]>([]),[slot,setSlot]=useState(''),[message,setMessage]=useState(''),[link,setLink]=useState(''),[id]=useState(uuid);
 useEffect(()=>{setSlot('');if(!att||!date){Promise.resolve().then(()=>setSlots([]));return}void run('slots',{attendant:att,minutes,date},'').then(d=>setSlots(((d as {slots?:{startsAt:string;label:string}[]})?.slots)||[]))},[att,date,minutes,run]);
 return <div className="pa-overlay" role="dialog" aria-modal="true" aria-label="Marcar com membro"><div className="pa-modal">
  <h3>Marcar com um membro</h3><p className="pa-muted">O membro recebe o aviso no app e confirma presença. Sem a regra das 24 horas; o horário não pode coincidir com outro.</p>
  <label>Quem vai atender<select value={att} onChange={e=>setAtt(e.target.value)}>{attendants.map(a=><option key={a.id} value={a.id}>{a.name} · {a.role}</option>)}</select></label>
  {person?<p>Membro: <b>{person.name}</b> <button type="button" className="pa-quiet" onClick={()=>setPerson(null)}>trocar</button></p>:<PersonSearch unit={unit} label="Membro" onPick={setPerson}/>}
  <div className="pa-grid"><label>Assunto<select value={kind} onChange={e=>setKind(e.target.value)}>{Object.entries(pastoralKinds).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
   <label>Onde<select value={mode} onChange={e=>setMode(e.target.value)}>{Object.entries(pastoralModes).map(([k,l])=><option key={k} value={k}>{k==='visita'?'Visita na casa do membro':l}</option>)}</select></label>
   <label>Duração<select value={minutes} onChange={e=>setMinutes(Number(e.target.value))}>{allDurations.map(d=><option key={d} value={d}>{durationLabel(d)}</option>)}</select></label>
   <label>Dia<input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label></div>
  {date&&<div className="pa-slots">{slots.length?slots.map(s=><button key={s.startsAt} type="button" aria-pressed={slot===s.startsAt} onClick={()=>setSlot(s.startsAt)}>{s.label}</button>):<span className="pa-muted">Sem horários livres neste dia (confira os horários da semana e bloqueios).</span>}</div>}
  <label>Mensagem para o membro (opcional)<input value={message} maxLength={500} onChange={e=>setMessage(e.target.value)}/></label>
  {mode==='online'&&<label>Link da conversa online<input type="url" value={link} maxLength={300} onChange={e=>setLink(e.target.value)} placeholder="https://…"/></label>}
  <footer><button type="button" onClick={close}>Voltar</button><button type="button" className="pa-go" disabled={busy||!person||!slot} onClick={()=>void run('schedule',{id,attendant:att,person:person!.id,minutes,startsAt:slot,kind,mode,message:message.trim(),link:link.trim()},'Atendimento marcado. O membro foi avisado no app.').then(ok=>{if(ok)close()})}>Marcar</button></footer>
 </div></div>;
}
