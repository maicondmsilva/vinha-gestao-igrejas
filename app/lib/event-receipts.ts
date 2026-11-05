import nodemailer from 'nodemailer';
import type {OperationsClient} from './supabase/operations';
import {eventEmailConfigured} from './event-email.ts';
import {uuidPattern} from './private-files.ts';
type Job={id:string;token:string;recipient:string;title:string;receipt:string;sale:boolean};
export async function processEventReceipts(client:OperationsClient,org:string|null=null,event:string|null=null,env:Record<string,string|undefined>=process.env,send?:(j:Job,text:string)=>Promise<string>){
 if(!eventEmailConfigured(env))return{ok:true,waitingConfiguration:true,submitted:0,uncertain:0};let submitted=0,uncertain=0;const started=Date.now();const seen=new Set<string>();
 for(let n=0;n<10&&Date.now()-started<20000;n++){
  const r=await client.rpc('event_receipt_work',{p_action:'claim',p_org:org,p_event:event});if(r.error||!Array.isArray(r.data?.items)||r.data.items.length>1)throw Error('Fila indisponível.');if(!r.data.items.length)break;
  const j=r.data.items[0] as Job;if(![j.id,j.token,j.receipt].every(v=>typeof v==='string'&&uuidPattern.test(v))||typeof j.recipient!=='string'||!/^[^\s<>\r\n@]+@[^\s<>\r\n@]+\.[^\s<>\r\n@]+$/.test(j.recipient)||typeof j.title!=='string'||j.title.length>220||/[\r\n]/.test(j.title)||seen.has(j.id))throw Error('Entrega inválida.');seen.add(j.id);
  let provider:string|null=null;const text='Consulte a situação atual e baixe seu comprovante:\nhttps://app.vinhaigrejas.com.br/comprovante-evento?token='+j.receipt+'\n\nO QR Code é liberado somente após a confirmação. Este link é pessoal; compartilhe apenas com o titular.';
  try{if(send)provider=await send(j,text);else{const port=Number(env.EVENT_SMTP_PORT||465),t=nodemailer.createTransport({host:env.EVENT_SMTP_HOST,port,secure:port===465,requireTLS:true,tls:{minVersion:'TLSv1.2',rejectUnauthorized:true},auth:{user:env.EVENT_SMTP_USER,pass:env.EVENT_SMTP_PASSWORD},connectionTimeout:8000,greetingTimeout:8000,socketTimeout:10000,disableFileAccess:true,disableUrlAccess:true});try{const s=await t.sendMail({from:{name:'Vinha · Comprovantes',address:'notificacoes@vinhaigrejas.com.br'},to:j.recipient,subject:j.title,text,messageId:`<receipt-${j.id}@vinhaigrejas.com.br>`});if(s.accepted?.length&&!s.rejected?.length)provider=s.messageId}finally{t.close()}}}catch{provider=null}
  const saved=await client.rpc('event_receipt_work',{p_action:'settle',p_data:{id:j.id,token:j.token,provider}});if(saved.error)throw Error('Resultado externo não confirmado. Não reenvie automaticamente.');if(provider)submitted++;else uncertain++;
 }
 return{ok:true,submitted,uncertain,waitingConfiguration:false};
}
