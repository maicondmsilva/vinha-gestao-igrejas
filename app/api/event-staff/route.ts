import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {processEventReceipts} from '../../lib/event-receipts';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import {ticketBuyerValid} from '../../../shared/event-tickets';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(r:Request)=>run(r,false);export const POST=(r:Request)=>run(r,true);
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,100000))):Object.fromEntries(new URL(request.url).searchParams);
 if(!b||Object.keys(b).some(k=>!['unit','event','action','id','version','data','tenant'].includes(k))||!uuidPattern.test(b.unit)||!uuidPattern.test(b.event)||!['read','create','item','edit','receipt','email'].includes(b.action)||b.action!=='read'&&!uuidPattern.test(b.id)||!write&&!['read','item'].includes(b.action)||b.action==='create'&&!ticketBuyerValid(b.data)||b.action==='edit'&&(!Number.isInteger(b.version)||b.version<1))return json({error:'Revise os dados da inscrição ou do pedido.'},400);
 const r=await db(request).rpc('event_staff_admin',{p_org:auth.access!.membership.organization_id,p_unit:b.unit,p_event:b.event,p_action:b.action,p_id:b.id||null,p_version:b.version||null,p_data:b.data||{}});
 if(r.error)return json({error:r.error.code==='42501'?'Seu acesso não permite esta operação.':r.error.code==='40001'?'Atualize a lista. Confira prazo, estoque, alterações anteriores e o intervalo entre reenvios.':'Confira os dados, respostas e limites do ticket.'},r.error.code==='42501'?403:r.error.code==='40001'?409:400);
 if(b.action==='email'){
  const delivery=await processEventReceipts(supabaseAdminClient(),auth.access!.membership.organization_id,b.event).catch(()=>({ok:false,uncertain:true}));
  const latest=await db(request).rpc('event_staff_admin',{p_org:auth.access!.membership.organization_id,p_unit:b.unit,p_event:b.event,p_action:'email',p_id:b.id,p_data:b.data});
  return json({...r.data,...(!latest.error?latest.data:{}),delivery});
 }
 return json(r.data);
}catch{return json({error:'Operação não confirmada. Consulte os registros antes de repetir.'},503)}}
