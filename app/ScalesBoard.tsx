'use client';
import './scales-board.css';
import {useEffect,useMemo,useState} from 'react';
import {formatInZone,panelTimezone,toLocalDay} from '../shared/timezone';
import {boardPublishMessage,conflictLabel,weekRange} from './lib/scale-board';

type Service={id:string;title:string;startsAt:string;timezone:string;status:'draft'|'published';version:number;started:boolean;canPublish:boolean;open:number};
type Row={team:string;teamName:string;role:string;roleName:string;ordinal:number;canAssign:boolean};
type Cell={service:string;team:string;role:string;ordinal:number;member:string|null;name:string|null;conflicts:string[];response:string|null};
type Board={services:Service[];rows:Row[];cells:Cell[]};
type Suggestion={id:string;name:string;conflicts:string[];recent:number};
type Team={id:string;name:string};
type Pick={service:Service;row:Row;cell:Cell|undefined};
const responseLabel:Record<string,string>={pending:'Aguardando',accepted:'Confirmou',declined:'Recusou'};
const periods=[['7','Próximos 7 dias'],['14','Próximas 2 semanas'],['31','Próximo mês']] as const;
const key=(s:string,r:string,o:number)=>s+'|'+r+'|'+o;

function url(path:string,params:Record<string,string>){const p=new URLSearchParams(params);const t=new URLSearchParams(location.search).get('tenant');if(t)p.set('tenant',t);return path+'?'+p}
async function call<T>(path:string,params:Record<string,string>,body?:unknown):Promise<T>{
 const r=await fetch(body?url(path,{}):url(path,params),body?{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}:{cache:'no-store'});
 const d=await r.json().catch(()=>({})) as T&{error?:string};if(!r.ok)throw Error(d.error||'Não foi possível concluir.');return d;
}

/** Escalas › Quadro de montagem: funções × cultos do período, escalar várias datas e publicar em lote. */
export default function ScalesBoard({unitId,teams}:{unitId:string;teams:Team[]}){
 const today=toLocalDay(new Date(),panelTimezone());
 const[days,setDays]=useState('14'),[team,setTeam]=useState(''),[board,setBoard]=useState<Board|null>(null),[error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[reload,setReload]=useState(0);
 const[pick,setPick]=useState<Pick|null>(null),[suggestions,setSuggestions]=useState<Suggestion[]|null>(null),[search,setSearch]=useState(''),[selected,setSelected]=useState<string[]>([]);
 const range=weekRange(today,Number(days));
 useEffect(()=>{let live=true;call<Board>('/api/scales-board',{unit:unitId,from:range.from,to:range.to,...(team?{team}:{})}).then(b=>{if(live){setError('');setBoard(b)}}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}
  // eslint-disable-next-line react-hooks/exhaustive-deps
 },[unitId,days,team,reload]);
 const cells=useMemo(()=>new Map((board?.cells||[]).map(c=>[key(c.service,c.role,c.ordinal),c])),[board]);
 useEffect(()=>{if(!pick)return;let live=true;call<{items:Suggestion[]}>('/api/scales-operations',{unit:unitId,action:'suggest',service:pick.service.id,role:pick.row.role,ordinal:String(pick.row.ordinal),...(search?{search}:{})})
  .then(d=>{if(live)setSuggestions(d.items)}).catch(e=>{if(live){setSuggestions([]);setError(e.message)}});return()=>{live=false}},[pick,search,unitId]);

 async function assign(member:string|null,conflicts:string[]=[]){if(!pick)return;
  let override=false,reason='';
  if(member&&conflicts.length&&pick.service.status==='published'){const why=prompt(`Esta pessoa tem conflito (${conflicts.map(conflictLabel).join(', ')}). Para escalar mesmo assim, explique o motivo (mínimo de 10 caracteres):`);if(why===null)return;if(why.trim().length<10){setNotice('Explique o motivo com pelo menos 10 caracteres.');return}override=true;reason=why.trim()}
  setBusy(true);setError('');
  try{await call('/api/scales-board',{},{unit:unitId,action:'assign',data:{service:pick.service.id,role:pick.row.role,ordinal:pick.row.ordinal,member,version:pick.service.version,...(override?{override,reason}:{})}});
   setNotice(member?(conflicts.length?'Escalado com aviso: '+conflicts.map(conflictLabel).join(', ')+'.':'Escalado.'):'Vaga liberada.');setPick(null);setSuggestions(null);setSearch('');setReload(x=>x+1)}
  catch(e){setError(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}
 async function publish(override=false,reason=''){if(!selected.length)return;setBusy(true);setError('');
  try{const r=await call<{published:string[];failed:{id:string;code:string;error:string}[]}>('/api/scales-board',{},{unit:unitId,action:'publish',data:{services:selected,...(override?{override,reason}:{})}});
   setNotice(boardPublishMessage(r));setSelected(r.failed.map(f=>f.id));setReload(x=>x+1);
   if(!override&&r.failed.some(f=>/scale_conflict/.test(f.error))){const why=prompt('Algumas escalas têm conflitos marcados no quadro. Para publicar mesmo assim, explique o motivo (mínimo de 10 caracteres). Cancele para revisar antes.');if(why&&why.trim().length>=10){setBusy(false);await publish(true,why.trim());return}}}
  catch(e){setError(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}

 const services=board?.services||[],rows=board?.rows||[];
 const publishable=services.filter(s=>s.canPublish);
 return <section className="sb" aria-labelledby="sb-title">
  <div className="sb-head"><div><h2 id="sb-title">Quadro de montagem</h2><p>Funções nas linhas e cultos nas colunas. Clique numa vaga para escolher quem serve. Rascunhos podem ser publicados juntos.</p></div>
   <div className="sb-tools"><div className="sb-seg" role="group" aria-label="Período">{periods.map(([v,l])=><button key={v} type="button" aria-pressed={days===v} onClick={()=>setDays(v)}>{l}</button>)}</div>
    {teams.length>1&&<label>Equipe<select value={team} onChange={e=>setTeam(e.target.value)}><option value="">Todas</option>{teams.map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select></label>}
    {!!publishable.length&&<button type="button" className="sb-primary" disabled={busy||!selected.length} onClick={()=>void publish()}>Publicar selecionadas ({selected.length})</button>}</div></div>
  {error&&<p className="sb-error" role="alert">{error}</p>}
  {notice&&<p className="sb-notice" role="status">{notice}</p>}
  {!board?!error&&<p className="sb-muted">Carregando o quadro…</p>:!services.length?<p className="sb-empty">Nenhum culto com vagas neste período. Crie as escalas em Calendário e escalas.</p>:
   <div className="sb-scroll"><table className="sb-grid">
    <thead><tr><th scope="col" className="sb-corner">Função</th>{services.map(s=><th scope="col" key={s.id}>
     <span className="sb-date">{formatInZone(s.startsAt,s.timezone,{weekday:'short',day:'2-digit',month:'2-digit'})}</span>
     <span className="sb-time">{formatInZone(s.startsAt,s.timezone,{hour:'2-digit',minute:'2-digit'})}</span>
     <b title={s.title}>{s.title}</b>
     <span className={'sb-status '+s.status}>{s.status==='draft'?'Rascunho':'Publicada'}{s.open?` · ${s.open} aberta${s.open>1?'s':''}`:''}</span>
     {s.canPublish&&<label className="sb-check"><input type="checkbox" checked={selected.includes(s.id)} onChange={e=>setSelected(x=>e.target.checked?[...x,s.id]:x.filter(y=>y!==s.id))}/>Publicar</label>}
    </th>)}</tr></thead>
    <tbody>{rows.map((r,i)=><tr key={r.role+r.ordinal}>
     <th scope="row">{(i===0||rows[i-1].team!==r.team)&&<small>{r.teamName}</small>}<span>{r.roleName}{rows.filter(x=>x.role===r.role).length>1?` ${r.ordinal}`:''}</span></th>
     {services.map(s=>{const c=cells.get(key(s.id,r.role,r.ordinal));
      if(!c)return <td key={s.id} className="sb-none" aria-label="Sem esta vaga">—</td>;
      const locked=!r.canAssign||s.started||(s.status==='published'&&!!c.member);
      const cls='sb-cell'+(c.member?' filled':' open')+(c.conflicts.length?' warn':'')+(c.response?' r-'+c.response:'');
      return <td key={s.id}><button type="button" className={cls} disabled={locked||busy} onClick={()=>{setNotice('');setError('');setSearch('');setSuggestions(null);setPick({service:s,row:r,cell:c})}}
       title={c.conflicts.map(conflictLabel).join(', ')||undefined}>
       {c.member?<><b>{c.name}</b>{c.conflicts.length>0&&<em>⚠ {c.conflicts.map(conflictLabel).join(', ')}</em>}{c.response&&<em className="resp">{responseLabel[c.response]||c.response}</em>}</>:<span>+ Escalar</span>}
      </button></td>})}
    </tr>)}</tbody></table></div>}
  {pick&&<div className="sb-overlay" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget&&!busy)setPick(null)}}><aside className="sb-panel" role="dialog" aria-modal="true" aria-labelledby="sb-pick-title">
   <div className="sb-panel-head"><div><p>{formatInZone(pick.service.startsAt,pick.service.timezone,{weekday:'long',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})} · {pick.service.title}</p><h3 id="sb-pick-title">{pick.row.roleName}{rows.filter(x=>x.role===pick.row.role).length>1?` ${pick.row.ordinal}`:''} · {pick.row.teamName}</h3></div><button type="button" aria-label="Fechar" disabled={busy} onClick={()=>setPick(null)}>×</button></div>
   {pick.cell?.member&&<div className="sb-current"><span>Escalado: <b>{pick.cell.name}</b></span>{pick.service.status==='draft'&&<button type="button" disabled={busy} onClick={()=>void assign(null)}>Tirar da vaga</button>}</div>}
   <label className="sb-search">Buscar na equipe<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nome" maxLength={100}/></label>
   {suggestions===null?<p className="sb-muted">Buscando sugestões…</p>:!suggestions.length?<p className="sb-muted">Ninguém habilitado para esta função. Habilite integrantes em Equipes e funções.</p>:
    <ul className="sb-list">{suggestions.map(p=><li key={p.id} className={p.conflicts.length?'warn':''}><div><b>{p.name}</b><small>{p.recent?`Serviu ${p.recent}× nos últimos 30 dias`:'Não serviu nos últimos 30 dias'}</small>{p.conflicts.length>0&&<em>⚠ {p.conflicts.map(conflictLabel).join(', ')}</em>}</div>
     <button type="button" disabled={busy||p.conflicts.includes('duplicate')||p.id===pick.cell?.member} onClick={()=>void assign(p.id,p.conflicts)}>{p.id===pick.cell?.member?'Escalado':'Escolher'}</button></li>)}</ul>}
   {pick.service.status==='published'&&<p className="sb-muted">Culto já publicado: a pessoa escolhida recebe o convite na hora.</p>}
  </aside></div>}
 </section>;
}
