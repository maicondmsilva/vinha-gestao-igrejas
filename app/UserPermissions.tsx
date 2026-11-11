'use client';
import {useEffect,useMemo,useState} from 'react';
import {groupKinds,permissionActions,userTypeLabel,type GroupOption,type PermissionAction,type PermissionGrant,type PermissionSection,type PermissionTemplate} from './lib/permissions';
import './user-permissions.css';

type Unit={id:string;name:string};
type User={id:string;name:string;email:string;role:string;unit_access:{unit_id:string}[]};
type Row={enabled:boolean;unit:string;children:boolean;actions:PermissionAction[];kind:string;groups:string[]};
const tenantQuery=()=>{const t=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';return t?'tenant='+encodeURIComponent(t):''};
async function api<T>(query:string,body?:unknown):Promise<T>{
 const q=[query,tenantQuery()].filter(Boolean).join('&');
 const r=await fetch('/api/permissions'+(q?'?'+q:''),body?{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}:{cache:'no-store'});
 const d=await r.json().catch(()=>({})) as T&{error?:string};
 if(!r.ok)throw Error(d.error||'Não foi possível concluir.');
 return d;
}
const rowFrom=(g?:PermissionGrant):Row=>g?{enabled:true,unit:g.unit_id||'',children:g.include_children,actions:g.actions,kind:g.group_kind||'',groups:g.group_ids||[]}:{enabled:false,unit:'',children:true,actions:[],kind:'',groups:[]};
const same=(a:Row,b:Row)=>a.enabled===b.enabled&&a.unit===b.unit&&a.children===b.children&&[...a.actions].sort().join()===[...b.actions].sort().join()&&a.kind===b.kind&&[...a.groups].sort().join()===[...b.groups].sort().join();

/** Configurações › Usuários e permissões: tipo de usuário e matriz por seção (seção, abrangência, ações). */
export default function UserPermissions({user,units,close,embedded=false}:{user:User;units:Unit[];close:()=>void;embedded?:boolean}){
 const [sections,setSections]=useState<PermissionSection[]>([]),[templates,setTemplates]=useState<PermissionTemplate[]>([]),[grants,setGrants]=useState<PermissionGrant[]>([]);
 const [rows,setRows]=useState<Record<string,Row>>({}),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[template,setTemplate]=useState(''),[templateUnit,setTemplateUnit]=useState(''),[groupOptions,setGroupOptions]=useState<Record<string,GroupOption[]>>({});
 const owner=user.role==='owner';
 useEffect(()=>{let live=true;Promise.all([api<{sections:PermissionSection[];templates:PermissionTemplate[]}>(''),owner?Promise.resolve({grants:[] as PermissionGrant[]}):api<{grants:PermissionGrant[]}>('membership='+user.id),owner?Promise.resolve({}):api<Record<string,GroupOption[]>>('groups=1').catch(()=>({}))])
  .then(([c,l,g])=>{if(!live)return;setSections(c.sections);setTemplates(c.templates);setGrants(l.grants);setGroupOptions(g as Record<string,GroupOption[]>)}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}},[user.id,owner]);
 const saved=useMemo(()=>Object.fromEntries(sections.map(s=>[s.code,rowFrom(grants.find(g=>g.permission===s.code))])),[sections,grants]);
 const current=(code:string)=>rows[code]||saved[code]||rowFrom();
 const areas=[...new Set(sections.map(s=>s.area))];
 const type=userTypeLabel(user.role,grants.length,user.unit_access.length>0);
 function edit(code:string,patch:Partial<Row>){setRows(r=>({...r,[code]:{...current(code),...patch}}))}
 async function run(body:unknown,ok:string){setBusy(true);setError('');setNotice('');try{const d=await api<{grants:PermissionGrant[]}>('',body);setGrants(d.grants);setRows({});setNotice(ok)}catch(e){setError(e instanceof Error?e.message:'Não foi possível salvar.')}finally{setBusy(false)}}
 async function saveAll(){
  const changed=sections.filter(s=>rows[s.code]&&!same(rows[s.code],saved[s.code]));
  if(!changed.length){setNotice('Nada para salvar.');return}
  setBusy(true);setError('');setNotice('');
  try{let last:PermissionGrant[]=grants;
   for(const s of changed){const r=rows[s.code],before=saved[s.code];
    if(before.enabled&&(!r.enabled||before.unit!==r.unit))last=(await api<{grants:PermissionGrant[]}>('',{action:'remove',data:{membership:user.id,permission:s.code,unit:before.unit}})).grants;
    if(r.enabled){if(!r.actions.length)throw Error(`Escolha ao menos uma ação em "${s.label}" ou desmarque a seção.`);if(r.kind&&!r.groups.length)throw Error(`Marque ao menos um grupo em "${s.label}" ou escolha "Sem limite".`);last=(await api<{grants:PermissionGrant[]}>('',{action:'set',data:{membership:user.id,permission:s.code,unit:r.unit,includeChildren:r.children,actions:r.actions,...(r.kind?{groupKind:r.kind,groups:r.groups}:{})}})).grants}}
   setGrants(last);setRows({});setNotice(`${changed.length} ${changed.length===1?'seção salva':'seções salvas'}.`);
  }catch(e){setError(e instanceof Error?e.message:'Não foi possível salvar.')}finally{setBusy(false)}
 }
 const dirty=sections.some(s=>rows[s.code]&&!same(rows[s.code],saved[s.code]));
 const head=embedded?<header className="user-perms-head embedded"><div><h2 id="user-perms-title">Permissões</h2><p>Marque as seções, onde valem e o que a pessoa pode fazer. Somam-se ao perfil de acesso; nada é retirado.</p></div></header>
  :<header className="user-perms-head"><div><p className="user-perms-over">Usuários e permissões</p><h2 id="user-perms-title">{user.name}</h2><p>{user.email}</p></div><button type="button" className="user-perms-close" aria-label="Fechar" disabled={busy} onClick={()=>{if(!dirty||confirm('Descartar as alterações não salvas?'))close()}}>×</button></header>;
 const body=<section className={'user-perms'+(embedded?' embedded':'')} role={embedded?'region':'dialog'} aria-modal={embedded?undefined:true} aria-labelledby="user-perms-title">
   {head}
   {!embedded&&<div className="user-perms-type"><span>Perfil de acesso</span><b>{type}</b><small>{owner?'O dono tem acesso a tudo e não recebe permissões avulsas.':'As permissões abaixo somam-se ao papel atual. Nenhum acesso é retirado ao conceder.'}</small></div>}
   {error&&<p className="user-perms-alert" role="alert">{error}</p>}{notice&&<p className="user-perms-notice" role="status">{notice}</p>}
   {!owner&&<>
    <div className="user-perms-template"><label>Aplicar modelo<select value={template} onChange={e=>setTemplate(e.target.value)} disabled={busy}><option value="">Escolha um modelo</option>{templates.map(t=><option key={t.code} value={t.code}>{t.label}</option>)}</select></label>
     <label>Onde vale<select value={templateUnit} onChange={e=>setTemplateUnit(e.target.value)} disabled={busy}><option value="">Todo o ministério</option>{units.map(u=><option key={u.id} value={u.id}>{u.name} e filhas</option>)}</select></label>
     <button type="button" className="user-perms-secondary" disabled={busy||!template||dirty} title={dirty?'Salve ou descarte as alterações antes':undefined} onClick={()=>void run({action:'apply_template',data:{membership:user.id,template,unit:templateUnit}},'Modelo aplicado. Ajuste o que precisar.')}>Aplicar</button>
     {template&&<p>{templates.find(t=>t.code===template)?.description}</p>}</div>
    {!sections.length&&!error?<p className="user-perms-loading">Carregando permissões…</p>:<div className="user-perms-matrix">
     {areas.map(area=><section key={area} className="user-perms-area"><h3>{area}</h3>
      <div className="user-perms-rows">{sections.filter(s=>s.area===area).map(s=>{const r=current(s.code),changed=rows[s.code]&&!same(rows[s.code],saved[s.code]);return <div key={s.code} className={'user-perms-row'+(r.enabled?' on':'')+(changed?' changed':'')}>
       <label className="user-perms-section"><input type="checkbox" checked={r.enabled} disabled={busy} onChange={e=>edit(s.code,e.target.checked?{enabled:true,actions:r.actions.length?r.actions:['view']}:{enabled:false})}/><span>{s.label}{s.owner_only&&<small>só o dono concede</small>}</span></label>
       <label className="user-perms-scope"><span className="sr-only">Onde vale: {s.label}</span><select value={r.unit} disabled={busy||!r.enabled} onChange={e=>edit(s.code,{unit:e.target.value})}><option value="">Todo o ministério</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select>{r.unit&&<label className="user-perms-children"><input type="checkbox" checked={r.children} disabled={busy||!r.enabled} onChange={e=>edit(s.code,{children:e.target.checked})}/>Incluir filhas</label>}{s.group_kinds.length>0&&<div className="user-perms-groups"><select aria-label={'Limitar a: '+s.label} value={r.kind} disabled={busy||!r.enabled} onChange={e=>edit(s.code,{kind:e.target.value,groups:[]})}><option value="">Sem limite de grupo</option>{groupKinds.filter(([k])=>s.group_kinds.includes(k)).map(([k,label])=><option key={k} value={k}>Só {label.toLowerCase()} escolhidas</option>)}</select>{r.kind&&r.enabled&&<details className="user-perms-group-list" open={!r.groups.length}><summary>{r.groups.length?`${r.groups.length} ${r.groups.length===1?'grupo marcado':'grupos marcados'}`:'Marque os grupos'}</summary>{(groupOptions[r.kind]||[]).length?(groupOptions[r.kind]||[]).map(g=><label key={g.id}><input type="checkbox" checked={r.groups.includes(g.id)} disabled={busy} onChange={e=>edit(s.code,{groups:e.target.checked?[...r.groups,g.id]:r.groups.filter(x=>x!==g.id)})}/>{g.name}<small>{units.find(u=>u.id===g.unit)?.name||''}</small></label>):<p>Nenhum grupo ativo deste tipo.</p>}</details>}</div>}</label>
       <fieldset className="user-perms-actions" disabled={busy||!r.enabled}><legend className="sr-only">Autorizado a ({s.label})</legend>{permissionActions.filter(([a])=>s.actions.includes(a)).map(([a,label])=><label key={a} className={r.actions.includes(a)?'on':''}><input type="checkbox" checked={r.actions.includes(a)} onChange={e=>edit(s.code,{actions:e.target.checked?[...r.actions,a]:r.actions.filter(x=>x!==a)})}/>{label}</label>)}</fieldset>
      </div>})}</div></section>)}
    </div>}
    <footer className="user-perms-foot"><button type="button" className="user-perms-danger" disabled={busy||!grants.length||dirty} onClick={()=>{if(confirm('Retirar todas as permissões avulsas deste usuário? O papel atual continua.'))void run({action:'clear',data:{membership:user.id}},'Permissões avulsas retiradas.')}}>Limpar permissões</button><span>{dirty?'Alterações não salvas':'Tudo salvo'}</span><button type="button" className="user-perms-secondary" disabled={busy||!dirty} onClick={()=>setRows({})}>Desfazer</button><button type="button" className="user-perms-primary" disabled={busy||!dirty} onClick={()=>void saveAll()}>Salvar permissões</button></footer>
   </>}
  </section>;
 if(embedded)return body;
 return <div className="user-perms-backdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget&&!busy&&!dirty)close()}}>{body}</div>;
}
