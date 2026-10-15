/* eslint-disable @typescript-eslint/no-explicit-any */
import {timingSafeEqual} from 'node:crypto';
import {NextResponse} from 'next/server';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';
import {one,rpc,check,uuid,OperationError} from '../../../../lib/supabase/operations';
import {decryptSecret} from '../../../payments/secrets';
import {verifyMercadoPagoPayment} from '../../../payments/provider';
import {handleFinancialSandboxEvent} from '../../../../lib/supabase/financial-webhook';
const paidStates=new Set(['approved','paid','received','confirmed','payment_received','payment_confirmed','checkout_paid','3','4']);
function secretMatches(expected:string|null,received:string){if(!expected||!received)return false;const a=Buffer.from(expected),b=Buffer.from(received);return a.length===b.length&&timingSafeEqual(a,b)}
export async function POST(request:Request,{params}:{params:Promise<{provider:string}>}){try{
 const {provider}=await params;if(!['asaas','mercado_pago','safe2pay'].includes(provider))return NextResponse.json({error:'Provedor inválido.'},{status:404});
 const raw=await request.text();if(raw.length>100000)return NextResponse.json({error:'Notificação muito grande.'},{status:413});
 let body:any;try{body=JSON.parse(raw||'{}')}catch{return NextResponse.json({error:'JSON inválido.'},{status:400})}
 const client=supabaseAdminClient(),setting=await one(client,'saas_billing_provider_settings','provider',provider);
 if(!setting)return NextResponse.json({error:'Provedor não configurado.'},{status:404});
 let reference='',status='',externalId='',paymentId='',amount:number|null=null;
 if(provider==='mercado_pago'){
  paymentId=String(body?.data?.id||body?.id||new URL(request.url).searchParams.get('data.id')||'');
  const credential=await decryptSecret(setting.credential_ciphertext,setting.credential_iv),verified=paymentId&&credential?await verifyMercadoPagoPayment(paymentId,credential):null;
  if(!verified||verified.currency!=='BRL')return NextResponse.json({error:'Pagamento não confirmado.'},{status:401});
  reference=verified.orderId;status=verified.status;amount=verified.amountCents;externalId='payment:'+verified.providerPaymentId+':'+status;
 }else{
  const expected=await decryptSecret(setting.webhook_token_ciphertext,setting.webhook_token_iv);
  const received=provider==='asaas'?request.headers.get('asaas-access-token')||'':String(body?.SecretKey||body?.ResponseDetail?.SecretKey||request.headers.get('x-webhook-token')||'');
  if(!secretMatches(expected,received))return NextResponse.json({error:'Notificação não autenticada.'},{status:401});
  if(provider==='asaas'&&setting.environment==='sandbox'){
   const handled=await handleFinancialSandboxEvent(client,body);
   return NextResponse.json({ok:true,sandbox:true,ignored:!handled});
  }
  if(provider==='asaas'){
   const value=body.payment||body.checkout||{};paymentId=String(value.id||'');reference=String(value.externalReference||'');status=String(body.event||value.status||'');externalId=String(body.id||paymentId+':'+status);
   amount=body.payment?Math.round(Number(value.value)*100):Array.isArray(value.items)?Math.round(value.items.reduce((sum:number,item:any)=>sum+Number(item.quantity)*Number(item.value),0)*100):null;
  }else{
   const value=body.ResponseDetail||body.Object||body;reference=String(value.Reference||'');status=String(value.TransactionStatus?.Code||value.TransactionStatus?.Name||value.Status||'');paymentId=String(value.IdTransaction||value.TransactionId||value.Id||'');externalId=paymentId+':'+status;amount=Math.round(Number(value.Amount)*100);
  }
 }
 if(!reference&&paymentId){const invoice=check(await client.from('saas_invoices').select('id').eq('provider',provider).eq('provider_invoice_id',paymentId).maybeSingle()),batch=!invoice?check(await client.from('saas_consolidated_invoices').select('id').eq('provider',provider).eq('provider_invoice_id',paymentId).maybeSingle()):null;reference=invoice?.id||batch?.id||''}
 if(!uuid(reference)||!externalId)return NextResponse.json({ok:true,ignored:true});
 const normalized=status.toLowerCase(),isPaid=paidStates.has(normalized);
 if(isPaid&&(!Number.isFinite(amount)||amount===null))return NextResponse.json({error:'Valor do pagamento ausente.'},{status:400});
 // Persist identifiers and reconciliation fields, never provider secrets or card data.
 return NextResponse.json(await rpc(client,'apply_saas_billing_event',{p_reference:reference,p_provider:provider,p_event_id:externalId,p_event_type:status,p_paid:isPaid,p_amount_cents:amount,p_payload:{reference,status,paymentId,amountCents:amount}}));
}catch(error){console.error('Retorno de pagamento Vinha:',error instanceof Error?error.message:'falha');return NextResponse.json({error:error instanceof OperationError?error.message:'Não foi possível processar a notificação.'},{status:error instanceof OperationError?error.status:500})}}
