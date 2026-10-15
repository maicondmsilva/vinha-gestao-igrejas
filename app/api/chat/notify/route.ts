import { withLegacyContainment } from '../../../lib/release-availability';
import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';
import {sessionFrom} from '../../_auth';

async function legacyPOST(request:Request){
  const session=await sessionFrom(request);
  if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});
  if(!session.personId)return NextResponse.json({error:'Usuário sem membro vinculado.'},{status:409});
  const data=await request.json<Record<string,unknown>>();
  const message=await env.DB.prepare(`SELECT m.id,m.body,m.conversation_id,c.name FROM chat_messages m JOIN chat_conversations c ON c.id=m.conversation_id WHERE m.id=? AND m.church_id=? AND m.sender_person_id=?`).bind(data.messageId,session.churchId,session.personId).first<Record<string,any>>();
  if(!message)return NextResponse.json({error:'Mensagem inválida.'},{status:403});
  const [setting,recipients]=await Promise.all([
    env.DB.prepare("SELECT enabled,status FROM notification_channel_settings WHERE church_id=? AND channel='push'").bind(session.churchId).first<Record<string,any>>(),
    env.DB.prepare(`SELECT p.person_id,p.notification_level,CASE WHEN EXISTS(SELECT 1 FROM chat_mentions x WHERE x.message_id=? AND x.mentioned_person_id=p.person_id) THEN 1 ELSE 0 END mentioned FROM chat_participants p WHERE p.conversation_id=? AND p.status='active' AND p.person_id<>? AND p.notification_level<>'none'`).bind(message.id,message.conversation_id,session.personId).all<Record<string,any>>()
  ]);
  const now=Date.now(),ready=Boolean(setting?.enabled&&setting?.status==='connected');
  const statements=recipients.results.filter(item=>item.notification_level==='all'||item.mentioned).map(item=>env.DB.prepare(`INSERT INTO notification_jobs (id,church_id,event_code,channel,recipient_person_id,subject,body,entity_type,entity_id,scheduled_at,status,created_at,attempts,next_attempt_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,0,?,?)`).bind(crypto.randomUUID(),session.churchId,item.mentioned?'chat_mention':'chat_message','push',item.person_id,item.mentioned?`Você foi mencionado em ${message.name}`:`Nova mensagem em ${message.name}`,String(message.body).slice(0,220),'chat_conversation',message.conversation_id,now,ready?'queued':'waiting_configuration',now,ready?now:null,now));
  if(statements.length)await env.DB.batch(statements);
  return NextResponse.json({ok:true,count:statements.length,status:ready?'queued':'waiting_configuration'});
}

export const POST = withLegacyContainment(legacyPOST);
