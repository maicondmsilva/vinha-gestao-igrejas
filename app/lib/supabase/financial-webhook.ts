import {check,rpc,requireValue,type OperationsClient,type Row} from './operations';
import {httpsUrl} from './financial-payloads';
// Called ONLY after verifying the Asaas token. These records cannot affect production invoices.
export async function handleFinancialSandboxEvent(client:OperationsClient,body:Row){
 const value=body.invoice||body.subscription||body.checkout;if(!value)return false;
 const kind=body.invoice?'fiscal':'recurring';
 let operation:Row|null=null;
 if(typeof value.id==='string')operation=check(await client.from('saas_financial_operations').select('*').eq('kind',kind).eq('provider_id',value.id).maybeSingle());
 if(!operation&&typeof value.externalReference==='string'&&/^[a-f0-9-]{36}$/i.test(value.externalReference))operation=check(await client.from('saas_financial_operations').select('*').eq('kind',kind).eq('id',value.externalReference).maybeSingle());
 if(!operation)return false;
 requireValue(operation.environment==='sandbox','Ambiente incompatível.',409);
 // A delayed event cannot revive an already cancelled recurring authorization.
 if(operation.status==='cancelled')return true;
 const patch:Row={updated_at:new Date().toISOString()};
 if(body.invoice){
  requireValue(Math.round(Number(value.value)*100)===Number(operation.amount_cents),'Valor fiscal divergente.',409);
  const states:Record<string,string>={INVOICE_AUTHORIZED:'authorized',INVOICE_CANCELED:'cancelled',INVOICE_ERROR:'rejected'};
  if(!states[body.event])return true;
  if(operation.status==='authorized'&&body.event==='INVOICE_ERROR')return true;
  Object.assign(patch,{status:states[body.event],provider_id:value.id,pdf_url:httpsUrl(value.pdfUrl),xml_url:httpsUrl(value.xmlUrl)});
 }else if(body.subscription){
  requireValue(Math.round(Number(value.value)*100)===Number(operation.amount_cents)&&value.cycle==='MONTHLY'&&value.billingType==='CREDIT_CARD','Assinatura divergente.',409);
  if(['SUBSCRIPTION_INACTIVATED','SUBSCRIPTION_DELETED'].includes(body.event))patch.status='cancelled';
  else if(['SUBSCRIPTION_CREATED','SUBSCRIPTION_UPDATED'].includes(body.event)&&value.status==='ACTIVE')patch.status='active';
  else return true;
  patch.subscription_id=value.id;
 }else{
  const states:Record<string,string>={CHECKOUT_PAID:'awaiting_confirmation',CHECKOUT_CANCELED:'cancelled',CHECKOUT_EXPIRED:'cancelled'};
  if(!states[body.event]||operation.status==='active')return true;
  patch.status=states[body.event];
 }
 requireValue(typeof body.id==='string'&&body.id.length>0,'Evento sem identificador.',400);
 await rpc(client,'apply_financial_sandbox_event',{p_id:operation.id,p_event:body.id,p_patch:patch});return true;
}
