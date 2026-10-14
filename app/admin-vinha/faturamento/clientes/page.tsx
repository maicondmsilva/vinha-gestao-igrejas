'use client';
import {useCallback,useEffect,useState} from 'react';
import Link from '@/app/admin-vinha/CentralLink';
import '../billing.css';
import '../providers.css';
import '../financial.css';

type Org={id:string;registration_code:number;name:string;owner_email?:string;subscription_status:string;billing_profile_complete:boolean};
type Result={organizations?:Org[];error?:string};
export default function BillingClients(){
 const[items,setItems]=useState<Org[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[search,setSearch]=useState('');
 const load=useCallback(async()=>{
  setLoading(true);setError('');
  try{
   const response=await fetch('/api/platform/billing/profiles',{cache:'no-store'}),data=await response.json<Result>();
   if(!response.ok)throw new Error(data.error||'Não foi possível carregar os ministérios.');
   if(!Array.isArray(data.organizations))throw new Error('A lista de ministérios não foi recebida. Tente novamente.');
   setItems(data.organizations);
  }catch(e){setError(e instanceof Error?e.message:'Falha de conexão. Tente novamente.')}
  finally{setLoading(false)}
 },[]);
 useEffect(()=>{const timer=window.setTimeout(()=>void load(),0);return()=>window.clearTimeout(timer)},[load]);
 const filtered=items.filter(o=>`${o.registration_code} ${o.name} ${o.owner_email||''}`.toLocaleLowerCase('pt-BR').includes(search.toLocaleLowerCase('pt-BR')));
 return <main className="billing-page">
  <aside><Link href="/admin-vinha" className="billing-brand"><i>V</i><span><b>Vinha</b><small>Administração SaaS</small></span></Link><nav><Link href="/admin-vinha">▦ Organizações</Link><Link href="/admin-vinha/faturamento">◫ Cobranças</Link><Link className="on" href="/admin-vinha/faturamento/clientes">▣ Cadastros de cobrança</Link></nav><Link className="billing-back" href="https://app.vinhaigrejas.com.br/painel">← Painel da igreja</Link></aside>
  <section><header><div><small>CARTEIRA DE CLIENTES</small><h1>Cadastros de cobrança</h1><p>Todos os ministérios, inclusive em avaliação ou com cadastro financeiro pendente. Esta lista não depende de faturas geradas.</p></div><Link className="billing-button secondary" href="/admin-vinha/faturamento">← Voltar às cobranças</Link></header>
   <label>Buscar ministério por código, nome ou e-mail<input type="search" value={search} onChange={e=>setSearch(e.target.value)} placeholder="Ex.: 1000"/></label>
   {error&&<div className="billing-notice" role="alert">{error} <button type="button" disabled={loading} onClick={()=>void load()}>Tentar novamente</button></div>}
   <div className="client-list">{loading?<div className="billing-empty">Carregando ministérios…</div>:error?null:!filtered.length?<div className="billing-empty">{items.length?'Nenhum ministério corresponde à busca.':'Nenhum ministério cadastrado.'} {!items.length&&<Link href="/admin-vinha">Cadastrar ministério</Link>}</div>:filtered.map(o=><div className="client-line" key={o.id}><span><b>{o.name}</b><small>Código {o.registration_code} · {o.owner_email||'Sem e-mail de responsável'}</small></span><em className={o.billing_profile_complete?'ready':''}>{o.billing_profile_complete?'✓ Cadastro completo':'Cadastro pendente'}</em><Link className="billing-button secondary" href={`/admin-vinha/organizacoes/${o.id}/financeiro`}>{o.billing_profile_complete?'Revisar dados':'Completar cadastro'}</Link></div>)}</div>
  </section>
 </main>
}
