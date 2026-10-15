import {centralRoute,check,one,insert,update,requireValue,recordAudit,type Row} from '../../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';
import {decryptSecret} from '../../../payments/secrets';
import {recurringPayload,fiscalPayload,httpsUrl,type CompanyProfile} from '../../../../lib/supabase/financial-payloads';
import {asaasStaging,sandboxCheckoutUrl} from '../../../../lib/supabase/asaas-staging';

export const GET=centralRoute(async(_request,client,session)=>{
 requireValue(['owner','admin'].includes(session.role),'Somente administradores podem acessar a homologação.',403);
 return{items:check(await client.from('saas_financial_operations').select('id,invoice_id,kind,status,environment,amount_cents,provider_id,subscription_id,checkout_url,pdf_url,xml_url,last_error,created_at').order('created_at',{ascending:false}).limit(100)),sandboxEnabled:process.env.FINANCIAL_SANDBOX_ENABLED==='true',productionEnabled:false};
});
export const POST=centralRoute(async(request,client,session)=>{
 requireValue(request.headers.get('origin')===new URL(request.url).origin,'Origem inválida.',403);
 const d=await request.json<Row>();
 requireValue(['prepare','submit','sync'].includes(d.action),'Ação inválida.');
 const admin=supabaseAdminClient();
 if(d.action==='prepare'){
  requireValue(['recurring','fiscal'].includes(d.kind),'Tipo inválido.');
  const invoice=await one(client,'saas_invoices','id',String(d.invoiceId));requireValue(invoice,'Fatura não encontrada.',404);
  requireValue(!check(await client.from('saas_consolidated_invoice_items').select('id').eq('invoice_id',invoice.id).maybeSingle()),'Use uma cobrança individual para homologação.');
  const id=crypto.randomUUID();let payload:unknown;
  if(d.kind==='recurring'){
   requireValue(invoice.unit_contract_id&&invoice.status==='open','Recorrência requer contrato por unidade e fatura aberta.');
   const contract=await one(client,'saas_unit_contracts','id',invoice.unit_contract_id);
   requireValue(contract?.status==='active'&&contract.autopay_requested,'O responsável deve solicitar o cartão recorrente no contrato.');
   // First recurring cycle must start AFTER this invoice's month: no double billing.
   requireValue(String(d.date)>`${invoice.reference_month}-31`,'A recorrência deve começar após a competência desta fatura.');
   const payerUnit=await one(client,'saas_unit_contracts','unit_id',invoice.payer_unit_id||contract.payer_unit_id);
   let profile=payerUnit?.financial_profile;
   if(!profile?.tax_id)profile=await one(client,'saas_billing_profiles','church_id',invoice.payer_church_id);
   requireValue(profile?.tax_id&&profile.email&&profile.legal_name,'Preencha o cadastro financeiro do pagador.');
   payload=recurringPayload({id,amountCents:Number(invoice.amount_cents),firstDueDate:String(d.date),origin:new URL(request.url).origin,name:profile.legal_name,email:profile.email,taxId:profile.tax_id});
  }else{
   requireValue(invoice.status==='paid'&&invoice.provider==='asaas'&&/^pay_/.test(invoice.provider_invoice_id||''),'A nota de homologação exige uma cobrança Asaas identificada e paga.');
   const company=await one(client,'saas_company_profile','id','true');requireValue(company,'Cadastre os dados fiscais da Vinha.');
   payload=fiscalPayload({id,paymentId:invoice.provider_invoice_id,amountCents:Number(invoice.amount_cents),effectiveDate:String(d.date),company:company.profile as CompanyProfile});
  }
  const item=await insert(admin,'saas_financial_operations',{id,invoice_id:invoice.id,unit_contract_id:invoice.unit_contract_id,kind:d.kind,amount_cents:invoice.amount_cents,snapshot:payload,created_by:session.id});
  await recordAudit(client,session.id,'financial.operation_prepared','financial_operation',id,{kind:d.kind,environment:'sandbox'});return{ok:true,id:item.id,message:'Preparação salva. Nenhum pedido foi enviado ao provedor.'};
 }
 const operation=await one(client,'saas_financial_operations','id',String(d.id));requireValue(operation,'Operação não encontrada.',404);
 requireValue(process.env.FINANCIAL_SANDBOX_ENABLED==='true','Homologação externa desativada. Configure o ambiente de testes antes de enviar.',503);
 const setting=await one(client,'saas_billing_provider_settings','provider','asaas');
 requireValue(setting?.environment==='sandbox'&&setting.status==='active','Configure e teste uma credencial Asaas de homologação. Produção não é aceita aqui.');
 const credential=await decryptSecret(setting.credential_ciphertext,setting.credential_iv);requireValue(credential,'Credencial ausente.');
 if(d.action==='sync'){
  requireValue(operation.kind==='fiscal'&&operation.provider_id,'Consulte a nota já enviada; recorrências são acompanhadas por retorno autenticado.');
  const result=await asaasStaging(`/invoices/${encodeURIComponent(operation.provider_id)}`,credential);
  requireValue(result.externalReference===operation.id&&Math.round(Number(result.value)*100)===Number(operation.amount_cents),'Referência ou valor fiscal divergente.');
  const status=result.status==='AUTHORIZED'?'authorized':result.status==='CANCELED'?'cancelled':result.status==='ERROR'?'rejected':'submitted';
  if(status!=='submitted')check(await admin.rpc('apply_financial_sandbox_event',{p_id:operation.id,p_event:`sync:${crypto.randomUUID()}`,p_patch:{status,pdf_url:httpsUrl(result.pdfUrl),xml_url:httpsUrl(result.xmlUrl)}}));
  await recordAudit(client,session.id,'financial.operation_synced','financial_operation',operation.id,{status});return{ok:true,message:'Situação de homologação consultada.'};
 }
 requireValue(d.confirmSandbox===true,'Confirme o envio somente para homologação.');
 requireValue(operation.status==='prepared','A operação já foi enviada ou exige conciliação. Não será reenviada.');
 // Durable claim BEFORE the HTTP call; timeout or failed persistence must never resend blindly.
 const claimed=check(await admin.from('saas_financial_operations').update({status:'sending',updated_at:new Date().toISOString()}).eq('id',operation.id).eq('status','prepared').select('id'));
 requireValue(claimed?.length,'Outro operador já iniciou este envio.',409);
 try{
  if(operation.kind==='fiscal'){
   const payment=await asaasStaging(`/payments/${encodeURIComponent(operation.snapshot.payment)}`,credential);
   requireValue(payment.externalReference===operation.invoice_id&&Math.round(Number(payment.value)*100)===Number(operation.amount_cents),'A cobrança de homologação não corresponde à fatura e ao valor.');
  }
  const result=await asaasStaging(operation.kind==='recurring'?'/checkouts':'/invoices',credential,operation.snapshot);
  requireValue(result.id,'O provedor não retornou identificador.');
  await update(admin,'saas_financial_operations','id',operation.id,{provider_id:result.id,checkout_url:operation.kind==='recurring'?sandboxCheckoutUrl(result):null,last_error:null,updated_at:new Date().toISOString()});
  check(await admin.from('saas_financial_operations').update({status:operation.kind==='recurring'?'awaiting_confirmation':'submitted'}).eq('id',operation.id).eq('status','sending'));
  await recordAudit(client,session.id,'financial.sandbox_submitted','financial_operation',operation.id,{kind:operation.kind});
  return{ok:true,message:'Solicitação enviada à homologação. Isso não confirma pagamento, assinatura ou autorização fiscal.'};
 }catch{
  check(await admin.from('saas_financial_operations').update({status:'uncertain',last_error:'Resultado não confirmado. Concilie no Asaas pela referência da operação antes de nova tentativa.',updated_at:new Date().toISOString()}).eq('id',operation.id).eq('status','sending'));
  return{ok:false,message:'Resultado incerto. Não reenvie: confira no provedor para evitar duplicidade.'};
 }
});
