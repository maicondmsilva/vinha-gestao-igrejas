import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {digitalConnection} from '../../lib/digital-provider';
import {inspectDigitalCheckout} from '../../lib/event-checkout-review';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function POST(request:Request){try{
 const a=await authorizeSupabaseChurch(request,'units.manage',['events.events:create','events.events:edit','events.agenda:create','events.agenda:edit']);if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);
 const b=JSON.parse(new TextDecoder().decode(await boundedBody(request,2000)));if(!b||Object.keys(b).some(k=>!['unit','event','order'].includes(k))||![b.unit,b.event,b.order].every(v=>typeof v==='string'&&uuidPattern.test(v)))return json({error:'Pedido inválido.'},400);
 const r=await db(request).rpc('event_checkout_review',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_event:b.event,p_order:b.order});if(r.error||!r.data?.receiver)return json({error:'Seu acesso não permite conferir este pedido ou não há checkout vinculado.'},403);
 const server=supabaseAdminClient(),c=await digitalConnection(server,r.data.receiver);if(c.org!==a.access!.membership.organization_id)throw Error('Recebedor fora do escopo.');
 const result=await inspectDigitalCheckout(c,r.data);if(!result.ready)return json(result);
 if(!['uncertain','dispatching','ready'].includes(r.data.state))return json({note:'O pedido ainda não possui uma tentativa externa em conferência.',ready:false});
 if(r.data.state!=='ready'){const saved=await server.rpc('event_ticket_delivery',{p_id:b.order,p_action:'complete',p_data:{preference:result.providerPaymentId,url:result.checkoutUrl}});if(saved.error)return json({error:'O pedido mudou durante a conferência. Atualize a situação antes de continuar.'},409)}
 return json({note:result.note,url:result.checkoutUrl,ready:true});
}catch(e){const message=e instanceof Error?e.message:'';return json({error:/^(Acesso à conta|Consulta de meios de pagamento|Consulta de checkout|Consulta do link).*HTTP \d{3}/.test(message)||message.startsWith('Credencial protegida indisponível.')?message:'Conferência não concluída. Confira a conexão da conta recebedora e consulte o provedor antes de repetir.'},503)}}
