import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {parseAgendaCommand} from '../../lib/member-agenda-command';
import {agendaError} from '../../../shared/member-agenda';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage',['events.events:create','events.events:edit','events.agenda:create','events.agenda:edit']);if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let b:{action:string;unit:string;id:string|null;version:number|null;data:Record<string,unknown>};
 if(write){try{const parsed=parseAgendaCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,12000))));if(!parsed)throw Error();b=parsed}catch{return json({error:'Revise os dados do evento ou o código do ticket.'},400)}}
 else{const q=new URL(request.url).searchParams,unit=q.get('unit')||'',id=q.get('event');if(!uuidPattern.test(unit)||id&&!uuidPattern.test(id))return json({error:'Selecione uma igreja válida.'},400);b={action:id?'attendees':'list',unit,id,version:null,data:{}}}
 const r=await db(request).rpc('member_agenda_admin',{p_org:auth.access!.membership.organization_id,p_unit:b.unit,p_action:b.action,p_id:b.id,p_version:b.version,p_data:b.data});
 if(r.error)return json({error:agendaError(r.error.message)},r.error.code==='42501'?403:r.error.code==='40001'?409:['22023','22007','22008','22P02'].includes(r.error.code)?400:503);
 if(write&&r.data?.ok!==true)return json({error:'Operação não confirmada. Atualize a lista antes de repetir.'},503);
 return json(r.data);
 }catch{return json({error:'Conexão interrompida. Consulte a lista antes de repetir.'},503)}}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
