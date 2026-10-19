'use client';
import {useEffect,useState} from 'react';
import type {ContractData} from '../types';
import {readPlanPreview} from '../../../lib/plan-preview-response';
import {ledgerCurrency} from '../../../lib/ledger-pilot';
export default function PlanPreview({data,contractId}:{data:ContractData|null;contractId:string}){
 const [nextPlanId,setPlan]=useState(''),[attempt,setAttempt]=useState(0),[result,setResult]=useState<{key:string;value:ReturnType<typeof readPlanPreview>}|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const key=`${contractId}:${nextPlanId}:${attempt}`;
 useEffect(()=>{const controller=new AbortController();setResult(null);setError('');
  if(!contractId||!nextPlanId){setBusy(false);return()=>controller.abort()}
  setBusy(true);
  void fetch(`/api/platform/contracts/plan-preview?contractId=${encodeURIComponent(contractId)}&nextPlanId=${encodeURIComponent(nextPlanId)}`,{cache:'no-store',signal:controller.signal}).then(async response=>{
   const body=await response.json<unknown>();if(!response.ok)throw Error(body&&typeof body==='object'&&'error' in body?String(body.error):'Consulta indisponível.');
   const value=readPlanPreview(body,contractId,nextPlanId);if(!controller.signal.aborted)setResult({key,value});
  }).catch(e=>{if(!controller.signal.aborted)setError(e instanceof Error?e.message:'Prévia indisponível.')}).finally(()=>{if(!controller.signal.aborted)setBusy(false)});
  return()=>controller.abort();
 },[contractId,nextPlanId,attempt,key]);
 const preview=result?.key===key?result.value:null;
 return <section className="sector-card"><h2>Prévia de mudança de pacote</h2><label>Novo pacote<select value={nextPlanId} disabled={!contractId} onChange={event=>setPlan(event.target.value)}><option value="">Selecione um pacote</option>{data?.plans.filter(plan=>plan.active).map(plan=><option key={plan.id} value={plan.id}>{plan.name}</option>)}</select></label><button type="button" disabled={!contractId||!nextPlanId||busy} onClick={()=>setAttempt(value=>value+1)}>Recalcular prévia</button>
 {busy&&<p role="status">Calculando estimativa…</p>}{error&&<p role="alert">{error}</p>}{preview&&<div><p>Mensalidade atual: {ledgerCurrency(preview.currentNetCents)}</p><p>Nova mensalidade: {ledgerCurrency(preview.nextNetCents)}</p><p>Ajuste adicional estimado: {ledgerCurrency(preview.chargeCents)}</p><p>Crédito estimado para próxima fatura: {ledgerCurrency(preview.creditCents)}</p><p>Calculado em {new Date(preview.effectiveAt).toLocaleString('pt-BR')}; ciclo termina em {new Date(preview.cycleEnd).toLocaleString('pt-BR')}.</p></div>}
 <p>Somente estimativa. Nenhuma alteração foi salva. O valor depende do momento da confirmação e da revalidação do catálogo, ciclo e permissões.</p><button type="button" disabled>Confirmação ainda não habilitada neste piloto</button></section>;
}
