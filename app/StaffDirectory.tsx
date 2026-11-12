'use client';
import {useMinistryLanguage} from './MinistryLanguage';
import {useEffect,useMemo,useState,type FormEvent} from 'react';
import UserSheet,{roleLabels} from './UserSheet';
import './staff-directory.css';
type Staff={id:string;person_id?:string|null;name:string;email:string;phone?:string|null;role:string;status:string;unit_access:{unit_id:string;role:string;include_children:boolean}[]};
type Unit={id:string;name:string};
const roles=['admin','pastor','secretary','leader','finance','member','viewer'];
const statusLabels:Record<string,string>={active:'Ativo',suspended:'Suspenso',pending:'Pendente',revoked:'Sem acesso'};
const levelLabels:Record<string,string>={read:'Leitura',manage:'Gestão',admin:'Administração local'};
const pageSize=20;
const fold=(v:string)=>v.normalize('NFD').replace(/[̀-ͯ]/g,'').toLocaleLowerCase('pt-BR');

/** Configurações › Usuários e permissões: lista em tabela e ficha do usuário (dados, igrejas e permissões). */
export default function StaffDirectory(){
 const {t}=useMinistryLanguage();
 const[users,setUsers]=useState<Staff[]>([]),[units,setUnits]=useState<Unit[]>([]),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[revision,setRevision]=useState(0),[currentId,setCurrentId]=useState('');
 const[query,setQuery]=useState(''),[roleFilter,setRoleFilter]=useState(''),[page,setPage]=useState(1),[openId,setOpenId]=useState(''),[exporting,setExporting]=useState(false),[creating,setCreating]=useState(false),[loaded,setLoaded]=useState(false);
 const tenant=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';
 const url=(path:string)=>path+(tenant?'?tenant='+encodeURIComponent(tenant):'');
 async function call(path:string,method='GET',body?:unknown){const r=await fetch(url(path),{method,headers:body?{'content-type':'application/json'}:undefined,body:body?JSON.stringify(body):undefined,cache:'no-store'});const d=await r.json() as {error?:string;users?:Staff[];units?:Unit[];current?:{id:string}};if(!r.ok)throw Error(d.error||'Não foi possível concluir.');return d}
 useEffect(()=>{let current=true;call('/api/users').then(a=>{if(current){setUsers(a.users||[]);setUnits(a.units||[]);setCurrentId(a.current?.id||'');setLoaded(true)}}).catch(e=>{if(current){setNotice(e.message);setLoaded(true)}});return()=>{current=false}
  // eslint-disable-next-line react-hooks/exhaustive-deps
 },[tenant,revision]);
 async function action(fn:()=>Promise<unknown>,ok='Alteração salva.'){setBusy(true);setNotice('');try{await fn();setRevision(x=>x+1);setNotice(ok)}catch(e){setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}
 async function grant(user:Staff,event:FormEvent<HTMLFormElement>){event.preventDefault();const data=new FormData(event.currentTarget),unit=String(data.get('unitId')||'');await action(()=>call('/api/users/unit-access','PATCH',{userId:user.id,entries:unit?[{unitId:unit,level:data.get('level'),includeChildren:data.get('children')==='on'}]:[]}),'Igrejas de acesso atualizadas.')}
 const unitName=(id:string)=>units.find(u=>u.id===id)?.name||'Igreja';
 const churches=(u:Staff)=>u.unit_access.length?u.unit_access.map(g=>unitName(g.unit_id)+(g.include_children?' e filhas':'')).join(', '):['owner','admin','pastor'].includes(u.role)?'Todas as igrejas':'—';
 const filtered=useMemo(()=>{const q=fold(query.trim());return users.filter(u=>(!roleFilter||u.role===roleFilter)&&(!q||fold(u.name+' '+u.email).includes(q)))},[users,query,roleFilter]);
 const pages=Math.max(1,Math.ceil(filtered.length/pageSize)),current=Math.min(page,pages),shown=filtered.slice((current-1)*pageSize,current*pageSize);
 const open=users.find(u=>u.id===openId)||null;
 /** Planilha com todas as pessoas do filtro atual (não só a página), gerada no navegador. */
 async function exportExcel(){setExporting(true);setNotice('');try{
  const {default:ExcelJS}=await import('exceljs');const book=new ExcelJS.Workbook();const sheet=book.addWorksheet('Usuários');
  sheet.columns=[{header:'Pessoa',key:'name',width:32},{header:'E-mail',key:'email',width:34},{header:'Celular',key:'phone',width:18},{header:'Perfil de acesso',key:'role',width:24},{header:'Igrejas',key:'churches',width:34},{header:'Situação',key:'status',width:12},{header:'Cadastro de membro',key:'person',width:20}];
  sheet.getRow(1).font={bold:true};
  // Texto começando com =, +, - ou @ vira texto puro, para não ser lido como fórmula.
  const safe=(v:string)=>/^[=+\-@]/.test(v)?"'"+v:v;
  for(const u of filtered)sheet.addRow({name:safe(u.name),email:safe(u.email),phone:safe(u.phone||''),role:roleLabels[u.role]||u.role,churches:safe(churches(u)),status:statusLabels[u.status]||u.status,person:u.person_id?'Vinculado':'Sem vínculo'});
  const blob=new Blob([await book.xlsx.writeBuffer()],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
  const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='usuarios-'+new Date().toISOString().slice(0,10)+'.xlsx';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);
 }catch{setNotice('Não foi possível gerar a planilha. Tente de novo.')}finally{setExporting(false)}}

 const done=(msg:string)=>{setNotice(msg);setRevision(x=>x+1)};
 if(creating)return <main className="content staff-dir"><UserSheet units={units} currentId={currentId} close={()=>setCreating(false)} saved={msg=>{done(msg);setCreating(false)}}/></main>;
 if(open)return <main className="content staff-dir">
  {notice&&<p className="staff-notice" role="status">{notice}</p>}
  <UserSheet key={open.id} membershipId={open.id} units={units} currentId={currentId} unitAccess={open.unit_access} close={()=>setOpenId('')} saved={done}>
   <section className="staff-card"><header><h2>Igrejas de acesso</h2><span className={'staff-status '+open.status}>{statusLabels[open.status]||open.status}</span></header>
    <p className="staff-help">{open.unit_access.length?'Acessos atuais: '+open.unit_access.map(g=>`${unitName(g.unit_id)} (${levelLabels[g.role]||g.role}${g.include_children?', com filhas':''})`).join(' · '):['owner','admin','pastor'].includes(open.role)?'Dono, administradores e pastores gerais já alcançam todas as igrejas.':'Nenhuma igreja explícita.'}</p>
    <form className="staff-grid" onSubmit={e=>void grant(open,e)}><label>Igreja<select name="unitId"><option value="">Retirar acessos explícitos</option>{units.map(unit=><option key={unit.id} value={unit.id}>{unit.name}</option>)}</select></label><label>Nível<select name="level"><option value="read">Leitura</option><option value="manage">Gestão</option><option value="admin">Administração local</option></select></label><label className="staff-check"><input type="checkbox" name="children"/>Incluir igrejas filhas</label><button type="submit" className="staff-secondary" disabled={busy}>Substituir acessos</button></form>
    {open.role!=='owner'&&open.id!==currentId&&<div className="staff-actions"><button type="button" className={open.status==='active'?'staff-danger':'staff-secondary'} disabled={busy} onClick={()=>{if(open.status!=='active'||confirm(`Suspender o acesso de ${open.name}? A pessoa não entra mais no painel até ser reativada.`))void action(()=>call('/api/users','PATCH',{id:open.id,role:open.role,status:open.status==='active'?'suspended':'active'}),open.status==='active'?'Acesso suspenso.':'Acesso reativado.')}}>{open.status==='active'?'Suspender acesso':'Reativar acesso'}</button></div>}
   </section>
  </UserSheet>
 </main>;

 return <main className="content staff-dir">
  <header className="staff-head"><div><h1>{t('usuarios')}</h1><p>Quem acessa o painel, o que pode fazer e em quais igrejas.</p></div><button type="button" className="staff-primary" onClick={()=>{setNotice('');setCreating(true)}}>Novo usuário</button></header>
  {notice&&<p className="staff-notice" role="status">{notice}</p>}
  <section className="staff-card staff-list"><div className="staff-toolbar"><label>Pesquisar<input type="search" value={query} placeholder="Nome ou e-mail" onChange={e=>{setQuery(e.target.value);setPage(1)}}/></label><label>Perfil de acesso<select value={roleFilter} onChange={e=>{setRoleFilter(e.target.value);setPage(1)}}><option value="">Todos</option><option value="owner">{roleLabels.owner}</option>{roles.map(r=><option key={r} value={r}>{roleLabels[r]}</option>)}</select></label><span>{filtered.length} {filtered.length===1?'usuário':'usuários'}</span><button type="button" className="staff-secondary" disabled={exporting||!filtered.length} onClick={()=>void exportExcel()}>{exporting?'Gerando planilha…':'Exportar para Excel'}</button></div>
   {!loaded?<p className="staff-help">Carregando usuários…</p>:!filtered.length?<p className="staff-help">Nenhum usuário encontrado.</p>:<table className="staff-table"><thead><tr><th>Pessoa</th><th>E-mail</th><th>Celular</th><th>Perfil de acesso</th><th>Igrejas</th><th>Situação</th></tr></thead>
    <tbody>{shown.map(u=><tr key={u.id} onClick={()=>{setOpenId(u.id);setNotice('')}}><td data-label="Pessoa"><button type="button" onClick={e=>{e.stopPropagation();setOpenId(u.id);setNotice('')}}>{u.name}</button></td><td data-label="E-mail">{u.email}</td><td data-label="Celular">{u.phone||'—'}</td><td data-label="Perfil">{roleLabels[u.role]||u.role}</td><td data-label="Igrejas">{churches(u)}</td><td data-label="Situação"><span className={'staff-status '+u.status}>{statusLabels[u.status]||u.status}</span></td></tr>)}</tbody></table>}
   {pages>1&&<footer className="staff-pages"><span>{(current-1)*pageSize+1}–{Math.min(current*pageSize,filtered.length)} de {filtered.length} pessoas</span><div><button type="button" disabled={current===1} onClick={()=>setPage(current-1)}>Anterior</button><b>Página {current} de {pages}</b><button type="button" disabled={current===pages} onClick={()=>setPage(current+1)}>Próxima</button></div></footer>}
  </section>
 </main>
}
