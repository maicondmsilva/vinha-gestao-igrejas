'use client';
import {useEffect,useState,type FormEvent,type ReactNode} from 'react';
import UserPermissions from './UserPermissions';
import {brazilStates,genders} from '../shared/brazil-registration';
import './user-sheet.css';

type Unit={id:string;name:string};
type Sheet={membership:{id:string;role:string;status:string;unit_id:string|null;version:string;editable:boolean;password_change_required:boolean};
 person:null|{id:string;full_name:string;phone:string|null;email:string|null;gender:string|null;cpf:string|null;birth_date:string|null;marriage_date:string|null;baptism_date:string|null;is_pastor:boolean;unit_id:string|null;
  address:null|{postal_code:string|null;street:string|null;number:string|null;complement:string|null;district:string|null;city:string|null;state:string|null}};
 groups:{cells:string[];teams:string[];kids:string[]};hasLogin:boolean;email:string|null};
type Found={person:string;name:string;email:string|null;phone:string|null;cpf_masked:string|null;unit:string|null;hasLogin:boolean;membership:string|null;membership_status:string|null;version:string};
type Form={name:string;phone:string;email:string;password:string;role:string;unit:string;
 postal_code:string;street:string;number:string;complement:string;district:string;city:string;state:string;
 gender:string;cpf:string;birth_date:string;marriage_date:string;baptism_date:string;is_pastor:boolean};

const roles=['admin','pastor','secretary','leader','finance','member','viewer'];
export const roleLabels:Record<string,string>={owner:'Dono',admin:'Administrador',pastor:'Pastor',secretary:'Secretaria',leader:'Líder',finance:'Tesouraria',member:'Membro (usuário do app)',viewer:'Somente leitura'};
const statusLabels:Record<string,string>={active:'Ativo',suspended:'Suspenso',pending:'Pendente',revoked:'Sem acesso'};
const addressKeys=['postal_code','street','number','complement','district','city','state'] as const;
const extraKeys=['gender','cpf','birth_date','marriage_date','baptism_date'] as const;
const empty:Form={name:'',phone:'',email:'',password:'',role:'member',unit:'',postal_code:'',street:'',number:'',complement:'',district:'',city:'',state:'',gender:'',cpf:'',birth_date:'',marriage_date:'',baptism_date:'',is_pastor:false};
const initials=(n:string)=>n.trim().split(/\s+/).filter(Boolean).slice(0,2).map(p=>p[0]!.toUpperCase()).join('')||'?';

function tenantUrl(path:string){const t=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';return path+(t?(path.includes('?')?'&':'?')+'tenant='+encodeURIComponent(t):'')}
async function call<T>(path:string,method='GET',body?:unknown):Promise<T>{
 const r=await fetch(tenantUrl(path),{method,headers:body?{'content-type':'application/json'}:undefined,body:body?JSON.stringify(body):undefined,cache:'no-store'});
 const d=await r.json().catch(()=>({})) as T&{error?:string};
 if(!r.ok)throw Error(d.error||'Não foi possível concluir.');
 return d;
}
function fromSheet(s:Sheet):Form{const p=s.person,a=p?.address;return{...empty,name:p?.full_name||'',phone:p?.phone||'',email:s.email||p?.email||'',role:s.membership.role,unit:s.membership.unit_id||p?.unit_id||'',
 postal_code:a?.postal_code||'',street:a?.street||'',number:a?.number||'',complement:a?.complement||'',district:a?.district||'',city:a?.city||'',state:a?.state||'',
 gender:p?.gender||'',cpf:p?.cpf||'',birth_date:p?.birth_date||'',marriage_date:p?.marriage_date||'',baptism_date:p?.baptism_date||'',is_pastor:!!p?.is_pastor}}

/** Configurações › Usuários e permissões: ficha que edita o mesmo cadastro do membro (Conta, Endereço, Informações adicionais, Grupos e Permissões). */
export default function UserSheet({membershipId,units,currentId,unitAccess=[],close,saved,children}:{membershipId?:string;units:Unit[];currentId?:string;unitAccess?:{unit_id:string}[];close:()=>void;saved:(msg:string)=>void;children?:ReactNode}){
 const[sheet,setSheet]=useState<Sheet|null>(null),[found,setFound]=useState<Found|null>(null),[picking,setPicking]=useState(!membershipId);
 const[form,setForm]=useState<Form>(empty),[busy,setBusy]=useState(false),[error,setError]=useState(''),[q,setQ]=useState(''),[results,setResults]=useState<Found[]|null>(null),[reload,setReload]=useState(0);
 useEffect(()=>{if(!membershipId)return;let live=true;call<Sheet>('/api/users/'+membershipId).then(s=>{if(live){setError('');setSheet(s);setForm(fromSheet(s))}}).catch(e=>{if(live)setError(e.message)});return()=>{live=false}},[membershipId,reload]);
 const set=<K extends keyof Form>(k:K,v:Form[K])=>setForm(f=>({...f,[k]:v}));
 const isNew=!membershipId,hasLogin=sheet?.hasLogin||found?.hasLogin||false,owner=sheet?.membership.role==='owner',self=!!membershipId&&membershipId===currentId;
 const editable=isNew||!!sheet?.membership.editable||self;

 async function search(e:FormEvent){e.preventDefault();if(q.trim().length<2){setError('Digite ao menos 2 letras do nome, e-mail ou CPF.');return}setError('');setBusy(true);try{setResults((await call<{items:Found[]}>('/api/users/search?q='+encodeURIComponent(q.trim()))).items)}catch(err){setError(err instanceof Error?err.message:'Falha de conexão.')}finally{setBusy(false)}}
 function pick(f:Found|null){setFound(f);setPicking(false);setError('');setForm(f?{...empty,name:f.name,email:f.email||'',phone:f.phone||'',unit:units[0]?.id||''}:{...empty,name:/@|\d{3}/.test(q)?'':q.trim(),email:q.includes('@')?q.trim():'',unit:units[0]?.id||''})}

 function body(){
  // Ficha completa: envia tudo. Pessoa vinda da busca: só o que foi preenchido, para não apagar dados do cadastro.
  const full=!!sheet,address:Record<string,string>={},extra:Record<string,string|boolean|null>={};
  for(const k of addressKeys)if(full||form[k])address[k]=form[k];
  for(const k of extraKeys)if(full||form[k])extra[k]=form[k]||null;
  if(full||form.is_pastor)extra.is_pastor=form.is_pastor;
  return{...(found?{person:found.person,version:found.version}:{}),...(sheet?{version:sheet.membership.version}:{}),role:form.role,unit:form.unit||null,
   account:{name:form.name,phone:form.phone,email:form.email,password:form.password},
   ...(Object.keys(address).length?{address}:{}),...(Object.keys(extra).length?{extra}:{})};
 }
 async function save(e:FormEvent){e.preventDefault();setError('');
  if(form.password&&form.password.length<8){setError('A senha precisa ter pelo menos 8 caracteres.');return}
  if(isNew&&!hasLogin&&!form.password){setError('Informe uma senha para o primeiro acesso. A pessoa troca no primeiro login.');return}
  setBusy(true);try{
   if(sheet)await call('/api/users/'+sheet.membership.id,'PATCH',body());else await call('/api/users','POST',body());
   saved(isNew?'Usuário criado. '+(hasLogin?'A pessoa entra com a senha que já usa.':'Passe a senha para a pessoa; ela troca no primeiro acesso.'):'Ficha salva.');
   if(sheet){set('password','');setReload(x=>x+1)}else close();
  }catch(err){setError(err instanceof Error?err.message:'Falha de conexão.')}finally{setBusy(false)}}
 async function remove(){if(!sheet)return;if(!confirm(`Excluir o usuário ${form.name}?\n\nO acesso dele é retirado e, se não tiver acesso em outra igreja, a conta de login é apagada: para voltar, ele cria uma conta nova no app.\n\nO cadastro de membro e os lançamentos continuam em Pessoas.`))return;setBusy(true);setError('');
  try{const r=await call<{accountClosed?:boolean;error?:string}>('/api/users/'+sheet.membership.id,'DELETE');saved(r?.error||(r?.accountClosed?'Usuário excluído e conta de login apagada. O cadastro de membro e os lançamentos continuam em Pessoas.':'Acesso retirado nesta igreja. A conta continua porque a pessoa tem acesso em outra igreja ou à plataforma.'));close()}catch(err){setError(err instanceof Error?err.message:'Falha de conexão.')}finally{setBusy(false)}}

 if(picking)return <section className="us" aria-labelledby="us-title">
  <nav className="us-crumbs" aria-label="Caminho"><button type="button" onClick={close}>Usuários</button><span>›</span><b>Novo usuário</b></nav>
  <div className="us-head"><i aria-hidden>+</i><div><h2 id="us-title">Novo usuário</h2><p>Procure a pessoa em Pessoas. Se ela ainda não tem cadastro, crie aqui mesmo.</p></div></div>
  <form className="us-card us-search" onSubmit={search}><label>Nome, e-mail ou CPF<input autoFocus value={q} onChange={e=>setQ(e.target.value)} placeholder="Ex.: Maria Souza" maxLength={80}/></label><button type="submit" className="us-primary" disabled={busy}>{busy?'Buscando…':'Buscar'}</button></form>
  {error&&<p className="us-error" role="alert">{error}</p>}
  {results&&<div className="us-card"><h3>{results.length?'Encontramos em Pessoas':'Ninguém encontrado com essa busca'}</h3>
   <ul className="us-results">{results.map(r=><li key={r.person}><i aria-hidden>{initials(r.name)}</i><div><b>{r.name}</b><small>{[r.email,r.cpf_masked,r.unit].filter(Boolean).join(' · ')||'Sem e-mail e CPF'}</small>
    <span className="us-tags">{r.hasLogin?<em className="ok">Já tem login do app</em>:<em>Sem login</em>}{r.membership&&r.membership_status!=='revoked'&&<em className="warn">Já é usuário</em>}</span></div>
    <button type="button" className="us-secondary" disabled={!!r.membership&&r.membership_status!=='revoked'} onClick={()=>pick(r)}>{r.membership&&r.membership_status!=='revoked'?'Já tem acesso':'Usar este cadastro'}</button></li>)}</ul>
   <button type="button" className="us-link" onClick={()=>pick(null)}>Cadastrar pessoa nova</button></div>}
 </section>;

 if(membershipId&&!sheet)return <section className="us"><nav className="us-crumbs" aria-label="Caminho"><button type="button" onClick={close}>Usuários</button></nav>{error?<p className="us-error" role="alert">{error}</p>:<p className="us-help">Abrindo a ficha…</p>}</section>;

 const status=sheet?.membership.status;
 return <section className="us" aria-labelledby="us-title">
  <nav className="us-crumbs" aria-label="Caminho"><button type="button" onClick={close}>Usuários</button><span>›</span><b>{form.name||'Novo usuário'}</b></nav>
  <div className="us-head"><i aria-hidden>{initials(form.name)}</i><div><h2 id="us-title">{form.name||'Novo usuário'}</h2>
   <p>{roleLabels[form.role]||form.role}{status&&<span className={'us-status '+status}>{statusLabels[status]||status}</span>}{sheet?.membership.password_change_required&&<span className="us-status pending">Troca de senha pendente</span>}</p></div></div>
  {error&&<p className="us-error" role="alert">{error}</p>}
  <form onSubmit={save}><fieldset disabled={busy||!editable} className="us-blocks">
   <section className="us-card"><h3>Conta</h3>
    <div className="us-grid">
     <label className="us-wide">Nome<input required minLength={2} maxLength={160} value={form.name} onChange={e=>set('name',e.target.value)}/></label>
     <label>Igreja principal<select value={form.unit} onChange={e=>set('unit',e.target.value)}><option value="">Selecione</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
     <label>Tipo de usuário<select value={form.role} disabled={owner||self} onChange={e=>set('role',e.target.value)}>{owner&&<option value="owner">{roleLabels.owner}</option>}{roles.map(r=><option key={r} value={r}>{roleLabels[r]}</option>)}</select></label>
     <label>Celular<input inputMode="tel" maxLength={30} value={form.phone} onChange={e=>set('phone',e.target.value)} placeholder="(11) 90000-0000"/></label>
     <label>E-mail<input type="email" required maxLength={254} value={form.email} onChange={e=>set('email',e.target.value)}/><small>É o e-mail de login no app e no painel.</small></label>
     <label className="us-wide">Senha<input type="password" autoComplete="new-password" minLength={8} maxLength={72} value={form.password} onChange={e=>set('password',e.target.value)} placeholder={hasLogin?'••••••••':'Mínimo de 8 caracteres'}/>
      <small>{hasLogin?'Deixe em branco para manter a senha atual. Se digitar uma nova, a pessoa troca no próximo acesso.':'A pessoa usa esta senha no primeiro acesso e cria a dela em seguida.'}</small></label>
    </div></section>
   <section className="us-card"><h3>Endereço</h3>
    <div className="us-grid">
     <label>CEP<input inputMode="numeric" maxLength={9} value={form.postal_code} onChange={e=>set('postal_code',e.target.value)}/></label>
     <label className="us-wide">Rua<input maxLength={160} value={form.street} onChange={e=>set('street',e.target.value)}/></label>
     <label>Número<input maxLength={20} value={form.number} onChange={e=>set('number',e.target.value)}/></label>
     <label>Complemento<input maxLength={80} value={form.complement} onChange={e=>set('complement',e.target.value)}/></label>
     <label>Bairro<input maxLength={80} value={form.district} onChange={e=>set('district',e.target.value)}/></label>
     <label>Cidade<input maxLength={80} value={form.city} onChange={e=>set('city',e.target.value)}/></label>
     <label>UF<select value={form.state} onChange={e=>set('state',e.target.value)}><option value="">—</option>{brazilStates.map(([v,l])=><option key={v} value={v}>{v} — {l}</option>)}</select></label>
    </div></section>
   <section className="us-card"><h3>Informações adicionais</h3>
    <div className="us-grid">
     <label>Sexo<select value={form.gender} onChange={e=>set('gender',e.target.value)}><option value="">Não informado</option>{genders.map(g=><option key={g} value={g}>{g}</option>)}</select></label>
     <label>CPF<input inputMode="numeric" maxLength={14} value={form.cpf} onChange={e=>set('cpf',e.target.value)}/></label>
     <label>Nascimento<input type="date" value={form.birth_date} onChange={e=>set('birth_date',e.target.value)}/></label>
     <label>Data de casamento<input type="date" value={form.marriage_date} onChange={e=>set('marriage_date',e.target.value)}/></label>
     <label>Data de batismo<input type="date" value={form.baptism_date} onChange={e=>set('baptism_date',e.target.value)}/></label>
     <label className="us-check"><input type="checkbox" checked={form.is_pastor} onChange={e=>set('is_pastor',e.target.checked)}/>É pastor</label>
    </div></section>
   <section className="us-card"><h3>Grupos</h3>
    {!sheet?<p className="us-help">Os grupos aparecem depois de salvar.</p>:!sheet.groups.cells.length&&!sheet.groups.teams.length?<p className="us-help">Não participa de células nem de equipes de escala.</p>:
     <dl className="us-groups">{!!sheet.groups.cells.length&&<><dt>Células</dt><dd>{sheet.groups.cells.map(c=><span key={c}>{c}</span>)}</dd></>}{!!sheet.groups.teams.length&&<><dt>Equipes de escala</dt><dd>{sheet.groups.teams.map(c=><span key={c}>{c}</span>)}</dd></>}</dl>}
   </section>
  </fieldset>
  {!editable&&<p className="us-help">Você pode ver esta ficha, mas só quem tem um tipo de usuário acima do dela pode alterá-la.</p>}
  <div className="us-actions">
   <button type="button" className="us-secondary" onClick={close}>Voltar</button>
   {sheet&&!owner&&!self&&editable&&<button type="button" className="us-danger" disabled={busy} onClick={()=>void remove()}>Excluir usuário</button>}
   {editable&&<button type="submit" className="us-primary" disabled={busy}>{busy?'Salvando…':isNew?'Criar usuário':'Salvar'}</button>}
  </div></form>
  {sheet&&children}
  {sheet&&!owner&&<UserPermissions key={sheet.membership.id+':'+sheet.membership.version} user={{id:sheet.membership.id,name:form.name,email:form.email,role:sheet.membership.role,unit_access:unitAccess}} units={units} close={close} embedded/>}
 </section>;
}
