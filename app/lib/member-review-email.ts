import nodemailer from 'nodemailer';
import {vinhaEmail} from '../../shared/vinha-email.ts';
import {eventEmailConfigured} from './event-email.ts';

// Fila de e-mails de reprovação de cadastro (private.member_review_emails).
// O aviso no app já existe sem depender deste envio; falhas voltam para a fila com nova tentativa.
type Rpc={rpc:(name:string,args:Record<string,unknown>)=>PromiseLike<{data:unknown;error:unknown}>};
type Job={id:string;recipient:string;subject:string;items:string[];reason:string;church:string|null;slug:string|null};
export type OutgoingEmail={to:string;subject:string;html:string;text:string};

const appUrl='https://app.vinhaigrejas.com.br';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function memberReviewMessage(j:Job):OutgoingEmail{
 const slug=j.slug&&/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(j.slug)?j.slug:null;
 const {html,text}=vinhaEmail({church:j.church||undefined,title:'Seu cadastro precisa de ajuste',
  intro:'Olá! A igreja analisou o cadastro que você enviou pelo aplicativo e alguns dados precisam ser corrigidos:',
  items:j.items,note:j.reason?'Motivo: '+j.reason:undefined,
  action:slug?{label:'Corrigir meu cadastro',url:appUrl+'/membro/'+slug+'?corrigir=1'}:undefined});
 return{to:j.recipient,subject:j.subject,html,text};
}

function jobs(raw:unknown):Job[]{
 if(!Array.isArray(raw))return[];
 return raw.filter(j=>j&&typeof j==='object'&&uuid.test(String(j.id))&&typeof j.recipient==='string'&&/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(j.recipient))
  .map(j=>({id:j.id,recipient:j.recipient,subject:String(j.subject||'Seu cadastro precisa de ajuste').slice(0,200),items:Array.isArray(j.items)?j.items.map(String).slice(0,20):[],reason:String(j.reason||'').slice(0,1000),church:typeof j.church==='string'?j.church:null,slug:typeof j.slug==='string'?j.slug:null}));
}

export async function sendMemberReviewEmails(client:Rpc,env:Record<string,string|undefined>=process.env,limit=20,send?:(m:OutgoingEmail)=>Promise<void>){
 if(!eventEmailConfigured(env))return{sent:0,failed:0,waitingConfiguration:true};
 const batch=await client.rpc('member_review_email_batch',{p_limit:limit});
 if(batch.error)throw Error('Fila de e-mails indisponível.');
 const deliver=send??(async(m:OutgoingEmail)=>{const port=Number(env.EVENT_SMTP_PORT||465);
  const transport=nodemailer.createTransport({host:'smtp.hostinger.com',port,secure:port===465,requireTLS:true,tls:{minVersion:'TLSv1.2',rejectUnauthorized:true},auth:{user:env.EVENT_SMTP_USER,pass:env.EVENT_SMTP_PASSWORD},connectionTimeout:10000,greetingTimeout:10000,socketTimeout:15000,disableFileAccess:true,disableUrlAccess:true});
  await transport.sendMail({from:'"Vinha" <notificacoes@vinhaigrejas.com.br>',to:m.to,subject:m.subject,html:m.html,text:m.text})});
 let sent=0,failed=0;
 for(const j of jobs(batch.data)){
  try{await deliver(memberReviewMessage(j));sent++;await client.rpc('member_review_email_mark',{p_id:j.id,p_ok:true,p_error:null})}
  catch(e){failed++;await client.rpc('member_review_email_mark',{p_id:j.id,p_ok:false,p_error:(e instanceof Error?e.message:'erro').slice(0,300)})}
 }
 return{sent,failed,waitingConfiguration:false};
}
