import {eventModuleError} from '../../../shared/event-validation';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(r:Request)=>run(r,false);export const POST=(r:Request)=>run(r,true);
async function run(request:Request,write:boolean){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,80000))):Object.fromEntries(new URL(request.url).searchParams);
 if(!b||Object.keys(b).some(k=>!['unit','event','action','id','version','data','tenant'].includes(k))||!uuidPattern.test(b.unit)||!uuidPattern.test(b.event)||b.id&&!uuidPattern.test(b.id)||!['read','settings','type','type_delete','type_active','coupon','registrations','checkin'].includes(b.action)||write&&(!Number.isSafeInteger(b.version)||b.version<1)||!write&&!['read','registrations'].includes(b.action))return json({error:'Revise os campos do evento.'},400);
 const r=await db(request).rpc('event_ticket_admin',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_event:b.event,p_action:b.action,p_id:b.id||null,p_version:b.version||null,p_data:b.data||{}});if(r.error)return json({error:eventModuleError(r.error.message,r.error.code)||(r.error.code==='42501'?'Seu acesso não permite esta operação.':r.error.code==='40001'?'Atualize o evento. Confira vagas, horário e inscrições anteriores.':'Revise as informações e os limites informados.')},r.error.code==='42501'?403:r.error.code==='40001'?409:400);return json(r.data);
 }catch{return json({error:'Operação não confirmada. Atualize antes de repetir.'},503)}}
