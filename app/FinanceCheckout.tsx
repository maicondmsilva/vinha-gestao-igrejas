'use client';
import {useState,type FormEvent} from 'react';
import {Dialog} from './FinanceModule';
import {financeMoney} from './lib/finance-f1';
export default function FinanceCheckout({unit,order,name,gross,environment}:{unit:string;order:string;name:string;gross:string;environment:string}){
 const [open,setOpen]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[url,setUrl]=useState('');
 async function submit(e:FormEvent<HTMLFormElement>){
  e.preventDefault();if(busy)return;const form=new FormData(e.currentTarget);setBusy(true);setError('');
  try{
   const tenant=new URLSearchParams(location.search).get('tenant'),query=tenant?'?'+new URLSearchParams({tenant}):'';
   const response=await fetch('/api/finance-digital/checkout'+query,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({unit,order,name:String(form.get('name')||'')}),signal:AbortSignal.timeout(25000)});
   const d=await response.json() as {error?:string;checkoutUrl?:string};if(!response.ok||!d.checkoutUrl)throw Error(d.error||'Checkout não confirmado.');
   const link=new URL(d.checkoutUrl);if(link.protocol!=='https:'||!['www.mercadopago.com.br','mercadopago.com.br'].includes(link.hostname)||link.username||link.password||link.port||link.hash||link.pathname!=='/checkout/v1/redirect')throw Error('Link não confirmado.');setUrl(link.href);
  }catch(e){setError(e instanceof Error?e.message:'Resultado incerto. Consulte o responsável antes de tentar novamente.')}finally{setBusy(false)}
 }
 return <><button type="button" className="f1-secondary" onClick={()=>{setOpen(true);setError('')}}>Preparar checkout</button>{open&&<Dialog title="Checkout seguro" locked={busy} close={()=>setOpen(false)}>
  <p>{environment==='sandbox'?'Ambiente de teste: não use dados ou dinheiro reais.':'Produção: depende de homologação e autorização do recebedor.'}</p>
  <p>Valor do pedido: <b>{financeMoney(gross)}</b>. Abrir o checkout não confirma pagamento e não autoriza recorrência.</p>
  {error&&<p className="f1-alert" role="alert">{error}</p>}
  {url?<div className="f1-actions"><a href={url} target="_blank" rel="noopener noreferrer">Continuar no Mercado Pago ↗</a><p>Não pague duas vezes. A confirmação virá da consulta segura ao provedor.</p></div>:<form onSubmit={submit}><label>Nome do pagador<input name="name" required minLength={2} maxLength={160} defaultValue={name}/></label><p>Validação restrita ao proprietário/administrador. O e-mail será o da conta autenticada, sem enviar dados do cadastro de membros por aproximação.</p><div className="f1-dialog-foot"><button type="button" className="f1-secondary" disabled={busy} onClick={()=>setOpen(false)}>Cancelar</button><button type="submit" disabled={busy}>{busy?'Conferindo…':'Preparar link seguro'}</button></div></form>}
 </Dialog>}</>;
}
