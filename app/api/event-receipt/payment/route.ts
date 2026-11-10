import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {boundedBody,uuidPattern} from '../../../lib/private-files';
import {trustedSessionRequest} from '../../../lib/access-security';
import {digitalConnection} from '../../../lib/digital-provider';
import {checkoutPreparationIssue,checkoutOrigin,createDigitalPreference,type CheckoutReservation} from '../../../lib/digital-checkout';
import {eventCheckoutMethods} from '../../../../shared/event-payment-methods';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store','Referrer-Policy':'no-referrer'}});
export async function POST(request:Request){try{
 if(!trustedSessionRequest(request))return json({error:'Origem não autorizada.'},403);
 const b=JSON.parse(new TextDecoder().decode(await boundedBody(request,1000)));if(!b||Object.keys(b).join(',')!=='token'||!uuidPattern.test(b.token))return json({error:'Comprovante indisponível.'},400);
 const server=supabaseAdminClient(),proof=await server.rpc('event_receipt_payment',{p_token:b.token});if(proof.error||!proof.data)return json({error:'Prazo encerrado ou pedido indisponível para pagamento.'},409);
 const a=proof.data,args={p_event:a.event,p_action:'pay',p_id:a.id,p_actor:null,p_proof:a.proof,p_data:{},p_network:''};
 const order=await server.rpc('event_ticket_checkout',args);if(order.error)return json({error:'Confira a situação do pedido com a igreja.'},409);
 const claim=await server.rpc('event_ticket_delivery',{p_id:a.id,p_action:'claim',p_data:{}});if(claim.error||!claim.data)return json({error:'Pagamento indisponível.'},409);
 const reservation=claim.data as CheckoutReservation&{org:string;unit:string;methods?:string[]|null};
 if(reservation.state==='dispatching'){try{const c=await digitalConnection(server,reservation.receiver);if(c.org!==reservation.org||!c.beneficiaries.includes(reservation.unit))throw Error('Recebedor divergente.');const result=await createDigitalPreference({...c,methods:eventCheckoutMethods(c.methods,reservation.methods)},reservation,checkoutOrigin(process.env.FINANCE_CHECKOUT_ORIGIN||'https://app.vinhaigrejas.com.br'));const saved=await server.rpc('event_ticket_delivery',{p_id:a.id,p_action:'complete',p_data:{preference:result.providerPaymentId,url:result.checkoutUrl}});if(saved.error)throw Error('Resultado não registrado.')}catch(error){const issue=checkoutPreparationIssue(error);await server.rpc('event_ticket_delivery',{p_id:a.id,p_action:issue?.retry?'not_sent':'uncertain',p_data:{}});return json({error:issue?.message||'Pagamento em conferência. Não gere outro pedido; consulte a igreja.'},409)}}
 const status=await server.rpc('event_ticket_checkout',{...args,p_action:'status'});return status.data?.checkoutUrl?json({url:status.data.checkoutUrl}):json({error:'Pagamento em conferência. Consulte a igreja antes de repetir.'},409);
}catch{return json({error:'Pagamento não confirmado. Consulte a igreja antes de repetir.'},503)}}
