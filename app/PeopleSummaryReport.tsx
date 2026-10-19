'use client';
import {useMinistryLanguage} from './MinistryLanguage';
import {useEffect,useState} from 'react';
import {peopleSummary} from './lib/people-summary';
type Summary=ReturnType<typeof peopleSummary>;
export default function PeopleSummaryReport({unitId}:{unitId:string}){
 const {t}=useMinistryLanguage();
 const [report,setReport]=useState<Summary|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(false),[revision,setRevision]=useState(0);
 useEffect(()=>{const controller=new AbortController();setReport(null);setError('');if(!unitId){setLoading(false);setError('Selecione uma unidade no topo do painel.');return}setLoading(true);
  const params=new URLSearchParams({unitId});const tenant=new URLSearchParams(location.search).get('tenant');if(tenant)params.set('tenant',tenant);
  fetch('/api/reports/people?'+params,{signal:controller.signal}).then(async response=>{const data=await response.json();if(!response.ok)throw Error(response.status===403?'Relatório não autorizado para esta unidade ou contrato.':'Não foi possível consultar.');const valid=peopleSummary(data);if(valid.unitId!==unitId)throw Error('Unidade divergente. Atualize o relatório.');if(!controller.signal.aborted)setReport(valid)}).catch(reason=>{if(!controller.signal.aborted)setError(reason instanceof Error?reason.message:'Relatório indisponível.')}).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return()=>controller.abort();
 },[unitId,revision]);
 const labels={total:'Pessoas cadastradas',members:'Membros',visitors:'Visitantes',integration:'Em integração',other:'Outras situações'};
 return <section className="content people-page"><div className="page-head"><div><p className="section-over">RELATÓRIOS · PRIMEIRA ENTREGA</p><h1>{t('relatorios')}</h1><p>Contagens da unidade selecionada, limitadas aos registros que sua conta pode consultar.</p></div><button type="button" className="create" disabled={loading} onClick={()=>setRevision(value=>value+1)}>Atualizar relatório</button></div>
  <p>Esta entrega não inclui relatórios financeiros, exportação nominal ou consolidação de filiais.</p>
  {loading&&<p role="status">Consultando dados…</p>}{error&&<p role="alert">{error}</p>}
  {report&&report.unitId===unitId&&!loading&&<><div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(160px,1fr))',gap:16}}>{(Object.keys(labels) as (keyof typeof labels)[]).map(key=><article className="card" key={key} style={{padding:24}}><small>{labels[key]}</small><h2>{BigInt(report.counts[key]).toLocaleString('pt-BR')}</h2></article>)}</div><p>Consulta em {new Date(report.generatedAt).toLocaleString('pt-BR')}. Nenhum dado pessoal foi exportado.</p></>}
 </section>;
}
