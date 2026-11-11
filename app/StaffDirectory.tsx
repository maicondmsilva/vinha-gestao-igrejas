'use client';
import {useMinistryLanguage} from './MinistryLanguage';
import {useEffect,useMemo,useState,type FormEvent} from 'react';
import UserPermissions from './UserPermissions';
import './staff-directory.css';
type Staff={id:string;person_id?:string|null;name:string;email:string;phone?:string|null;role:string;status:string;unit_access:{unit_id:string;role:string;include_children:boolean}[]};
type Invitation={id:string;email:string;full_name:string;role:string;status:string;expires_at:string};
type Unit={id:string;name:string};
const roles=['admin','pastor','secretary','leader','finance','member','viewer'];
const roleLabels:Record<string,string>={owner:'Dono',admin:'Administrador',pastor:'Pastor',secretary:'Secretaria',leader:'Líder',finance:'Tesouraria',member:'Membro (usuário do app)',viewer:'Somente leitura'};
const statusLabels:Record<string,string>={active:'Ativo',suspended:'Suspenso',pending:'Pendente',revoked:'Revogado',accepted:'Aceito',expired:'Expirado'};
const levelLabels:Record<string,string>={read:'Leitura',manage:'Gestão',admin:'Administração local'};
const pageSize=20;
const fold=(v:string)=>v.normalize('NFD').replace(/[̀-ͯ]/g,'').toLocaleLowerCase('pt-BR');

/** Configurações › Usuários e permissões: lista em tabela e ficha do usuário (dados, igrejas e permissões). */
export default function StaffDirectory(){
 const {t}=useMinistryLanguage();
 const[users,setUsers]=useState<Staff[]>([]),[invites,setInvites]=useState<Invitation[]>([]),[units,setUnits]=useState<Unit[]>([]),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[link,setLink]=useState(''),[revision,setRevision]=useState(0);
 const[query,setQuery]=useState(''),[roleFilter,setRoleFilter]=useState(''),[page,setPage]=useState(1),[openId,setOpenId]=useState(''),[exporting,setExporting]=useState(false),[inviting,setInviting]=useState(false),[loaded,setLoaded]=useState(false);
 const tenant=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';
 const url=(path:string)=>path+(tenant?'?tenant='+encodeURIComponent(tenant):'');
 async function call(path:string,method='GET',body?:unknown){const r=await fetch(url(path),{method,headers:body?{'content-type':'application/json'}:undefined,body:body?JSON.stringify(body):undefined,cache:'no-store'});const d=await r.json() as {error?:string;users?:Staff[];invites?:Invitation[];units?:Unit[];activationUrl?:string};if(!r.ok)throw Error(d.error||'Não foi possível concluir.');return d}
 useEffect(()=>{let current=true;Promise.all([call('/api/users'),call('/api/users/invites')]).then(([a,b])=>{if(current){setUsers(a.users||[]);setInvites(b.invites||[]);setUnits(b.units||[]);setLoaded(true)}}).catch(e=>{if(current){setNotice(e.message);setLoaded(true)}});return()=>{current=false}
  // eslint-disable-next-line react-hooks/exhaustive-deps
 },[tenant,revision]);
 async function action(fn:()=>Promise<unknown>,ok='Alteração salva.'){setBusy(true);setNotice('');try{await fn();setRevision(x=>x+1);setNotice(ok)}catch(e){setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}
 async function invite(event:FormEvent<HTMLFormElement>){event.preventDefault();const data=new FormData(event.currentTarget);await action(async()=>{const result=await call('/api/users/invites','POST',Object.fromEntries(data));setLink(result.activationUrl||'')},'Convite criado. Copie o link e envie para a pessoa.')}
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

 if(open)return <main className="content staff-dir"><nav className="staff-crumbs" aria-label="Caminho"><button type="button" onClick={()=>setOpenId('')}>Usuários</button><span>›</span><b>{open.name}</b></nav>
  {notice&&<p className="staff-notice" role="status">{notice}</p>}
  <section className="staff-card"><header><h2>Dados da conta</h2><span className={'staff-status '+open.status}>{statusLabels[open.status]||open.status}</span></header>
   <div className="staff-grid"><label>Nome<input readOnly value={open.name}/></label><label>E-mail<input readOnly value={open.email}/></label>
    <label>Perfil de acesso<select value={open.role} disabled={busy||open.role==='owner'} onChange={e=>void action(()=>call('/api/users','PATCH',{id:open.id,role:e.target.value,status:open.status}),'Perfil de acesso atualizado.')}>{open.role==='owner'&&<option value="owner">{roleLabels.owner}</option>}{roles.map(r=><option key={r} value={r}>{roleLabels[r]}</option>)}</select></label>
    <label>Cadastro de membro<input readOnly value={open.person_id?'Vinculado ao cadastro de membro':'Sem vínculo com cadastro de membro'}/></label></div>
   <p className="staff-help">O perfil de acesso define o acesso padrão. As permissões abaixo somam acessos específicos, seção por seção.</p>
   {open.role!=='owner'&&<div className="staff-actions"><button type="button" className={open.status==='active'?'staff-danger':'staff-secondary'} disabled={busy} onClick={()=>{if(open.status!=='active'||confirm(`Suspender o acesso de ${open.name}? A pessoa não entra mais no painel até ser reativada.`))void action(()=>call('/api/users','PATCH',{id:open.id,role:open.role,status:open.status==='active'?'suspended':'active'}),open.status==='active'?'Acesso suspenso.':'Acesso reativado.')}}>{open.status==='active'?'Suspender acesso':'Reativar acesso'}</button></div>}
  </section>
  <section className="staff-card"><header><h2>Igrejas de acesso</h2></header>
   <p className="staff-help">{open.unit_access.length?'Acessos atuais: '+open.unit_access.map(g=>`${unitName(g.unit_id)} (${levelLabels[g.role]||g.role}${g.include_children?', com filhas':''})`).join(' · '):['owner','admin','pastor'].includes(open.role)?'Dono, administradores e pastores gerais já alcançam todas as igrejas.':'Nenhuma igreja explícita.'}</p>
   <form className="staff-grid" onSubmit={e=>void grant(open,e)}><label>Igreja<select name="unitId"><option value="">Retirar acessos explícitos</option>{units.map(unit=><option key={unit.id} value={unit.id}>{unit.name}</option>)}</select></label><label>Nível<select name="level"><option value="read">Leitura</option><option value="manage">Gestão</option><option value="admin">Administração local</option></select></label><label className="staff-check"><input type="checkbox" name="children"/>Incluir igrejas filhas</label><button type="submit" className="staff-secondary" disabled={busy}>Substituir acessos</button></form>
  </section>
  <UserPermissions key={open.id+':'+revision} user={open} units={units} close={()=>setOpenId('')} embedded/>
  <div className="staff-actions"><button type="button" className="staff-secondary" onClick={()=>setOpenId('')}>Voltar para usuários</button></div>
 </main>;

 return <main className="content staff-dir">
  <header className="staff-head"><div><h1>{t('usuarios')}</h1><p>Quem acessa o painel, o que pode fazer e em quais igrejas.</p></div><button type="button" className="staff-primary" onClick={()=>setInviting(v=>!v)} aria-expanded={inviting}>{inviting?'Fechar convite':'Convidar pessoa'}</button></header>
  {notice&&<p className="staff-notice" role="status">{notice}</p>}
  {inviting&&<section className="staff-card"><header><h2>Convidar pessoa</h2></header><form className="staff-grid" onSubmit={invite}><label>Nome<input name="name" required minLength={2} maxLength={160}/></label><label>E-mail<input name="email" type="email" required maxLength={254}/></label><label>Perfil de acesso<select name="role">{roles.map(role=><option key={role} value={role}>{roleLabels[role]}</option>)}</select></label><label>Igreja<select name="unitId" required><option value="">Selecione</option>{units.map(unit=><option key={unit.id} value={unit.id}>{unit.name}</option>)}</select></label><button type="submit" className="staff-primary" disabled={busy}>Criar convite</button></form><p className="staff-help">O convite gera um link pessoal. Envie por um canal autorizado; ele não promove contas existentes nem reativa acessos suspensos.</p>{link&&<div className="staff-grid"><label>Link pessoal<input readOnly value={link}/></label><button type="button" className="staff-secondary" onClick={()=>void navigator.clipboard.writeText(link).then(()=>setNotice('Link copiado.'),()=>setNotice('Não foi possível copiar. Selecione o link e copie manualmente.'))}>Copiar link</button></div>}</section>}
  <section className="staff-card staff-list"><div className="staff-toolbar"><label>Pesquisar<input type="search" value={query} placeholder="Nome ou e-mail" onChange={e=>{setQuery(e.target.value);setPage(1)}}/></label><label>Perfil de acesso<select value={roleFilter} onChange={e=>{setRoleFilter(e.target.value);setPage(1)}}><option value="">Todos</option><option value="owner">{roleLabels.owner}</option>{roles.map(r=><option key={r} value={r}>{roleLabels[r]}</option>)}</select></label><span>{filtered.length} {filtered.length===1?'usuário':'usuários'}</span><button type="button" className="staff-secondary" disabled={exporting||!filtered.length} onClick={()=>void exportExcel()}>{exporting?'Gerando planilha…':'Exportar para Excel'}</button></div>
   {!loaded?<p className="staff-help">Carregando usuários…</p>:!filtered.length?<p className="staff-help">Nenhum usuário encontrado.</p>:<table className="staff-table"><thead><tr><th>Pessoa</th><th>E-mail</th><th>Celular</th><th>Perfil de acesso</th><th>Igrejas</th><th>Situação</th></tr></thead>
    <tbody>{shown.map(u=><tr key={u.id} onClick={()=>{setOpenId(u.id);setNotice('')}}><td data-label="Pessoa"><button type="button" onClick={e=>{e.stopPropagation();setOpenId(u.id);setNotice('')}}>{u.name}</button></td><td data-label="E-mail">{u.email}</td><td data-label="Celular">{u.phone||'—'}</td><td data-label="Perfil">{roleLabels[u.role]||u.role}</td><td data-label="Igrejas">{churches(u)}</td><td data-label="Situação"><span className={'staff-status '+u.status}>{statusLabels[u.status]||u.status}</span></td></tr>)}</tbody></table>}
   {pages>1&&<footer className="staff-pages"><span>{(current-1)*pageSize+1}–{Math.min(current*pageSize,filtered.length)} de {filtered.length} pessoas</span><div><button type="button" disabled={current===1} onClick={()=>setPage(current-1)}>Anterior</button><b>Página {current} de {pages}</b><button type="button" disabled={current===pages} onClick={()=>setPage(current+1)}>Próxima</button></div></footer>}
  </section>
  {!!invites.length&&<details className="staff-card staff-invites"><summary>Convites recentes ({invites.length})</summary><ul>{invites.map(invite=><li key={invite.id}><span><b>{invite.full_name}</b> · {invite.email} · {roleLabels[invite.role]||invite.role} · {statusLabels[invite.status]||invite.status} · expira em {new Date(invite.expires_at).toLocaleDateString('pt-BR')}</span>{invite.status==='pending'&&<button type="button" className="staff-secondary" disabled={busy} onClick={()=>void action(()=>call('/api/users/invites','PATCH',{id:invite.id,action:'revoke'}),'Convite cancelado.')}>Cancelar convite</button>}</li>)}</ul></details>}
 </main>
}
