import {receiverId} from '../../../../lib/finance-receivers';
import {verifyDigitalMercadoSignature} from '../../../../lib/digital-signature';
import {boundedBody} from '../../../../lib/private-files';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';
import {digitalConnection,digitalSync} from '../../../../lib/digital-provider';
import {openReceiver,receiverContext} from '../../../../lib/receiver-vault';
const reply=(data:unknown,status:number)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
export async function POST(r:Request,{params}:{params:Promise<{receiver:string}>}){
 try{
  const receiver=receiverId((await params).receiver),u=new URL(r.url),environment=u.searchParams.get('environment');if(!['sandbox','production'].includes(environment||'')||[...u.searchParams.keys()].some(k=>!['environment','data.id','type'].includes(k)||u.searchParams.getAll(k).length!==1))return reply({error:'Notificação inválida.'},400);
  const server=supabaseAdminClient(),c=await digitalConnection(server,receiver);if(c.provider!=='mercado_pago'||c.environment!==environment)return reply({error:'Conta ou ambiente inválido.'},403);
  const material=openReceiver<{webhookSecret?:string}>(c.sealed,receiverContext(c.org,c.unit,c.provider,c.environment));
  const secret=material.webhookSecret||(!c.webhookConfigured?process.env[environment==='sandbox'?'FINANCE_MP_TEST_WEBHOOK_SECRET':'FINANCE_MP_LIVE_WEBHOOK_SECRET']:'')||'';
  if(!secret)return reply({error:'Notificações não configuradas.'},503);
  if(!verifyDigitalMercadoSignature(r,secret))return reply({error:'Assinatura inválida.'},401);
  const d=JSON.parse(new TextDecoder().decode(await boundedBody(r,32768))),id=u.searchParams.get('data.id')!;if(d.type!=='payment'||String(d.data?.id)!==id)return reply({error:'Evento não suportado.'},400);
  if(d.live_mode!==(environment==='production')||String(d.user_id)!==c.externalId)return reply({error:'Titular ou ambiente divergente.'},403);
  // Fetch the current payment with this receiver's credential. No status/amount from POST is trusted.
  await digitalSync(server,receiver,c,id);return reply({ok:true},200);
 }catch{return reply({error:'Processamento não confirmado; notificação deve ser reenviada.'},503)}
}
