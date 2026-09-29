import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';
import {sessionFrom} from '../../_auth';

export async function POST(request:Request){
  const session=await sessionFrom(request);
  if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});
  if(!session.personId)return NextResponse.json({error:'Usuário sem membro vinculado.'},{status:409});
  const data=await request.json<Record<string,unknown>>();
  const message=await env.DB.prepare('SELECT id,conversation_id FROM chat_messages WHERE id=? AND church_id=? AND sender_person_id=?').bind(data.messageId,session.churchId,session.personId).first<{id:string;conversation_id:string}>();
  if(!message)return NextResponse.json({error:'Mensagem inválida.'},{status:403});
  const ids=[...new Set((Array.isArray(data.personIds)?data.personIds:[]).map(String))].slice(0,20),now=Date.now();
  if(ids.length)await env.DB.batch(ids.map(id=>env.DB.prepare('INSERT OR IGNORE INTO chat_mentions (id,church_id,message_id,mentioned_person_id,created_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM people WHERE id=? AND church_id=?)').bind(crypto.randomUUID(),session.churchId,message.id,id,now,id,session.churchId)));
  return NextResponse.json({ok:true,count:ids.length});
}
