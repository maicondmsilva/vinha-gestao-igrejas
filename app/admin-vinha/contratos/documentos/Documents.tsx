'use client';
import {useEffect,useRef,useState} from 'react';
import type {ContractData} from '../types';
import type {summarizeProrationDocument} from '../../../lib/proration-documents';
import {ledgerCurrency} from '../../../lib/ledger-pilot';
import {parseProrationDocuments} from '../../../lib/proration-document-response';
import PlanPreview from './PlanPreview';
type Document=ReturnType<typeof summarizeProrationDocument>;
export default function Documents(){
 const [data,setData]=useState<ContractData|null>(null),[contractId,setContractId]=useState(''),[documents,setDocuments]=useState<Document[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState(''),[loaded,setLoaded]=useState(false),[refresh,setRefresh]=useState(0);
 const generation=useRef(0);
 useEffect(()=>{const controller=new AbortController();void fetch('/api/platform/contracts',{cache:'no-store',signal:controller.signal}).then(async response=>{const value=await response.json<ContractData>();if(!response.ok)throw Error(value.error||'Não foi possível consultar os contratos.');setData(value)}).catch(e=>{if(!controller.signal.aborted)setError(e instanceof Error?e.message:'Consulta indisponível.')});return()=>controller.abort()},[]);
 useEffect(()=>{
  const version=++generation.current,controller=new AbortController();setDocuments([]);setLoaded(false);setError('');
  if(!contractId){setBusy(false);return()=>controller.abort()}
  setBusy(true);
  void fetch(`/api/platform/contracts/documents?contractId=${encodeURIComponent(contractId)}`,{cache:'no-store',signal:controller.signal}).then(async response=>{
   const value=await response.json<{error?:string;pilot?:boolean;documents:Document[]}>();if(!response.ok)throw Error(value.error||'Consulta indisponível.');
   const confirmed=parseProrationDocuments(value);
   if(generation.current===version){setDocuments(confirmed);setLoaded(true)}
  }).catch(e=>{if(!controller.signal.aborted&&generation.current===version)setError(e instanceof Error?e.message:'Consulta indisponível.')}).finally(()=>{if(generation.current===version)setBusy(false)});
  return()=>controller.abort();
 },[contractId,refresh]);
 return <main className="team-chat-page"><a href="/admin-vinha/contratos">← Contratos por igreja</a><h1>Créditos e ajustes proporcionais</h1><p role="note">Validação isolada: documentos internos, sem envio ao cliente, cobrança externa ou reembolso automático. Créditos seguem para faturas futuras, respeitando o pagador.</p>
 <section className="sector-card"><label>Contrato da igreja<select value={contractId} onChange={event=>setContractId(event.target.value)} disabled={!data}><option value="">Selecione uma igreja</option>{data?.contracts.map(contract=>{const unit=data.units.find(item=>item.id===contract.unit_id);return <option key={contract.id} value={contract.id}>{unit?`${unit.registration_code} · ${unit.name}`:contract.unit_id}</option>})}</select></label><button type="button" disabled={!contractId||busy} onClick={()=>setRefresh(value=>value+1)}>Atualizar histórico</button>
 {error&&<p role="alert">{error}</p>}{busy&&<p role="status">Consultando documentos…</p>}{!contractId&&<p>Selecione um contrato para consultar seu histórico.</p>}{loaded&&!documents.length&&<p>Nenhum ajuste proporcional registrado para este contrato.</p>}
 {loaded&&documents.map(document=><article className="sector-card" key={document.id}><h2>{document.kind==='credit'?'Crédito para próxima fatura':'Ajuste adicional interno'}</h2><p>Valor: {ledgerCurrency(document.amountCents)}</p>{document.kind==='credit'&&<><p>Utilizado: {ledgerCurrency(document.usedCents)}</p><p>Saldo ainda não utilizado: {ledgerCurrency(document.remainingCents||'0')}</p><p>A utilização depende da elegibilidade da fatura e do pagador.</p></>}<p>Registrado em: {new Date(document.createdAt).toLocaleString('pt-BR')}</p><small>Identificador: {document.id}</small></article>)}
 </section><PlanPreview data={data} contractId={contractId}/></main>;
}
