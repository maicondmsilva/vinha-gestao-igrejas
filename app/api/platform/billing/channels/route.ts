import {centralRoute,check,one,update,requireValue,clean,recordAudit,type Row} from '../../../../lib/supabase/operations';
import {decryptSecret} from '../../../payments/secrets';
import {billingChannelFingerprint,billingChannelVerified} from '../../../../lib/supabase/billing-channel-readiness';
export const GET=centralRoute(async(_r,client)=>{
 const channels=check(await client.from('saas_notification_channels').select('*').in('channel',['email','whatsapp'])) as Row[];
 return{enabled:process.env.BILLING_NOTIFICATIONS_ENABLED==='true',channels:await Promise.all(channels.map(async c=>({channel:c.channel,enabled:c.enabled,status:c.status,sender:c.sender_address,verified:await billingChannelVerified(c),config:{phoneNumberId:c.provider_config?.phoneNumberId||'',businessAccountId:c.provider_config?.businessAccountId||'',billingLanguage:c.provider_config?.billingLanguage||'pt_BR',apiVersion:c.provider_config?.apiVersion||'v22.0',billingTemplates:c.provider_config?.billingTemplates||{}}}))),callbacks:{email:!!process.env.BILLING_RESEND_WEBHOOK_SECRET,whatsapp:!!process.env.BILLING_META_APP_SECRET&&!!process.env.BILLING_WHATSAPP_VERIFY_TOKEN}};
});
export const POST=centralRoute(async(request,client,session)=>{
 requireValue(request.headers.get('origin')===new URL(request.url).origin,'Origem inválida.',403);
 const d=await request.json<Row>();requireValue(['email','whatsapp'].includes(d.channel),'Canal inválido.');
 const channel=await one(client,'saas_notification_channels','channel',d.channel);requireValue(channel,'Canal não encontrado.');
 const credential=await decryptSecret(channel.credential_ciphertext,channel.credential_iv);requireValue(credential,'Configure a credencial em Alertas antes de validar o envio financeiro.');
 if(d.channel==='email'){
  requireValue(channel.provider==='resend','Provedor de e-mail incompatível.');
  const sender=String(channel.sender_address||'').match(/(?:<)?([^\s<>]+@[^\s<>]+)(?:>)?$/)?.[1];requireValue(sender,'Informe um remetente de e-mail válido.');
  const r=await fetch('https://api.resend.com/domains?limit=100',{headers:{authorization:`Bearer ${credential}`},signal:AbortSignal.timeout(10000)});
  requireValue(r.ok,'Não foi possível consultar os domínios. Use uma credencial com permissão de consulta do Resend.');
  const result=await r.json<{data?:{name:string;status:string}[]}>();
  requireValue(result.data?.some(x=>x.name.toLowerCase()===sender.split('@')[1].toLowerCase()&&x.status==='verified'),'O domínio do remetente ainda não está verificado no Resend.');
 }else{
  requireValue(channel.provider==='meta_whatsapp','Provedor de WhatsApp incompatível.');
  const config=d.config||{},templates=config.billingTemplates||{};
  requireValue(/^\d{5,30}$/.test(config.phoneNumberId)&&/^\d{5,30}$/.test(config.businessAccountId)&&/^v\d{1,2}\.0$/.test(config.apiVersion),'Informe IDs e versão válidos do Meta.');
  requireValue(/^[a-z]{2}(?:_[A-Z]{2})?$/.test(config.billingLanguage),'Idioma inválido.');
  requireValue(['upcoming','overdue','paid'].every(k=>/^[a-z0-9_]{1,100}$/.test(templates[k])),'Informe os três modelos aprovados.');
  const base=`https://graph.facebook.com/${config.apiVersion}`,headers={authorization:`Bearer ${credential}`};
  const phone=await fetch(`${base}/${config.businessAccountId}/phone_numbers?fields=id&limit=100`,{headers,signal:AbortSignal.timeout(10000)});
  requireValue(phone.ok,'A credencial não pode consultar a conta WhatsApp.');
  const phones=await phone.json<{data?:{id:string}[]}>();requireValue(phones.data?.some(p=>p.id===config.phoneNumberId),'O número não pertence à conta informada.');
  const r=await fetch(`${base}/${config.businessAccountId}/message_templates?limit=100`,{headers,signal:AbortSignal.timeout(10000)});
  requireValue(r.ok,'Não foi possível consultar os modelos do WhatsApp.');
  const result=await r.json<{data?:{name:string;status:string;category:string;language:string;components?:{type:string;text?:string}[]}[]}>();
  requireValue(['upcoming','overdue','paid'].every(k=>result.data?.some(t=>t.name===templates[k]&&t.status==='APPROVED'&&t.category==='UTILITY'&&t.language===config.billingLanguage&&[...new Set((t.components?.find(c=>c.type==='BODY')?.text||'').match(/\{\{\d+\}\}/g)||[])].sort().join(',')==='{{1}},{{2}},{{3}},{{4}}')),'Modelos precisam estar aprovados como utilitários, no idioma definido e com quatro parâmetros de corpo.');
  channel.provider_config={...(channel.provider_config||{}),phoneNumberId:config.phoneNumberId,businessAccountId:config.businessAccountId,billingLanguage:config.billingLanguage,apiVersion:config.apiVersion,billingTemplates:{upcoming:clean(templates.upcoming,100),overdue:clean(templates.overdue,100),paid:clean(templates.paid,100)}};
 }
 channel.provider_config={...channel.provider_config,billingVerification:{at:new Date().toISOString(),fingerprint:billingChannelFingerprint(channel,credential)}};
 await update(client,'saas_notification_channels','channel',channel.channel,{provider_config:channel.provider_config,updated_at:Date.now()});
 await recordAudit(client,session.id,'billing.channel_verified','notification_channel',channel.channel);
 return{ok:true,message:'Configuração consultada e validada sem enviar mensagens. Validação válida por sete dias; alterações exigem nova validação.'};
});
