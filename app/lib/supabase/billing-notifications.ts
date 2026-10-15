import {check,rows,one,update,type OperationsClient,type Row} from './operations';
import {decryptSecret} from '../../api/payments/secrets';
import {billingEvent,billingEventApplicable} from './billing-rules';

const date=(value:number)=>new Date(value).toLocaleDateString('pt-BR',{timeZone:'America/Sao_Paulo'});
const money=(value:number)=>(value/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
async function payerSettings(client:OperationsClient,invoice:Row){
 const profile=await one(client,'saas_billing_profiles','church_id',invoice.payer_church_id);
 if(!invoice.payer_unit_id)return profile;
 const contract=await one(client,'saas_unit_contracts','unit_id',invoice.payer_unit_id),unit=await one(client,'organization_units','id',invoice.payer_unit_id);
 if(!contract)return null;
 return{...(unit?.unit_type==='headquarters'?profile:{}),...contract,...contract.financial_profile};
}
async function providerSend(channel:Row,notification:Row,to:string,invoice:Row){
 const credential=await decryptSecret(channel.credential_ciphertext,channel.credential_iv);if(!credential)throw new Error('Credencial indisponível.');
 const labels:Record<string,string>={upcoming:'Sua mensalidade vence em breve',overdue:'Sua mensalidade está vencida',paid:'Recebemos seu pagamento'};
 const content=`${labels[notification.event]}. Referência ${invoice.reference_month}; valor ${money(Number(invoice.amount_cents))}; vencimento ${date(Number(invoice.due_at))}.${invoice.payment_url&&notification.event!=='paid'?` Acesse sua cobrança: ${invoice.payment_url}`:''}`;
 let response:Response;
 if(notification.channel==='email')response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{authorization:`Bearer ${credential}`,'content-type':'application/json','Idempotency-Key':`vinha-billing-${notification.id}`},body:JSON.stringify({from:channel.sender_address,to:[to],subject:`Vinha · ${labels[notification.event]}`,text:`Olá!\n\n${content}\n\nEquipe Vinha\nGestão que frutifica`}),signal:AbortSignal.timeout(15000)});
 else{
  const config=channel.provider_config||{},template=config.billingTemplates?.[notification.event];
  // All three approved utility templates must have these four body parameters.
  response=await fetch(`https://graph.facebook.com/${config.apiVersion||'v22.0'}/${encodeURIComponent(config.phoneNumberId)}/messages`,{method:'POST',headers:{authorization:`Bearer ${credential}`,'content-type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',to,type:'template',template:{name:template,language:{code:config.billingLanguage||'pt_BR'},components:[{type:'body',parameters:[invoice.reference_month,money(Number(invoice.amount_cents)),date(Number(invoice.due_at)),notification.event==='paid'?'Pagamento confirmado':invoice.payment_url||'Consulte a Central Vinha'].map(text=>({type:'text',text}))}]}}),signal:AbortSignal.timeout(15000)});
 }
 if(!response.ok)throw new Error(`Provedor recusou a mensagem (HTTP ${response.status}). Revise a configuração antes de tentar novamente.`);
 const result=await response.json<{id?:string;messages?:{id:string}[]}>();return result.id||result.messages?.[0]?.id||'accepted';
}

export async function processBillingNotifications(client:OperationsClient){
 const invoices=await rows(client,'saas_invoices');let created=0,submitted=0,waiting=0;
 for(const invoice of invoices){
  // Legacy consolidated invoices have their own payment link and are not sent twice.
  if(!invoice.unit_contract_id&&check(await client.from('saas_consolidated_invoice_items').select('id').eq('invoice_id',invoice.id).maybeSingle()))continue;
  const event=billingEvent({status:invoice.status,due_at:Number(invoice.due_at),paid_at:invoice.paid_at?Number(invoice.paid_at):null});
  if(!event)continue;const payer=await payerSettings(client,invoice);if(!payer)continue;
  for(const channel of ['email','whatsapp']){
   if(!payer[`${channel}_enabled`]||channel==='whatsapp'&&!payer.whatsapp_consent_at)continue;
   const added=check(await client.from('saas_invoice_notifications').upsert({invoice_id:invoice.id,event,channel},{onConflict:'invoice_id,event,channel',ignoreDuplicates:true}).select('id'));created+=added?.length||0;
  }
 }
 const pending=check(await client.from('saas_invoice_notifications').select('*').in('status',['pending','waiting_configuration']).order('created_at').limit(50)) as Row[];
 for(const item of pending){
  const invoice=invoices.find(i=>i.id===item.invoice_id),payer=invoice&&await payerSettings(client,invoice);
  if(!invoice||!billingEventApplicable({status:invoice.status,due_at:Number(invoice.due_at),paid_at:invoice.paid_at?Number(invoice.paid_at):null},item.event)||!payer?.[`${item.channel}_enabled`]||item.channel==='whatsapp'&&!payer.whatsapp_consent_at){await update(client,'saas_invoice_notifications','id',item.id,{status:'cancelled',updated_at:new Date().toISOString()});continue}
  const channel=await one(client,'saas_notification_channels','channel',item.channel),recipient=item.channel==='email'?payer.email:payer.whatsapp_number,config=channel?.provider_config||{};
  const ready=process.env.BILLING_NOTIFICATIONS_ENABLED==='true'&&recipient&&channel?.enabled&&channel.status==='connected'&&(item.channel==='email'?channel.provider==='resend'&&channel.sender_address:channel.provider==='meta_whatsapp'&&config.phoneNumberId&&config.billingTemplates?.[item.event]);
  if(!ready){await update(client,'saas_invoice_notifications','id',item.id,{status:'waiting_configuration',last_error:'Ative o envio financeiro e configure canal, remetente, destinatário e modelos aprovados.',updated_at:new Date().toISOString()});waiting++;continue}
  const claimed=check(await client.from('saas_invoice_notifications').update({status:'sending',attempts:item.attempts+1,updated_at:new Date().toISOString()}).eq('id',item.id).eq('status',item.status).select('id'));if(!claimed?.length)continue;
  try{const providerId=await providerSend(channel!,item,String(recipient),invoice);await update(client,'saas_invoice_notifications','id',item.id,{status:'submitted',provider_message_id:providerId,last_error:null,updated_at:new Date().toISOString()});submitted++}
  catch{await update(client,'saas_invoice_notifications','id',item.id,{status:'failed',last_error:'Envio não confirmado. Consulte o provedor antes de reenviar para evitar duplicidade.',updated_at:new Date().toISOString()})}
 }
 return{created,submitted,waiting};
}
