import nodemailer from 'nodemailer';
import type {OperationsClient} from './operations';
import {cellUuid} from '../cell-directory';
const message='Há relatório de encontro aguardando atualização na sua unidade. Entre na Vinha e abra Células → Pendências e avisos para consultar as informações autorizadas.';
const link='https://app.vinhaigrejas.com.br/login';
export function cellDeliveryConfig(env:Record<string,string|undefined>){
 const email=env.CELL_EMAIL_ENABLED==='true'&&env.CELL_SMTP_HOST==='smtp.hostinger.com'&&['465','587'].includes(env.CELL_SMTP_PORT||'465')&&env.CELL_SMTP_USER==='notificacoes@vinhaigrejas.com.br'&&Boolean(env.CELL_SMTP_PASSWORD);
 const whatsapp=env.CELL_WHATSAPP_ENABLED==='true'&&/^\d{6,30}$/.test(env.CELL_WHATSAPP_PHONE_ID||'')&&/^v\d+\.\d+$/.test(env.CELL_WHATSAPP_API_VERSION||'')&&/^[a-z0-9_]{1,100}$/.test(env.CELL_WHATSAPP_TEMPLATE||'')&&Boolean(env.CELL_WHATSAPP_TOKEN);
 return {email,whatsapp};
}
export function cellDeliveryBatch(raw:unknown){if(!Array.isArray(raw)||raw.length>25)throw Error('Lote inválido.');return raw.map(d=>{if(!d||Object.keys(d).sort().join(',')!=='channel,id,recipient,token'||!cellUuid.test(d.id)||!cellUuid.test(d.token)||!['email','whatsapp'].includes(d.channel)||typeof d.recipient!=='string'||(d.channel==='email'?!/^[^\s<>\r\n@]+@[^\s<>\r\n@]+\.[^\s<>\r\n@]+$/.test(d.recipient):!/^[1-9][0-9]{9,14}$/.test(d.recipient)))throw Error('Destinatário inválido.');return d as {id:string;token:string;channel:string;recipient:string}})}
export async function processCellExternalDeliveries(client:OperationsClient,env:Record<string,string|undefined>=process.env){
 const ready=cellDeliveryConfig(env),channels=Object.entries(ready).filter(([,v])=>v).map(([k])=>k);if(!channels.length)return {submitted:0,uncertain:0,waitingConfiguration:true};
 const claim=await client.rpc('cell_delivery_claim',{p_channels:channels});if(claim.error)throw Error('Fila indisponível.');const batch=cellDeliveryBatch(claim.data);let submitted=0,uncertain=0;
 for(const d of batch){let provider:string|null=null;try{
  if(!channels.includes(d.channel))throw Error('Canal indisponível.');
  if(d.channel==='email'){
   const port=Number(env.CELL_SMTP_PORT||465),transport=nodemailer.createTransport({host:'smtp.hostinger.com',port,secure:port===465,requireTLS:true,tls:{minVersion:'TLSv1.2',rejectUnauthorized:true},auth:{user:env.CELL_SMTP_USER,pass:env.CELL_SMTP_PASSWORD},connectionTimeout:10000,greetingTimeout:10000,socketTimeout:15000,disableFileAccess:true,disableUrlAccess:true});
   try{const result=await transport.sendMail({from:{name:'Vinha — Gestão que frutifica',address:'notificacoes@vinhaigrejas.com.br'},to:d.recipient,subject:'Vinha · Relatório de encontro pendente',text:message+'\n\nAcesse: '+link,html:`<div style="background:#f4f6f2;padding:32px;font-family:Arial,sans-serif"><div style="max-width:560px;margin:auto;background:white;padding:32px;border-radius:16px"><h1 style="color:#174b3b">Vinha</h1><p>Gestão que frutifica</p><h2>Seu acompanhamento faz a diferença</h2><p>${message}</p><p><a href="${link}" style="background:#245c47;color:white;padding:12px 20px;display:inline-block;border-radius:8px">Acessar a Vinha</a></p><p>Você ativou este aviso nas preferências de Células. Para interromper, acesse Pendências e avisos → Meus canais de aviso.</p></div></div>`,messageId:`<cell-${d.id}@vinhaigrejas.com.br>`});if(!result.accepted?.length||result.rejected?.length)throw Error('Envio não confirmado.');provider=result.messageId;}finally{transport.close()}
  }else{
   const r=await fetch(`https://graph.facebook.com/${env.CELL_WHATSAPP_API_VERSION}/${env.CELL_WHATSAPP_PHONE_ID}/messages`,{method:'POST',headers:{authorization:`Bearer ${env.CELL_WHATSAPP_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',to:d.recipient,type:'template',template:{name:env.CELL_WHATSAPP_TEMPLATE,language:{code:'pt_BR'}}}),signal:AbortSignal.timeout(15000)});
   if(!r.ok)throw Error('Provedor recusou.');const data=await r.json() as {messages?:{id:string}[]};provider=data.messages?.[0]?.id||null;if(!provider)throw Error('Resposta sem confirmação.');
  }
 }catch{provider=null}
 const finish=await client.rpc('cell_delivery_finish',{p_id:d.id,p_token:d.token,p_provider:provider});if(finish.error||finish.data!==true)throw Error('Resultado não registrado. Consulte o provedor antes de repetir.');if(provider)submitted++;else uncertain++;
 }
 return {submitted,uncertain,waitingConfiguration:false};
}
