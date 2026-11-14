'use client';
import {useMinistryLanguage} from './MinistryLanguage';
import {useCallback,useEffect,useState} from 'react';
import './people-directory.css';
import './people-tools.css';
import type {Person} from './DashboardApp';
import MemberChurchAdmin from './MemberChurchAdmin';
import PendingProfiles from './PendingProfiles';
import PeopleBirthdays from './PeopleBirthdays';
import PeopleDuplicates from './PeopleDuplicates';
import PastoralAgenda from './PastoralAgenda';
import PeopleConverts from './PeopleConverts';
import {ageRange,ageRanges,bulkActions,exportColumns,exportFileName,exportRow,genders,journeys,type ExportPerson} from './lib/people-tools';
type Pagination={page:number;limit:number;total:number;pages:number};
type Options={cells:{id:string;name:string}[];networks:{id:string;name:string}[];tags:string[]};
type Adv={cell:string;network:string;gender:string;age:string;baptized:string;tag:string;converts:boolean};
const noAdv:Adv={cell:'',network:'',gender:'',age:'',baptized:'',tag:'',converts:false};
const advCount=(a:Adv,group:string)=>[a.cell,a.network,a.gender,a.age,a.baptized,a.tag,a.converts?'1':'',group].filter(Boolean).length;
function advParams(a:Adv){
 const p:Record<string,string>={};if(a.cell)p.cell=a.cell;if(a.network)p.network=a.network;if(a.gender)p.gender=a.gender;if(a.baptized)p.baptized=a.baptized;if(a.tag)p.tag=a.tag;if(a.converts)p.converts='1';
 return{...p,...ageRange(a.age)};
}

export default function PeopleDirectory({unitId,onAdd,onSelect,revision=0}:{unitId:string;onAdd:()=>void;onSelect:(person:Person)=>void;revision?:number}){
 const {t}=useMinistryLanguage();
 const[view,setView]=useState<'list'|'converts'|'duplicates'|'pastoral'>('list'),[dupCount,setDupCount]=useState<number|null>(null),[localRev,setLocalRev]=useState(0);
 const[q,setQ]=useState(''),[status,setStatus]=useState(''),[group,setGroup]=useState(''),[adv,setAdv]=useState<Adv>(noAdv),[options,setOptions]=useState<Options|null>(null),[showFilters,setShowFilters]=useState(false),[page,setPage]=useState(1),[people,setPeople]=useState<Person[]>([]),[pagination,setPagination]=useState<Pagination>({page:1,limit:25,total:0,pages:1}),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const[selected,setSelected]=useState<Map<string,string>>(new Map()),[exporting,setExporting]=useState(''),[notice,setNotice]=useState('');
 const tenant=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';
 const [counts,setCounts]=useState<Record<string,number|null>>({all:null,Membro:null,'Em integração':null,Visitante:null});
 const rev=revision+localRev;
 const listParams=useCallback(()=>{const params=new URLSearchParams();if(q.trim())params.set('q',q.trim());if(status)params.set('status',status);if(group.trim())params.set('group',group.trim());if(/^[0-9a-f]{8}-/i.test(unitId))params.set('unitId',unitId);if(tenant)params.set('tenant',tenant);for(const [k,v] of Object.entries(advParams(adv)))params.set(k,v);return params},[q,status,group,unitId,tenant,adv]);
 useEffect(()=>{Promise.resolve().then(()=>setPage(1))},[q,status,group,unitId,adv]);
 useEffect(()=>{Promise.resolve().then(()=>{setSelected(new Map());setAdv(noAdv);setOptions(null)})},[unitId]);
 useEffect(()=>{
  const controller=new AbortController();const timer=setTimeout(()=>{setLoading(true);setError('');const params=listParams();params.set('page',String(page));params.set('limit','25');
   fetch('/api/people?'+params,{signal:controller.signal}).then(async response=>{const data=await response.json() as {error?:string;people?:Person[];pagination?:Pagination};if(!response.ok)throw new Error(data.error||'Não foi possível carregar os membros.');if(!Array.isArray(data.people)||!data.pagination)throw new Error('Resposta inválida ao carregar membros.');if(controller.signal.aborted)return;setPeople(data.people);setPagination(data.pagination);if(page>data.pagination.pages)setPage(data.pagination.pages)}).catch(reason=>{if(!controller.signal.aborted){setPeople([]);setError(reason instanceof Error?reason.message:'Falha de conexão.')}}).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  },200);return()=>{clearTimeout(timer);controller.abort()};
 },[listParams,page,rev]);
 useEffect(()=>{const c=new AbortController();const base=new URLSearchParams({page:'1',limit:'1'});if(/^[0-9a-f]{8}-/i.test(unitId))base.set('unitId',unitId);if(tenant)base.set('tenant',tenant);
  Promise.all(['','Membro','Em integração','Visitante'].map(v=>{const p=new URLSearchParams(base);if(v)p.set('status',v);return fetch('/api/people?'+p,{signal:c.signal}).then(r=>r.ok?r.json():null).then((d:{pagination?:Pagination}|null)=>d?.pagination?.total??null).catch(()=>null)}))
   .then(([all,m,i,v])=>{if(!c.signal.aborted)setCounts({all,Membro:m,'Em integração':i,Visitante:v})});return()=>c.abort()},[unitId,tenant,rev]);
 useEffect(()=>{if(!showFilters||options||!/^[0-9a-f-]{36}$/i.test(unitId))return;const c=new AbortController();
  fetch('/api/people/options?'+new URLSearchParams({unit:unitId,...(tenant?{tenant}:{})}),{cache:'no-store',signal:c.signal}).then(r=>r.ok?r.json():null).then((d:Options|null)=>{if(d)setOptions(d)}).catch(()=>undefined);
  return()=>c.abort()},[showFilters,options,unitId,tenant]);
 const onDupCount=useCallback((n:number)=>setDupCount(n),[]);
 const pages=Array.from({length:Math.min(5,pagination.pages)},(_,index)=>Math.max(1,Math.min(page-2,pagination.pages-4))+index);
 const statusTabs:[string,string,number|null][]=[['','Todos',counts.all],['Membro','Membros',counts.Membro],['Em integração','Em integração',counts['Em integração']],['Visitante','Visitantes',counts.Visitante]];
 const initials=(p:Person)=>p.initials||p.name.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase();
 const openById=(id:string)=>void fetch('/api/people?'+new URLSearchParams({id,limit:'1',...(tenant?{tenant}:{})}),{cache:'no-store'}).then(r=>r.ok?r.json():null).then((d:{people?:Person[]}|null)=>{const p=d?.people?.[0];if(p)onSelect(p)}).catch(()=>undefined);
 const filters=advCount(adv,group);
 const pageIds=people.map(p=>p.id||'').filter(Boolean),allOnPage=pageIds.length>0&&pageIds.every(id=>selected.has(id));
 const toggle=(p:Person)=>setSelected(s=>{const n=new Map(s);if(p.id){if(n.has(p.id))n.delete(p.id);else n.set(p.id,p.name)}return n});
 const togglePage=()=>setSelected(s=>{const n=new Map(s);if(allOnPage)pageIds.forEach(id=>n.delete(id));else people.forEach(p=>{if(p.id)n.set(p.id,p.name)});return n});
 async function exportExcel(){
  setExporting('Preparando a planilha…');setNotice('');
  try{
   const rows:ExportPerson[]=[];let pageNo=1,pagesTotal=1;
   do{const params=listParams();params.set('page',String(pageNo));params.set('limit','100');
    const r=await fetch('/api/people?'+params,{cache:'no-store'});const d=await r.json() as {people?:ExportPerson[];pagination?:Pagination;error?:string};
    if(!r.ok||!d.people||!d.pagination)throw Error(d.error||'Não foi possível ler a lista.');rows.push(...d.people);pagesTotal=Math.min(d.pagination.pages,50);
    setExporting(`Lendo ${rows.length} de ${d.pagination.total} pessoas…`);pageNo++;
   }while(pageNo<=pagesTotal);
   const {default:ExcelJS}=await import('exceljs');const book=new ExcelJS.Workbook();const sheet=book.addWorksheet('Pessoas');
   sheet.columns=exportColumns.map(([key,header,width])=>({key,header,width}));sheet.getRow(1).font={bold:true};sheet.views=[{state:'frozen',ySplit:1}];
   for(const p of rows)sheet.addRow(exportRow(p));
   const blob=new Blob([await book.xlsx.writeBuffer()],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
   const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=exportFileName();a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);
   setNotice(`Planilha gerada com ${rows.length} ${rows.length===1?'pessoa':'pessoas'}${pagination.total>rows.length?` (limite de ${rows.length}; refine os filtros para o restante)`:''}.`);
  }catch(e){setNotice(e instanceof Error?e.message:'Não foi possível gerar a planilha.')}finally{setExporting('')}
 }
 const views:[typeof view,string,number|null][]=[['list','Lista',null],['converts','Novos convertidos',null],['duplicates','Duplicados',dupCount],['pastoral','Agenda pastoral',null]];
 return <div className="content pd">
  <header className="pd-head"><div><p>Comunidade</p><h1>{t('pessoas')}</h1><small>Membros, pessoas em integração e visitantes da igreja selecionada.</small></div>
   <div className="pd-actions"><a className="pd-secondary" href={`/onboarding/importar-membros${tenant?`?tenant=${encodeURIComponent(tenant)}`:''}`}>Importar planilha</a><button className="pd-primary" type="button" onClick={onAdd}>＋ Nova pessoa</button></div></header>
  <nav className="pd-views" aria-label="Visões de Pessoas">{views.map(([v,l,n])=><button key={v} type="button" aria-pressed={view===v} onClick={()=>setView(v)}>{l}{n?<b>{n}</b>:null}</button>)}</nav>
  {view==='pastoral'&&<PastoralAgenda unitId={unitId}/>}
  {view==='converts'&&<PeopleConverts unitId={unitId} onOpen={openById}/>}
  {view==='duplicates'&&<PeopleDuplicates unitId={unitId} onCount={onDupCount} onChanged={()=>setLocalRev(v=>v+1)}/>}
  {view==='list'&&<>
  <PendingProfiles/><MemberChurchAdmin/>
  <PeopleBirthdays unitId={unitId} onOpen={openById}/>
  <nav className="pd-kpis" aria-label="Filtrar por etapa">{statusTabs.map(([v,label,n])=><button key={label} type="button" aria-pressed={status===v} onClick={()=>setStatus(v)}><small>{label}</small><b>{n===null?'—':n}</b></button>)}</nav>
  <section className="pd-card">
   <div className="pd-tools"><label className="pd-search"><span className="sr-only">Buscar pessoa</span><input maxLength={100} value={q} onChange={event=>setQ(event.target.value)} placeholder="Buscar por nome, e-mail ou telefone"/></label>
    <button type="button" className={'pd-secondary'+(showFilters||filters?' on':'')} aria-expanded={showFilters} onClick={()=>setShowFilters(value=>!value)}>Filtros{filters?` (${filters})`:''}</button>
    <button type="button" className="pd-secondary" disabled={!!exporting||!pagination.total} onClick={()=>void exportExcel()}>{exporting?'Gerando…':'Exportar Excel'}</button></div>
   {showFilters&&<div className="pd-filters pd-adv">
    <label>Célula<select value={adv.cell} onChange={e=>setAdv(a=>({...a,cell:e.target.value}))}><option value="">Todas</option>{options?.cells.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
    <label>Rede<select value={adv.network} onChange={e=>setAdv(a=>({...a,network:e.target.value}))}><option value="">Todas</option>{options?.networks.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
    <label>Gênero<select value={adv.gender} onChange={e=>setAdv(a=>({...a,gender:e.target.value}))}><option value="">Todos</option>{genders.map(g=><option key={g}>{g}</option>)}</select></label>
    <label>Faixa etária<select value={adv.age} onChange={e=>setAdv(a=>({...a,age:e.target.value}))}>{ageRanges.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
    <label>Batismo<select value={adv.baptized} onChange={e=>setAdv(a=>({...a,baptized:e.target.value}))}><option value="">Todos</option><option value="sim">Batizados</option><option value="nao">Não batizados</option></select></label>
    <label>Marcador<select value={adv.tag} onChange={e=>setAdv(a=>({...a,tag:e.target.value}))}><option value="">Todos</option>{options?.tags.map(g=><option key={g}>{g}</option>)}</select></label>
    <label>Grupo ou ministério<input maxLength={160} value={group} onChange={event=>setGroup(event.target.value)}/></label>
    <label className="pd-check-filter"><input type="checkbox" checked={adv.converts} onChange={e=>setAdv(a=>({...a,converts:e.target.checked}))}/>Só novos convertidos</label>
    <button type="button" className="pd-link" onClick={()=>{setQ('');setStatus('');setGroup('');setAdv(noAdv)}}>Limpar filtros</button></div>}
   {(notice||exporting)&&<p className="pd-notice" role="status">{exporting||notice}</p>}
   {selected.size>0&&<BulkBar unitId={unitId} tenant={tenant} selected={selected} clear={()=>setSelected(new Map())} done={(msg)=>{setNotice(msg);setLocalRev(v=>v+1)}}/>}
   {error&&<div className="pd-empty" role="alert">{error}<button type="button" className="pd-link" onClick={()=>setQ(current=>current+' ')}>Tentar novamente</button></div>}
   <div className="pd-table" aria-busy={loading}>
    <div className="pd-row pd-th"><label className="pd-check"><span className="sr-only">Selecionar a página</span><input type="checkbox" checked={allOnPage} disabled={!pageIds.length} onChange={togglePage}/></label><span aria-hidden="true">Pessoa</span><span aria-hidden="true">Contato</span><span aria-hidden="true">Etapa</span><span aria-hidden="true">Grupo</span><span aria-hidden="true">Desde</span></div>
    {loading&&!people.length?<div className="pd-empty" role="status">Carregando pessoas…</div>:people.map(person=><div className={'pd-row'+(person.id&&selected.has(person.id)?' sel':'')} key={person.id}>
     <label className="pd-check"><span className="sr-only">Selecionar {person.name}</span><input type="checkbox" checked={!!person.id&&selected.has(person.id)} onChange={()=>toggle(person)}/></label>
     <button type="button" className="pd-person" onClick={()=>onSelect(person)}><i aria-hidden="true">{initials(person)}</i><span><b>{person.name}</b><small>{person.code?'Nº '+person.code:''}{person.code&&person.email?' · ':''}{person.email}</small></span></button>
     <span className="pd-contact">{person.phone||'—'}</span>
     <span className="pd-pillcell"><em className={'pd-pill '+(person.status==='Membro'?'member':person.status==='Visitante'?'visitor':'integration')}>{person.status}</em></span>
     <span className="pd-group">{person.group}</span><span className="pd-since">{person.since}</span></div>)}
    {!loading&&!error&&!people.length&&<div className="pd-empty"><b>Nenhuma pessoa encontrada</b><p>{q||status||filters?'Ajuste a busca ou os filtros.':'Cadastre a primeira pessoa ou importe uma planilha.'}</p></div>}
   </div>
   <footer className="pd-foot"><span>{loading?'Carregando…':`${pagination.total} ${pagination.total===1?'pessoa':'pessoas'}${pagination.pages>1?` · página ${page} de ${pagination.pages}`:''}`}</span>
    {pagination.pages>1&&<div><button type="button" aria-label="Página anterior" disabled={loading||page===1} onClick={()=>setPage(value=>Math.max(1,value-1))}>‹</button>{pages.map(number=><button type="button" key={number} disabled={loading} aria-current={page===number?'page':undefined} onClick={()=>setPage(number)}>{number}</button>)}<button type="button" aria-label="Próxima página" disabled={loading||page>=pagination.pages} onClick={()=>setPage(value=>Math.min(pagination.pages,value+1))}>›</button></div>}</footer>
  </section>
  </>}
 </div>
}

/** Barra de ações em lote: etapa, marcador e comunicado no aplicativo para as pessoas marcadas. */
function BulkBar({unitId,tenant,selected,clear,done}:{unitId:string;tenant:string;selected:Map<string,string>;clear:()=>void;done:(msg:string)=>void}){
 const[action,setAction]=useState(''),[value,setValue]=useState(''),[title,setTitle]=useState(''),[body,setBody]=useState(''),[reach,setReach]=useState<{people:number;devices:number}|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const [request,setRequest]=useState('');
 const ids=[...selected.keys()],n=ids.length,idsKey=ids.join(',');
 const post=useCallback(async(data:Record<string,unknown>)=>{const r=await fetch('/api/people/bulk'+(tenant?'?tenant='+encodeURIComponent(tenant):''),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({unit:unitId,ids:idsKey.split(','),...data})});
  const d=await r.json() as Record<string,unknown>&{error?:string};if(!r.ok)throw Error(d.error||'Não foi possível concluir.');return d},[unitId,tenant,idsKey]);
 useEffect(()=>{if(action!=='notify'||n>250){Promise.resolve().then(()=>setReach(null));return}
  Promise.resolve().then(()=>setRequest(r=>r||crypto.randomUUID()));
  post({action:'notify_preview'}).then(d=>setReach({people:Number(d.people)||0,devices:Number(d.devices)||0})).catch(()=>setReach(null))},[action,n,post]);
 async function apply(){
  setError('');
  if(action==='notify'&&!confirm(`Enviar agora a notificação "${title.trim()}" para ${reach?.people??0} pessoa(s) que usam o aplicativo?`))return;
  setBusy(true);
  try{
   const d=await post(action==='notify'?{action,title,body,request}:{action,value});
   const label=action==='journey'?`Etapa alterada para ${value}`:action==='tag'?`Marcador “${value.trim()}” adicionado`:action==='untag'?`Marcador “${value.trim()}” removido`:'Comunicado enviado pelo aplicativo';
   done(action==='notify'?`${label}. Acompanhe em Comunicação › Notificações.`:`${label}: ${Number(d.updated)||0} de ${n} ${n===1?'pessoa':'pessoas'} (as demais já estavam assim).`);
   setAction('');setValue('');setTitle('');setBody('');setRequest('');clear();
  }catch(e){setError(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}
 }
 const ready=action==='journey'?!!value:action==='tag'||action==='untag'?value.trim().length>0&&value.trim().length<=40:action==='notify'?n<=250&&title.trim().length>=2&&body.trim().length>=2&&!!reach?.people:false;
 return <div className="pd-bulk" role="region" aria-label="Ações em lote">
  <div className="pd-bulk-row"><b>{n} {n===1?'pessoa selecionada':'pessoas selecionadas'}</b><button type="button" className="pd-link" onClick={clear}>Limpar seleção</button>
   <label><span className="sr-only">Ação</span><select value={action} onChange={e=>{setAction(e.target.value);setValue('');setError('')}}><option value="">Escolha uma ação…</option>{bulkActions.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
   {action==='journey'&&<label><span className="sr-only">Nova etapa</span><select value={value} onChange={e=>setValue(e.target.value)}><option value="">Nova etapa…</option>{journeys.map(j=><option key={j}>{j}</option>)}</select></label>}
   {(action==='tag'||action==='untag')&&<label><span className="sr-only">Marcador</span><input value={value} maxLength={40} onChange={e=>setValue(e.target.value)} placeholder="Ex.: Retiro 2026"/></label>}
   {action&&action!=='notify'&&<button type="button" className="pd-primary" disabled={!ready||busy} onClick={()=>void apply()}>{busy?'Aplicando…':'Aplicar'}</button>}
  </div>
  {action==='notify'&&<div className="pd-bulk-notify">
   {n>250?<p className="pdup-warn">Para comunicados, selecione até 250 pessoas por vez.</p>:<p>{reach===null?'Calculando o alcance…':reach.people?`${reach.people} de ${n} pessoa(s) usam o aplicativo e vão receber a notificação.`:'Nenhuma das pessoas selecionadas usa o aplicativo com notificações ativas.'}</p>}
   <label>Título<input value={title} maxLength={65} onChange={e=>setTitle(e.target.value)} placeholder="Ex.: Ensaio extra no sábado"/></label>
   <label>Mensagem<textarea value={body} maxLength={240} rows={2} onChange={e=>setBody(e.target.value)} placeholder="Até 240 caracteres"/></label>
   <button type="button" className="pd-primary" disabled={!ready||busy} onClick={()=>void apply()}>{busy?'Enviando…':'Enviar agora'}</button>
  </div>}
  {error&&<p className="pdup-warn" role="alert">{error}</p>}
 </div>;
}
