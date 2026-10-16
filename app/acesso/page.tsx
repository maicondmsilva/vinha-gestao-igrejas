'use client';
import {useEffect,useMemo,useState} from 'react';
import '../access-flow.css';
import {createSupabaseBrowserClient,supabaseConfigured} from '../lib/supabase/client';
import {AccessContext,AccessMembership,parseAccessContext} from '../lib/supabase/access';

import {unitPreference} from '../lib/unit-integrity';

const roleLabel:Record<string,string>={owner:'Proprietário',admin:'Administrador',pastor:'Pastor',secretary:'Secretaria',finance:'Financeiro',leader:'Líder',member:'Membro',viewer:'Consulta'};

export default function AccessSelector(){
 const[data,setData]=useState<AccessContext|null>(null),[selected,setSelected]=useState(''),[unit,setUnit]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false);
 async function load(){
  try{
   if(!supabaseConfigured)throw new Error('O acesso está temporariamente indisponível. Tente novamente mais tarde.');
   {
    const supabase=createSupabaseBrowserClient(),{data:userData}=await supabase.auth.getUser();
    if(!userData.user){location.replace('/login');return}
    const{data:context,error}=await supabase.rpc('access_context');
    if(error)throw error;
    const parsed=parseAccessContext(context);
    if(!parsed.memberships.length){const response=await fetch('/api/access/pending-invite'),pending=await response.json() as {error?:string;invite?:{token?:string}};if(!response.ok)throw new Error(pending.error||'Não foi possível verificar seu convite.');location.replace(pending.invite?.token?`/ativar/${encodeURIComponent(pending.invite.token)}`:'/onboarding/novo');return}
    setData(parsed);const organizationId=parsed.preference.selected_organization_id||parsed.memberships[0].organization_id;setSelected(organizationId);const membership=parsed.memberships.find(item=>item.organization_id===organizationId)||parsed.memberships[0];setUnit(unitPreference(membership.units,parsed.preference.selected_unit_id,membership.default_unit_id));return;
   }
  }catch(error){setNotice(error instanceof Error?error.message:'Não foi possível carregar seu acesso.')}
 }
 useEffect(()=>{const task=window.setTimeout(()=>void load(),0);return()=>window.clearTimeout(task)},[]);
 const membership=useMemo(()=>data?.memberships.find(item=>item.organization_id===selected),[data,selected]);
 async function enter(){if(!membership)return;setBusy(true);setNotice('');try{
  if(unit&&!membership.units.some(item=>item.id===unit))throw new Error('Selecione uma unidade autorizada.');
  const{error}=await createSupabaseBrowserClient().rpc('set_access_context',{organization_id:selected,unit_id:unit||undefined,selected_theme:'system'});
  if(error)throw error;location.href=`/painel?tenant=${encodeURIComponent(membership.organization_slug)}`;
 }catch(error){setNotice(error instanceof Error?error.message:'Não foi possível entrar.');setBusy(false)}}

 return <main className="access-flow"><section className="access-flow-card"><a className="access-flow-brand" href="/"><i>V</i><span><b>Vinha</b><small>Acesso seguro</small></span></a><div className="access-step">AMBIENTE DE TRABALHO</div><h1>Onde você deseja entrar?</h1><p>Escolha o ministério e a unidade que serão usados nesta sessão.</p>{notice&&<div className="access-flow-notice">{notice}</div>}{data?.memberships.length?<><div className="membership-list">{data.memberships.map(item=><MembershipButton key={item.membership_id} item={item} active={selected===item.organization_id} onClick={()=>{setSelected(item.organization_id);setUnit(unitPreference(item.units,null,item.default_unit_id))}}/>)}</div>{membership&&<label className="access-unit">Unidade principal<select value={unit} onChange={event=>setUnit(event.target.value)}><option value="">Visão geral do ministério</option>{membership.units.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label>}<button className="access-primary" onClick={enter} disabled={!selected||busy}>{busy?'Preparando ambiente…':'Continuar para o painel'}</button></>:data&&<div className="access-empty"><b>Nenhuma igreja vinculada</b><p>Crie seu ministério ou peça um convite ao administrador.</p><a href="/onboarding/novo">Criar ministério</a></div>}<footer><span>Conta: {data?.email||'—'}</span><a href="/recuperar-acesso">Problemas para entrar?</a></footer></section></main>
}

function MembershipButton({item,active,onClick}:{item:AccessMembership;active:boolean;onClick:()=>void}){return <button className={active?'on':''} onClick={onClick}><i style={{background:item.primary_color}}>{item.organization_name.slice(0,1)}</i><span><b>{item.organization_name}</b><small>{roleLabel[item.role]||item.role} · {item.units.length} {item.units.length===1?'unidade':'unidades'}</small></span><em>{active?'✓':''}</em></button>}
