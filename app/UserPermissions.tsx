'use client';
import {useEffect,useMemo,useState} from 'react';
import {groupKinds,permissionActions,userTypeName,type GroupOption,type PermissionAction,type PermissionGrant,type PermissionSection,type PermissionTemplate} from './lib/permissions';
import './user-permissions.css';

type Unit={id:string;name:string};
type User={id:string;name:string;email:string;role:string;unit_access:{unit_id:string}[];team?:boolean};
type Custom={id:string;name:string;description:string;items:Record<string,PermissionAction[]>};
/** Uma seção: em quais igrejas vale ('' = todo o ministério), o que pode fazer e, se houver, quais grupos. */
type Row={enabled:boolean;units:string[];children:boolean;actions:PermissionAction[];kind:string;groups:string[]};
const tenantQuery=()=>{const t=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';return t?'tenant='+encodeURIComponent(t):''};
async function api<T>(query:string,body?:unknown):Promise<T>{
 const q=[query,tenantQuery()].filter(Boolean).join('&');
 const r=await fetch('/api/permissions'+(q?'?'+q:''),body?{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}:{cache:'no-store'});
 const d=await r.json().catch(()=>({})) as T&{error?:string};
 if(!r.ok)throw Error(d.error||'Não foi possível concluir.');
 return d;
}
const sorted=(a:string[])=>[...a].sort().join();
const empty:Row={enabled:false,units:[''],children:true,actions:[],kind:'',groups:[]};
function rowFrom(list:PermissionGrant[]):Row{
 if(!list.length)return empty;
 const g=list[0]!;
 return {enabled:true,units:[...new Set(list.map(x=>x.unit_id||''))],children:g.include_children,actions:[...new Set(list.flatMap(x=>x.actions))],kind:g.group_kind||'',groups:g.group_ids||[]};
}
const same=(a:Row,b:Row)=>a.enabled===b.enabled&&(!a.enabled||(sorted(a.units)===sorted(b.units)&&a.children===b.children&&sorted(a.actions)===sorted(b.actions)&&a.kind===b.kind&&sorted(a.groups)===sorted(b.groups)));
/** Ação inicial ao marcar uma seção: "Ver" quando existe, senão a primeira que a seção oferece. */
export const firstAction=(s:Pick<PermissionSection,'actions'>):PermissionAction[]=>s.actions.includes('view')?['view']:s.actions.slice(0,1);

function UnitChips({units,value,onChange,disabled,label}:{units:Unit[];value:string[];onChange:(v:string[])=>void;disabled?:boolean;label:string}){
 const all=value.includes('');
 return <div className="user-perms-units" role="group" aria-label={label}>
  <label className={all?'on':''}><input type="checkbox" checked={all} disabled={disabled} onChange={()=>onChange([''])}/>Todo o ministério</label>
  {units.map(u=>{const on=!all&&value.includes(u.id);return <label key={u.id} className={on?'on':''}><input type="checkbox" checked={on} disabled={disabled} onChange={()=>{const base=value.filter(x=>x);const next=on?base.filter(x=>x!==u.id):[...base,u.id];onChange(next.length?next:[''])}}/>{u.name}</label>})}
 </div>;
}

/** Configurações › Usuários e permissões: seções, igrejas onde valem, ações, modelos e "selecionar todos". */
export default function UserPermissions({user,units,close,embedded=false}:{user:User;units:Unit[];close:()=>void;embedded?:boolean}){
 const [sections,setSections]=useState<PermissionSection[]>([]),[templates,setTemplates]=useState<PermissionTemplate[]>([]),[custom,setCustom]=useState<Custom[]>([]),[grants,setGrants]=useState<PermissionGrant[]>([]);
 const [rows,setRows]=useState<Record<string,Row>>({}),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[template,setTemplate]=useState(''),[templateUnits,setTemplateUnits]=useState<string[]>(['']),[groupOptions,setGroupOptions]=useState<Record<string,GroupOption[]>>({});
 const owner=user.role==='owner';
 const loadCustom=()=>api<{items:Custom[]}>('custom=1').then(d=>setCustom(d.items||[])).catch(()=>setCustom([]));
 useEffect(()=>{let live=true;Promise.all([api<{sections:PermissionSection[];templates:PermissionTemplate[]}>(''),owner?Promise.resolve({grants:[] as PermissionGrant[]}):api<{grants:PermissionGrant[]}>('membership='+user.id),owner?Promise.resolve({}):api<Record<string,GroupOption[]>>('groups=1').catch(()=>({}))])
  .then(([c,l,g])=>{if(!live)return;setSections(c.sections);setTemplates(c.templates);setGrants(l.grants);setGroupOptions(g as Record<string,GroupOption[]>)}).catch(e=>{if(live)setError(e.message)});
  if(!owner)void loadCustom();
  return()=>{live=false}},[user.id,owner]);
 const saved=useMemo(()=>Object.fromEntries(sections.map(s=>[s.code,rowFrom(grants.filter(g=>g.permission===s.code))])),[sections,grants]);
 const current=(code:string)=>rows[code]||saved[code]||empty;
 const areas=[...new Set(sections.map(s=>s.area))];
 const type=userTypeName(user.role,!!user.team||grants.length>0);
 function edit(code:string,patch:Partial<Row>){setRows(r=>({...r,[code]:{...current(code),...patch}}))}
 const fullRow=(s:PermissionSection,base:Row):Row=>({...base,enabled:true,actions:[...s.actions],units:base.enabled?base.units:['']});
 function selectAll(list:PermissionSection[],on:boolean){setRows(r=>{const next={...r};for(const s of list){if(s.owner_only&&!owner)continue;const base=r[s.code]||saved[s.code]||empty;next[s.code]=on?fullRow(s,base):{...base,enabled:false}}return next})}
 const allOn=(list:PermissionSection[])=>list.length>0&&list.every(s=>{const r=current(s.code);return r.enabled&&s.actions.every(a=>r.actions.includes(a))});
 async function run(body:unknown,ok:string){setBusy(true);setError('');setNotice('');try{const d=await api<{grants:PermissionGrant[]}>('',body);setGrants(d.grants);setRows({});setNotice(ok)}catch(e){setError(e instanceof Error?e.message:'Não foi possível salvar.')}finally{setBusy(false)}}
 async function saveAll(){
  const changed=sections.filter(s=>rows[s.code]&&!same(rows[s.code]!,saved[s.code]!));
  if(!changed.length){setNotice('Nada para salvar.');return}
  setBusy(true);setError('');setNotice('');
  let last:PermissionGrant[]=grants,ok=0;const fails:string[]=[];
  for(const s of changed){const r=rows[s.code]!,before=saved[s.code]!;
   try{
    // Só as ações que a seção oferece (evita a recusa "ações inválidas").
    const actions=r.actions.filter(a=>s.actions.includes(a));
    if(r.enabled&&!actions.length)throw Error('escolha ao menos uma ação');
    if(r.enabled&&r.kind&&!r.groups.length)throw Error('marque ao menos um grupo ou escolha "Sem limite"');
    const keep=r.enabled?r.units:[];
    for(const u of before.enabled?before.units:[])if(!keep.includes(u))last=(await api<{grants:PermissionGrant[]}>('',{action:'remove',data:{membership:user.id,permission:s.code,unit:u}})).grants;
    for(const u of keep)last=(await api<{grants:PermissionGrant[]}>('',{action:'set',data:{membership:user.id,permission:s.code,unit:u,includeChildren:r.children,actions,...(r.kind?{groupKind:r.kind,groups:r.groups}:{})}})).grants;
    ok++;
   }catch(e){fails.push(`${s.label}: ${e instanceof Error?e.message:'não salvou'}`)}
  }
  setGrants(last);setRows(rw=>Object.fromEntries(Object.entries(rw).filter(([k])=>fails.some(f=>f.startsWith((sections.find(x=>x.code===k)?.label||'')+':')))));
  setBusy(false);
  if(ok)setNotice(`${ok} ${ok===1?'seção salva':'seções salvas'}.`);
  if(fails.length)setError('Não salvou: '+fails.join(' · '));
 }
 async function applyTemplate(){
  if(!template)return;
  if(template.startsWith('c:'))return run({action:'apply_custom_template',data:{membership:user.id,template:template.slice(2),units:templateUnits.filter(Boolean)}},'Modelo aplicado. Ajuste o que precisar.');
  setBusy(true);setError('');setNotice('');
  try{let last=grants;for(const u of templateUnits)last=(await api<{grants:PermissionGrant[]}>('',{action:'apply_template',data:{membership:user.id,template:template.slice(2),unit:u}})).grants;setGrants(last);setRows({});setNotice('Modelo aplicado. Ajuste o que precisar.')}
  catch(e){setError(e instanceof Error?e.message:'Não foi possível aplicar.')}finally{setBusy(false)}
 }
 async function saveAsTemplate(){
  const items=Object.fromEntries(sections.map(s=>[s.code,current(s.code)] as const).filter(([,r])=>r.enabled&&r.actions.length).map(([c,r])=>[c,r.actions.filter(a=>sections.find(s=>s.code===c)!.actions.includes(a))]).filter(([,a])=>(a as string[]).length));
  if(!Object.keys(items).length){setError('Marque ao menos uma seção para criar o modelo.');return}
  const name=window.prompt('Nome do modelo (ex.: Recepção, Mídia, Tesouraria):','')?.trim();if(!name)return;
  const description=window.prompt('Descrição curta (opcional):','')?.trim()||'';
  setBusy(true);setError('');try{await api('',{action:'save_custom_template',data:{name,description,items}});await loadCustom();setNotice(`Modelo "${name}" salvo. Ele aparece em "Aplicar modelo" para todos os usuários.`)}catch(e){setError(e instanceof Error?e.message:'Não foi possível salvar o modelo.')}finally{setBusy(false)}
 }
 async function deleteTemplate(){
  const c=custom.find(x=>'c:'+x.id===template);if(!c||!confirm(`Apagar o modelo "${c.name}"? Quem já recebeu continua com as permissões.`))return;
  setBusy(true);try{await api('',{action:'delete_custom_template',data:{id:c.id}});await loadCustom();setTemplate('');setNotice('Modelo apagado.')}catch(e){setError(e instanceof Error?e.message:'Não foi possível apagar.')}finally{setBusy(false)}
 }
 const dirty=sections.some(s=>rows[s.code]&&!same(rows[s.code]!,saved[s.code]!));
 const chosen=template.startsWith('c:')?custom.find(x=>'c:'+x.id===template):undefined,builtIn=template.startsWith('b:')?templates.find(t=>'b:'+t.code===template):undefined;
 const head=embedded?<header className="user-perms-head embedded"><div><h2 id="user-perms-title">Permissões</h2><p>Marque as seções, em quais igrejas valem e o que a pessoa pode fazer. Quem recebe alguma permissão passa a ser <b>Equipe</b>.</p></div></header>
  :<header className="user-perms-head"><div><p className="user-perms-over">Usuários e permissões</p><h2 id="user-perms-title">{user.name}</h2><p>{user.email}</p></div><button type="button" className="user-perms-close" aria-label="Fechar" disabled={busy} onClick={()=>{if(!dirty||confirm('Descartar as alterações não salvas?'))close()}}>×</button></header>;
 const body=<section className={'user-perms'+(embedded?' embedded':'')} role={embedded?'region':'dialog'} aria-modal={embedded?undefined:true} aria-labelledby="user-perms-title">
   {head}
   {!embedded&&<div className="user-perms-type"><span>Tipo de usuário</span><b>{type}</b><small>{owner?'O dono tem acesso a tudo e não recebe permissões avulsas.':'As permissões abaixo somam-se ao tipo atual.'}</small></div>}
   {error&&<p className="user-perms-alert" role="alert">{error}</p>}{notice&&<p className="user-perms-notice" role="status">{notice}</p>}
   {!owner&&<>
    <div className="user-perms-template">
     <label>Aplicar modelo<select value={template} onChange={e=>setTemplate(e.target.value)} disabled={busy}><option value="">Escolha um modelo</option>
      {custom.length>0&&<optgroup label="Modelos da igreja">{custom.map(t=><option key={t.id} value={'c:'+t.id}>{t.name}</option>)}</optgroup>}
      <optgroup label="Modelos prontos">{templates.map(t=><option key={t.code} value={'b:'+t.code}>{t.label}</option>)}</optgroup></select></label>
     <button type="button" className="user-perms-secondary" disabled={busy||!template||dirty} title={dirty?'Salve ou descarte as alterações antes':undefined} onClick={()=>void applyTemplate()}>Aplicar</button>
     {chosen&&<button type="button" className="user-perms-link" disabled={busy} onClick={()=>void deleteTemplate()}>Apagar modelo</button>}
     <button type="button" className="user-perms-link" disabled={busy} onClick={()=>void saveAsTemplate()}>Salvar seleção como modelo</button>
     {template&&<><p>{chosen?.description||builtIn?.description||''}</p><UnitChips units={units} value={templateUnits} onChange={setTemplateUnits} disabled={busy} label="Igrejas onde o modelo vale"/></>}
    </div>
    {!sections.length&&!error?<p className="user-perms-loading">Carregando permissões…</p>:<div className="user-perms-matrix">
     <label className="user-perms-all"><input type="checkbox" checked={allOn(sections.filter(s=>owner||!s.owner_only))} disabled={busy} onChange={e=>selectAll(sections,e.target.checked)}/>Selecionar todas as seções e ações</label>
     {areas.map(area=>{const list=sections.filter(s=>s.area===area);return <section key={area} className="user-perms-area"><h3>{area}<label className="user-perms-area-all"><input type="checkbox" checked={allOn(list.filter(s=>owner||!s.owner_only))} disabled={busy} onChange={e=>selectAll(list,e.target.checked)}/>Selecionar todos</label></h3>
      <div className="user-perms-rows">{list.map(s=>{const r=current(s.code),changed=rows[s.code]&&!same(rows[s.code]!,saved[s.code]!);return <div key={s.code} className={'user-perms-row'+(r.enabled?' on':'')+(changed?' changed':'')}>
       <label className="user-perms-section"><input type="checkbox" checked={r.enabled} disabled={busy||(s.owner_only&&!owner)} onChange={e=>edit(s.code,e.target.checked?{enabled:true,actions:r.actions.filter(a=>s.actions.includes(a)).length?r.actions:firstAction(s)}:{enabled:false})}/><span>{s.label}{s.owner_only&&<small>só o dono concede</small>}</span></label>
       <div className="user-perms-scope">
        {r.enabled&&<UnitChips units={units} value={r.units} onChange={v=>edit(s.code,{units:v})} disabled={busy} label={'Igrejas: '+s.label}/>}
        {r.enabled&&!r.units.includes('')&&<label className="user-perms-children"><input type="checkbox" checked={r.children} disabled={busy} onChange={e=>edit(s.code,{children:e.target.checked})}/>Incluir filhas</label>}
        {s.group_kinds.length>0&&r.enabled&&<div className="user-perms-groups"><select aria-label={'Limitar a: '+s.label} value={r.kind} disabled={busy} onChange={e=>edit(s.code,{kind:e.target.value,groups:[]})}><option value="">Sem limite de grupo</option>{groupKinds.filter(([k])=>s.group_kinds.includes(k)).map(([k,label])=><option key={k} value={k}>Só {label.toLowerCase()} escolhidas</option>)}</select>{r.kind&&<details className="user-perms-group-list" open={!r.groups.length}><summary>{r.groups.length?`${r.groups.length} ${r.groups.length===1?'grupo marcado':'grupos marcados'}`:'Marque os grupos'}</summary>{(groupOptions[r.kind]||[]).length?(groupOptions[r.kind]||[]).map(g=><label key={g.id}><input type="checkbox" checked={r.groups.includes(g.id)} disabled={busy} onChange={e=>edit(s.code,{groups:e.target.checked?[...r.groups,g.id]:r.groups.filter(x=>x!==g.id)})}/>{g.name}<small>{units.find(u=>u.id===g.unit)?.name||''}</small></label>):<p>Nenhum grupo ativo deste tipo.</p>}</details>}</div>}
       </div>
       <fieldset className="user-perms-actions" disabled={busy||!r.enabled}><legend className="sr-only">Autorizado a ({s.label})</legend>{permissionActions.filter(([a])=>s.actions.includes(a)).map(([a,label])=><label key={a} className={r.actions.includes(a)?'on':''}><input type="checkbox" checked={r.actions.includes(a)} onChange={e=>edit(s.code,{actions:e.target.checked?[...r.actions,a]:r.actions.filter(x=>x!==a)})}/>{label}</label>)}</fieldset>
      </div>})}</div></section>})}
    </div>}
    <footer className="user-perms-foot"><button type="button" className="user-perms-danger" disabled={busy||!grants.length||dirty} onClick={()=>{if(confirm('Retirar todas as permissões deste usuário? O tipo de usuário continua.'))void run({action:'clear',data:{membership:user.id}},'Permissões retiradas.')}}>Limpar permissões</button><span>{busy?'Salvando…':dirty?'Alterações não salvas':'Tudo salvo'}</span><button type="button" className="user-perms-secondary" disabled={busy||!dirty} onClick={()=>{setRows({});setError('')}}>Desfazer</button><button type="button" className="user-perms-primary" disabled={busy||!dirty} onClick={()=>void saveAll()}>Salvar permissões</button></footer>
   </>}
  </section>;
 if(embedded)return body;
 return <div className="user-perms-backdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget&&!busy&&!dirty)close()}}>{body}</div>;
}
