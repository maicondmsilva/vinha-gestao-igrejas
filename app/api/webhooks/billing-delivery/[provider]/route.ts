import {NextResponse} from 'next/server';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';
import {rpc} from '../../../../lib/supabase/operations';
import {verifyMeta,verifyResend} from '../../../../lib/supabase/delivery-signatures';
type DeliveryBody={type?:string;created_at?:string;data?:{email_id?:string};entry?:{changes?:{value?:{statuses?:{id:string;status:string;timestamp:string}[]}}[]}[]};
export async function GET(request:Request,{params}:{params:Promise<{provider:string}>}){
 const {provider}=await params,q=new URL(request.url).searchParams,token=process.env.BILLING_WHATSAPP_VERIFY_TOKEN;
 if(provider!=='whatsapp'||!token||q.get('hub.mode')!=='subscribe'||q.get('hub.verify_token')!==token)return new Response('Não autorizado',{status:403});
 return new Response(q.get('hub.challenge')||'',{headers:{'content-type':'text/plain'}});
}
export async function POST(request:Request,{params}:{params:Promise<{provider:string}>}){
 try{
  const {provider}=await params,raw=await request.text();if(raw.length>100000)return new Response(null,{status:413});
  const valid=provider==='email'?verifyResend(raw,request.headers,process.env.BILLING_RESEND_WEBHOOK_SECRET||''):provider==='whatsapp'&&verifyMeta(raw,request.headers.get('x-hub-signature-256'),process.env.BILLING_META_APP_SECRET||'');
  if(!valid)return NextResponse.json({error:'Assinatura inválida.'},{status:401});
  const d=JSON.parse(raw) as DeliveryBody,client=supabaseAdminClient();
  if(provider==='email'){
   const status:Record<string,string>={'email.delivered':'delivered','email.bounced':'bounced','email.failed':'delivery_failed'};
   if(d.type&&status[d.type]&&d.data?.email_id&&d.created_at)await rpc(client,'record_billing_delivery',{p_provider:'resend',p_event:request.headers.get('svix-id'),p_message:d.data.email_id,p_status:status[d.type],p_occurred:d.created_at});
  }else{
   for(const entry of d.entry||[])for(const change of entry.changes||[])for(const s of change.value?.statuses||[]){
    if(!['delivered','read','failed'].includes(s.status)||!/^\d+$/.test(s.timestamp))continue;
    await rpc(client,'record_billing_delivery',{p_provider:'meta_whatsapp',p_event:`${s.id}:${s.status}:${s.timestamp}`,p_message:s.id,p_status:s.status==='failed'?'delivery_failed':s.status,p_occurred:new Date(Number(s.timestamp)*1000).toISOString()});
   }
  }
  return NextResponse.json({ok:true});
 }catch{return NextResponse.json({error:'Não foi possível processar o retorno.'},{status:500})}
}
