import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {eventInfoValid} from '../../../shared/event-info';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(r:Request)=>run(r,false);export const POST=(r:Request)=>run(r,true);
async function run(request:Request,write:boolean){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,100000))):Object.fromEntries(new URL(request.url).searchParams);
 if(!b||Object.keys(b).some(k=>!['unit','action','event','version','data','tenant'].includes(k))||!uuidPattern.test(b.unit)||b.event&&!uuidPattern.test(b.event)||write&&(!eventInfoValid(b.data)||b.action!=='save'||!Number.isSafeInteger(b.version)||b.version<1)||!write&&!['choices','read'].includes(b.action))return json({error:'Revise os campos e a igreja selecionada.'},400);
 const r=await db(request).rpc('event_information_admin',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_action:b.action,p_event:b.event||null,p_version:b.version||null,p_data:b.data||{}});if(r.error)return json({error:r.error.code==='42501'?'Seu acesso não permite esta operação ou algum dos destinos.':r.error.code==='40001'?'O evento foi alterado. Atualize antes de repetir.':'Revise datas, endereços, links e participantes da equipe.'},r.error.code==='42501'?403:r.error.code==='40001'?409:400);if(write&&r.data?.ok!==true)return json({error:'Sem confirmação. Consulte antes de repetir.'},503);return json(r.data);
 }catch{return json({error:'Consulta interrompida. Atualize antes de repetir.'},503)}}
