'use client';
import './worship-workspace.css';
import {useCallback,useEffect,useMemo,useState,type FormEvent} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {chartLine,keyOptions,songStatus,timeSignatures,transposeChart} from './lib/worship';

type SongRow={id:string;title:string;artist:string;original_key:string;bpm:number|null;time_signature:string;tags:string[];status:string;version:number;last_played:string|null;times_played:number;has_chart:boolean};
type SongList={items:SongRow[];total:number;page:number;pageSize:number;tags:string[];canCreate:boolean;canEdit:boolean;canDelete:boolean};
type Song={id:string;title:string;artist:string;original_key:string;bpm:number|null;time_signature:string;chart:string;links:{video?:string;audio?:string;chart?:string};tags:string[];status:string;notes:string;version:number;history:{service:string;date:string;key:string}[];canEdit:boolean};
type Service={id:string;title:string;starts_at:string;status:string;setlist:'draft'|'published'|null;songs:number;canEdit:boolean};
type Item={song:string;title:string;artist:string;original_key:string;key:string;bpm:number|null;minister:string|null;minister_name?:string|null;notes:string;has_chart:boolean};
type Setlist={service:{id:string;title:string;starts_at:string;arrival_at:string;location:string;status:string};setlist:{id:string;status:string;notes:string;version:number;updated_at:string}|null;items:Item[];team:{person:string;name:string;role:string;team:string}[];canEdit:boolean;canPublish:boolean};

async function call<T>(query:Record<string,string>|null,body?:unknown):Promise<T>{
 const url=settingsUrl('/api/worship'+(query?'?'+new URLSearchParams(query):''));
 const r=await fetch(url,body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{cache:'no-store'});
 const d=await r.json().catch(()=>({})) as T&{error?:string};
 if(!r.ok)throw Error(d.error||'Não foi possível concluir.');
 return d;
}
const dayMonth=(iso:string)=>{const d=new Date(iso);return{day:d.toLocaleDateString('pt-BR',{day:'2-digit',timeZone:'America/Sao_Paulo'}),month:d.toLocaleDateString('pt-BR',{month:'short',timeZone:'America/Sao_Paulo'}).replace('.',''),week:d.toLocaleDateString('pt-BR',{weekday:'short',timeZone:'America/Sao_Paulo'}).replace('.',''),time:d.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit',timeZone:'America/Sao_Paulo'})}};
const dateLong=(iso:string)=>new Date(iso).toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long',timeZone:'America/Sao_Paulo'});
const statusLabel=(s:string)=>songStatus.find(([v])=>v===s)?.[1]||s;
const newId=()=>crypto.randomUUID();

/** Louvor: repertório do culto (ligado à Escala) e repertório de músicas da igreja. */
export default function WorshipWorkspace({unitId}:{unitId:string}){
 const [tab,setTab]=useState<'cultos'|'repertorio'>('cultos');
 const [notice,setNotice]=useState('');
 const valid=/^[0-9a-f]{8}-/i.test(unitId);
 return <div className="content wsh">
  <header className="wsh-head"><div><p>Louvor</p><h1>{tab==='cultos'?'Repertório dos cultos':'Repertório da igreja'}</h1><small>{tab==='cultos'?'Monte as músicas de cada culto da escala, com o tom do dia e quem ministra.':'Músicas, tons, cifras e referências da equipe de louvor.'}</small></div>
   <nav className="wsh-tabs" aria-label="Louvor"><button type="button" aria-pressed={tab==='cultos'} onClick={()=>setTab('cultos')}>Cultos</button><button type="button" aria-pressed={tab==='repertorio'} onClick={()=>setTab('repertorio')}>Repertório</button></nav></header>
  {notice&&<p className="wsh-notice" role="status">{notice}<button type="button" aria-label="Fechar aviso" onClick={()=>setNotice('')}>×</button></p>}
  {!valid?<p className="wsh-empty">Escolha uma igreja no topo da página para abrir o Louvor.</p>:tab==='cultos'?<Services unit={unitId} notify={setNotice}/>:<Library unit={unitId} notify={setNotice}/>}
 </div>;
}

// ---------------- Cultos ----------------
function Services({unit,notify}:{unit:string;notify:(m:string)=>void}){
 const [services,setServices]=useState<Service[]|null>(null),[error,setError]=useState(''),[open,setOpen]=useState(''),[rev,setRev]=useState(0);
 useEffect(()=>{let live=true;call<{items:Service[]}>({unit,kind:'services'}).then(d=>{if(!live)return;setServices(d.items);setOpen(o=>o||d.items.find(s=>new Date(s.starts_at)>=new Date(Date.now()-6*3600e3))?.id||d.items[0]?.id||'')}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}},[unit,rev]);
 if(error)return <p className="wsh-error" role="alert">{error}</p>;
 if(!services)return <p className="wsh-empty">Carregando cultos…</p>;
 if(!services.length)return <div className="wsh-empty-card"><b>Nenhum culto na escala</b><p>Cadastre os cultos em Escalas › Planejamento. Eles aparecem aqui para montar o repertório.</p></div>;
 return <div className="wsh-split">
  <aside className="wsh-services" aria-label="Cultos">{services.map(s=>{const d=dayMonth(s.starts_at),past=new Date(s.starts_at)<new Date();return <button key={s.id} type="button" className={'wsh-service'+(open===s.id?' on':'')+(past?' past':'')} aria-current={open===s.id} onClick={()=>setOpen(s.id)}>
   <span className="wsh-date"><b>{d.day}</b><small>{d.month}</small></span><span className="wsh-service-text"><b>{s.title}</b><small>{d.week} · {d.time}</small></span>
   <em className={'wsh-chip '+(s.setlist||'none')}>{s.setlist==='published'?`Publicado · ${s.songs}`:s.setlist==='draft'?`Rascunho · ${s.songs}`:'Sem músicas'}</em></button>})}</aside>
  {open&&<SetlistEditor key={open} unit={unit} service={open} notify={notify} changed={()=>setRev(n=>n+1)}/>}
 </div>;
}

function SetlistEditor({unit,service,notify,changed}:{unit:string;service:string;notify:(m:string)=>void;changed:()=>void}){
 const [data,setData]=useState<Setlist|null>(null),[items,setItems]=useState<Item[]>([]),[notes,setNotes]=useState(''),[dirty,setDirty]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[stage,setStage]=useState(false),[rev,setRev]=useState(0);
 useEffect(()=>{let live=true;call<Setlist>({unit,kind:'setlist',service}).then(d=>{if(!live)return;setData(d);setItems(d.items);setNotes(d.setlist?.notes||'');setDirty(false)}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}},[unit,service,rev]);
 if(error)return <section className="wsh-editor"><p className="wsh-error" role="alert">{error}</p></section>;
 if(!data)return <section className="wsh-editor"><p className="wsh-empty">Carregando repertório…</p></section>;
 const edit=data.canEdit&&data.service.status!=='cancelled';
 const change=(f:(l:Item[])=>Item[])=>{setItems(f);setDirty(true)};
 const move=(i:number,by:number)=>change(l=>{const n=[...l],j=i+by;if(j<0||j>=n.length)return l;[n[i],n[j]]=[n[j],n[i]];return n});
 async function save(){setBusy(true);setError('');try{await call(null,{unit,kind:'setlist',action:'save',data:{service,version:data!.setlist?.version||0,notes,items:items.map(i=>({song:i.song,key:i.key,minister:i.minister||'',notes:i.notes}))}});notify('Repertório salvo.');setRev(n=>n+1);changed()}catch(e){setError(e instanceof Error?e.message:'Não foi possível salvar.')}finally{setBusy(false)}}
 async function publish(action:'publish'|'unpublish'){setBusy(true);setError('');try{await call(null,{unit,kind:'setlist',action,data:{service,version:data!.setlist!.version}});notify(action==='publish'?'Repertório publicado para a equipe.':'Repertório voltou para rascunho.');setRev(n=>n+1);changed()}catch(e){setError(e instanceof Error?e.message:'Não foi possível concluir.')}finally{setBusy(false)}}
 const people=[...new Map(data.team.map(t=>[t.person,t])).values()];
 return <section className="wsh-editor" aria-labelledby="wsh-editor-title">
  <header><div><h2 id="wsh-editor-title">{data.service.title}</h2><small>{dateLong(data.service.starts_at)} · {dayMonth(data.service.starts_at).time}{data.service.location?` · ${data.service.location}`:''}</small></div>
   <span className={'wsh-chip '+(data.setlist?.status||'none')}>{data.setlist?.status==='published'?'Publicado':data.setlist?'Rascunho':'Ainda sem repertório'}</span></header>
  {data.team.length>0&&<div className="wsh-team" aria-label="Equipe escalada">{data.team.map(t=><span key={t.person+t.role}><b>{t.name}</b><small>{t.role}</small></span>)}</div>}
  {error&&<p className="wsh-error" role="alert">{error}</p>}
  <ol className="wsh-items">{items.map((it,i)=><li key={it.song+i}>
   <span className="wsh-pos">{i+1}</span>
   <div className="wsh-item-main"><b>{it.title}</b><small>{[it.artist,it.bpm?`${it.bpm} BPM`:'',it.original_key?`original ${it.original_key}`:''].filter(Boolean).join(' · ')}</small>
    {edit?<div className="wsh-item-fields"><label>Tom<select value={it.key} onChange={e=>change(l=>l.map((x,j)=>j===i?{...x,key:e.target.value}:x))}>{(keyOptions.includes(it.key)?keyOptions:[it.key,...keyOptions]).map(k=><option key={k} value={k}>{k||'—'}</option>)}</select></label>
     <label>Ministra<select value={it.minister||''} onChange={e=>change(l=>l.map((x,j)=>j===i?{...x,minister:e.target.value||null}:x))}><option value="">Não definido</option>{people.map(p=><option key={p.person} value={p.person}>{p.name}</option>)}{it.minister&&!people.some(p=>p.person===it.minister)&&<option value={it.minister}>{it.minister_name||'Pessoa anterior'}</option>}</select></label>
     <label className="wide">Observação<input value={it.notes} maxLength={500} placeholder="Ex.: intro só teclado, repetir refrão 2x" onChange={e=>change(l=>l.map((x,j)=>j===i?{...x,notes:e.target.value}:x))}/></label></div>
    :<small className="wsh-item-read">Tom <b>{it.key||'—'}</b>{it.minister_name?` · ministra ${it.minister_name}`:''}{it.notes?` · ${it.notes}`:''}</small>}</div>
   {edit&&<div className="wsh-item-actions"><button type="button" aria-label={`Subir ${it.title}`} disabled={i===0} onClick={()=>move(i,-1)}>↑</button><button type="button" aria-label={`Descer ${it.title}`} disabled={i===items.length-1} onClick={()=>move(i,1)}>↓</button><button type="button" aria-label={`Tirar ${it.title}`} onClick={()=>change(l=>l.filter((_,j)=>j!==i))}>×</button></div>}
  </li>)}</ol>
  {!items.length&&<p className="wsh-empty">{edit?'Busque abaixo as músicas deste culto.':'Nenhuma música definida ainda.'}</p>}
  {edit&&<SongPicker unit={unit} exclude={items.map(i=>i.song)} pick={s=>change(l=>[...l,{song:s.id,title:s.title,artist:s.artist,original_key:s.original_key,key:s.original_key,bpm:s.bpm,minister:null,notes:'',has_chart:s.has_chart}])}/>}
  <label className="wsh-notes">Recados para a equipe<textarea value={notes} disabled={!edit} maxLength={2000} placeholder="Ex.: ensaio sábado às 18h; chegar 1h antes" onChange={e=>{setNotes(e.target.value);setDirty(true)}}/></label>
  <footer>
   <button type="button" className="wsh-secondary" disabled={!items.length} onClick={()=>setStage(true)}>Modo palco</button>
   <span>{dirty?'Alterações não salvas':data.setlist?`Salvo em ${new Date(data.setlist.updated_at).toLocaleString('pt-BR')}`:''}</span>
   {edit&&<button type="button" className="wsh-secondary" disabled={busy||!dirty} onClick={()=>{setItems(data.items);setNotes(data.setlist?.notes||'');setDirty(false)}}>Desfazer</button>}
   {edit&&<button type="button" className="wsh-primary" disabled={busy||!dirty} onClick={()=>void save()}>{busy?'Salvando…':'Salvar'}</button>}
   {data.canPublish&&data.setlist&&!dirty&&(data.setlist.status==='published'?<button type="button" className="wsh-secondary" disabled={busy} onClick={()=>void publish('unpublish')}>Voltar a rascunho</button>:<button type="button" className="wsh-primary" disabled={busy||!items.length} onClick={()=>void publish('publish')}>Publicar para a equipe</button>)}
  </footer>
  {stage&&<StageView unit={unit} title={data.service.title} items={items} close={()=>setStage(false)}/>}
 </section>;
}

function SongPicker({unit,exclude,pick}:{unit:string;exclude:string[];pick:(s:SongRow)=>void}){
 const [q,setQ]=useState(''),[rows,setRows]=useState<SongRow[]>([]),[open,setOpen]=useState(false);
 useEffect(()=>{if(!open)return;const t=setTimeout(()=>{call<SongList>({unit,kind:'songs',search:q.trim()}).then(d=>setRows(d.items)).catch(()=>setRows([]))},250);return()=>clearTimeout(t)},[unit,q,open]);
 const list=rows.filter(r=>!exclude.includes(r.id));
 return <div className="wsh-picker"><label>Adicionar música<input value={q} placeholder="Buscar no repertório por nome ou artista" onFocus={()=>setOpen(true)} onChange={e=>{setQ(e.target.value);setOpen(true)}}/></label>
  {open&&<ul role="listbox" aria-label="Músicas do repertório">{list.slice(0,8).map(r=><li key={r.id}><button type="button" onClick={()=>{pick(r);setQ('');setOpen(false)}}><b>{r.title}</b><small>{[r.artist,r.original_key&&`tom ${r.original_key}`,r.times_played?`tocada ${r.times_played}x`:'nunca tocada'].filter(Boolean).join(' · ')}</small></button></li>)}
   {!list.length&&<li className="wsh-picker-empty">Nenhuma música encontrada. Cadastre em Repertório.</li>}<li className="wsh-picker-close"><button type="button" onClick={()=>setOpen(false)}>Fechar</button></li></ul>}
 </div>;
}

function StageView({unit,title,items,close}:{unit:string;title:string;items:Item[];close:()=>void}){
 const [charts,setCharts]=useState<Record<string,Song>>({}),[size,setSize]=useState(20);
 useEffect(()=>{let live=true;Promise.all(items.map(i=>call<Song>({unit,kind:'song',id:i.song}).catch(()=>null))).then(list=>{if(live)setCharts(Object.fromEntries(list.filter(Boolean).map(s=>[s!.id,s!])))});return()=>{live=false}},[unit,items]);
 useEffect(()=>{const k=(e:KeyboardEvent)=>{if(e.key==='Escape')close()};addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[close]);
 return <div className="wsh-stage" role="dialog" aria-modal="true" aria-label={'Modo palco: '+title}>
  <header><b>{title}</b><div><button type="button" aria-label="Diminuir letra" onClick={()=>setSize(s=>Math.max(14,s-2))}>A−</button><button type="button" aria-label="Aumentar letra" onClick={()=>setSize(s=>Math.min(40,s+2))}>A+</button><button type="button" onClick={()=>print()}>Imprimir</button><button type="button" onClick={close}>Fechar</button></div></header>
  <div className="wsh-stage-body" style={{fontSize:size}}>{items.map((it,i)=>{const s=charts[it.song];return <article key={it.song+i}><h2>{i+1}. {it.title} <small>tom {it.key||'—'}{it.minister_name?` · ${it.minister_name}`:''}</small></h2>{it.notes&&<p className="wsh-stage-note">{it.notes}</p>}
   {s?.chart?<Chart text={transposeChart(s.chart,s.original_key,it.key)}/>:<p className="wsh-stage-note">{s?'Sem cifra cadastrada.':'Carregando…'}</p>}</article>})}</div>
 </div>;
}

function Chart({text}:{text:string}){
 return <div className="wsh-chart">{text.split('\n').map((line,i)=>{const parts=chartLine(line);const hasChord=parts.some(p=>p.chord);
  return line.trim()===''?<br key={i}/>:/^\s*\{[^}]*\}\s*$|^\s*\[[^\]]*\]\s*$/.test(line)&&!hasChord?<p key={i} className="wsh-chart-section">{line.replace(/[{}[\]]/g,'').trim()}</p>
   :<p key={i} className={'wsh-chart-line'+(hasChord?' chords':'')}>{parts.map((p,j)=><span key={j}>{hasChord&&<i>{p.chord||' '}</i>}{p.text||(p.chord?' ':'')}</span>)}</p>})}</div>;
}

// ---------------- Repertório ----------------
function Library({unit,notify}:{unit:string;notify:(m:string)=>void}){
 const [search,setSearch]=useState(''),[status,setStatus]=useState('current'),[tag,setTag]=useState(''),[page,setPage]=useState(1),[data,setData]=useState<SongList|null>(null),[error,setError]=useState(''),[open,setOpen]=useState<string|null>(null),[creating,setCreating]=useState(false),[rev,setRev]=useState(0);
 const load=useCallback(()=>call<SongList>({unit,kind:'songs',search:search.trim(),status,tag,page:String(page)}),[unit,search,status,tag,page]);
 useEffect(()=>{let live=true;const t=setTimeout(()=>{load().then(d=>{if(live){setData(d);setError('')}}).catch(e=>{if(live)setError(e.message)})},200);return()=>{live=false;clearTimeout(t)}},[load,rev]);
 const pages=data?Math.max(1,Math.ceil(data.total/data.pageSize)):1;
 return <>
  <div className="wsh-toolbar"><label className="wsh-search"><span className="sr-only">Buscar música</span><input value={search} placeholder="Buscar por nome ou artista" onChange={e=>{setSearch(e.target.value);setPage(1)}}/></label>
   <select aria-label="Situação" value={status} onChange={e=>{setStatus(e.target.value);setPage(1)}}><option value="current">Ativas e em ensaio</option><option value="active">Só ativas</option><option value="rehearsal">Em ensaio</option><option value="archived">Arquivadas</option><option value="all">Todas</option></select>
   {data?.canCreate&&<button type="button" className="wsh-primary" onClick={()=>setCreating(true)}>＋ Nova música</button>}</div>
  {data&&data.tags.length>0&&<div className="wsh-tags" role="group" aria-label="Etiquetas"><button type="button" aria-pressed={!tag} onClick={()=>{setTag('');setPage(1)}}>Todas</button>{data.tags.map(t=><button key={t} type="button" aria-pressed={tag===t} onClick={()=>{setTag(t);setPage(1)}}>{t}</button>)}</div>}
  {error&&<p className="wsh-error" role="alert">{error}</p>}
  {!data?<p className="wsh-empty">Carregando repertório…</p>:!data.items.length?<div className="wsh-empty-card"><b>{search||tag?'Nenhuma música com esses filtros':'O repertório está vazio'}</b><p>{data.canCreate?'Cadastre as músicas com tom, BPM e cifra. Depois é só escolher no culto.':'Peça ao líder do louvor para cadastrar as músicas.'}</p></div>
   :<div className="wsh-songs">{data.items.map(s=><button key={s.id} type="button" className={'wsh-song '+s.status} onClick={()=>setOpen(s.id)}>
    <span className="wsh-key" aria-label={'Tom '+(s.original_key||'não informado')}>{s.original_key||'—'}</span>
    <span className="wsh-song-text"><b>{s.title}</b><small>{s.artist||'Artista não informado'}</small>
     <span className="wsh-song-meta">{s.bpm&&<em>{s.bpm} BPM</em>}{s.time_signature&&<em>{s.time_signature}</em>}{s.status!=='active'&&<em className="st">{statusLabel(s.status)}</em>}{!s.has_chart&&<em className="warn">sem cifra</em>}{s.tags.slice(0,3).map(t=><em key={t}>{t}</em>)}</span>
     <small className="wsh-played">{s.times_played?`Tocada ${s.times_played}x · última em ${new Date(s.last_played!).toLocaleDateString('pt-BR')}`:'Ainda não tocada'}</small></span></button>)}</div>}
  {data&&pages>1&&<nav className="wsh-pager" aria-label="Páginas"><button type="button" disabled={page<=1} onClick={()=>setPage(p=>p-1)}>‹ Anterior</button><span>Página {page} de {pages} · {data.total} músicas</span><button type="button" disabled={page>=pages} onClick={()=>setPage(p=>p+1)}>Próxima ›</button></nav>}
  {(open||creating)&&<SongSheet unit={unit} id={open} canDelete={!!data?.canDelete} close={()=>{setOpen(null);setCreating(false)}} saved={msg=>{notify(msg);setRev(n=>n+1);setOpen(null);setCreating(false)}}/>}
 </>;
}

function SongSheet({unit,id,canDelete,close,saved}:{unit:string;id:string|null;canDelete:boolean;close:()=>void;saved:(m:string)=>void}){
 const [song,setSong]=useState<Song|null>(null),[editing,setEditing]=useState(!id),[view,setView]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{if(!id)return;let live=true;call<Song>({unit,kind:'song',id}).then(s=>{if(live){setSong(s);setView(s.original_key)}}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}},[unit,id]);
 const blank:Song=useMemo(()=>({id:newId(),title:'',artist:'',original_key:'',bpm:null,time_signature:'4/4',chart:'',links:{},tags:[],status:'active',notes:'',version:0,history:[],canEdit:true}),[]);
 const current=song||blank;
 async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();const f=new FormData(e.currentTarget);setBusy(true);setError('');
  try{await call(null,{unit,kind:'song',action:'save',data:{id:current.id,version:current.version,title:String(f.get('title')),artist:String(f.get('artist')),originalKey:String(f.get('originalKey')),bpm:String(f.get('bpm')||''),timeSignature:String(f.get('timeSignature')),chart:String(f.get('chart')),
   links:{video:String(f.get('video')||'').trim(),audio:String(f.get('audio')||'').trim(),chart:String(f.get('chartLink')||'').trim()},tags:String(f.get('tags')||'').split(',').map(t=>t.trim()).filter(Boolean),status:String(f.get('status')),notes:String(f.get('notes')||'')}});
   saved(song?'Música atualizada.':'Música cadastrada no repertório.')}catch(err){setError(err instanceof Error?err.message:'Não foi possível salvar.')}finally{setBusy(false)}}
 async function remove(){if(!song||!confirm(`Excluir "${song.title}" do repertório?`))return;setBusy(true);setError('');try{await call(null,{unit,kind:'song',action:'delete',data:{id:song.id,version:song.version}});saved('Música excluída.')}catch(err){setError(err instanceof Error?err.message:'Não foi possível excluir.')}finally{setBusy(false)}}
 return <div className="wsh-backdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget&&!busy&&!editing)close()}}>
  <section className="wsh-sheet" role="dialog" aria-modal="true" aria-labelledby="wsh-sheet-title">
   <header><div><h2 id="wsh-sheet-title">{id?(song?.title||'Carregando…'):'Nova música'}</h2>{song&&<small>{[song.artist,song.bpm&&`${song.bpm} BPM`,song.time_signature,statusLabel(song.status)].filter(Boolean).join(' · ')}</small>}</div><button type="button" className="wsh-close" aria-label="Fechar" disabled={busy} onClick={close}>×</button></header>
   {error&&<p className="wsh-error" role="alert">{error}</p>}
   {editing?<form className="wsh-form" onSubmit={e=>void submit(e)}><fieldset disabled={busy}>
    <label className="wide">Nome da música<input name="title" required maxLength={160} defaultValue={current.title} autoFocus/></label>
    <label className="wide">Artista ou ministério<input name="artist" maxLength={160} defaultValue={current.artist}/></label>
    <label>Tom original<select name="originalKey" defaultValue={current.original_key}><option value="">Não informado</option>{keyOptions.map(k=><option key={k}>{k}</option>)}</select></label>
    <label>BPM<input name="bpm" type="number" min={20} max={300} defaultValue={current.bpm??''}/></label>
    <label>Compasso<select name="timeSignature" defaultValue={current.time_signature}>{timeSignatures.map(t=><option key={t} value={t}>{t||'—'}</option>)}</select></label>
    <label>Situação<select name="status" defaultValue={current.status}>{songStatus.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
    <label className="wide">Etiquetas<input name="tags" maxLength={300} defaultValue={current.tags.join(', ')} placeholder="adoração, celebração, ceia (separe por vírgula)"/></label>
    <label className="wide">Letra e cifra<textarea name="chart" rows={12} maxLength={20000} defaultValue={current.chart} placeholder={'Coloque os acordes entre colchetes, antes da sílaba:\n[G]Santo, [D/F#]santo, [Em]santo\n\nUse {Refrão} para marcar as partes.'}/><small>Acordes entre colchetes, como [G] ou [D/F#], são transpostos automaticamente para o tom do culto.</small></label>
    <label>Vídeo (https)<input name="video" type="url" maxLength={500} defaultValue={current.links.video||''}/></label>
    <label>Áudio (https)<input name="audio" type="url" maxLength={500} defaultValue={current.links.audio||''}/></label>
    <label className="wide">Cifra externa (https)<input name="chartLink" type="url" maxLength={500} defaultValue={current.links.chart||''}/></label>
    <label className="wide">Observações<textarea name="notes" rows={2} maxLength={1000} defaultValue={current.notes}/></label>
   </fieldset><footer>{song&&canDelete&&<button type="button" className="wsh-danger" disabled={busy} onClick={()=>void remove()}>Excluir</button>}<span/>
    <button type="button" className="wsh-secondary" disabled={busy} onClick={()=>song?setEditing(false):close()}>Cancelar</button><button type="submit" className="wsh-primary" disabled={busy}>{busy?'Salvando…':'Salvar música'}</button></footer></form>
   :song&&<div className="wsh-sheet-body">
    <div className="wsh-transpose"><label>Ver no tom<select value={view} onChange={e=>setView(e.target.value)}>{(keyOptions.includes(song.original_key)?keyOptions:[song.original_key,...keyOptions]).map(k=><option key={k} value={k}>{k||'—'}{k===song.original_key?' (original)':''}</option>)}</select></label>
     {(song.links.video||song.links.audio||song.links.chart)&&<div className="wsh-links">{song.links.video&&<a href={song.links.video} target="_blank" rel="noreferrer">Vídeo</a>}{song.links.audio&&<a href={song.links.audio} target="_blank" rel="noreferrer">Áudio</a>}{song.links.chart&&<a href={song.links.chart} target="_blank" rel="noreferrer">Cifra externa</a>}</div>}</div>
    {song.chart?<Chart text={transposeChart(song.chart,song.original_key,view)}/>:<p className="wsh-empty">Sem letra e cifra cadastradas.</p>}
    {song.notes&&<p className="wsh-song-notes">{song.notes}</p>}
    <h3>Últimas vezes no culto</h3>{song.history.length?<ul className="wsh-history">{song.history.map((h,i)=><li key={i}><b>{new Date(h.date).toLocaleDateString('pt-BR')}</b> {h.service}<small>tom {h.key||'—'}</small></li>)}</ul>:<p className="wsh-empty">Ainda não foi tocada em cultos publicados.</p>}
    {song.canEdit&&<footer><span/><button type="button" className="wsh-primary" onClick={()=>setEditing(true)}>Editar música</button></footer>}
   </div>}
  </section>
 </div>;
}
