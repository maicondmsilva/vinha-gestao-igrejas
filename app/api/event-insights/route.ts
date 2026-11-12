import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(r:Request)=>run(r,false);export const POST=(r:Request)=>run(r,true);
async function run(request:Request,write:boolean){try{
 const a=await authorizeSupabaseChurch(request,'units.manage',['events.events:create','events.events:edit','events.agenda:create','events.agenda:edit']);if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);
 const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,15000))):Object.fromEntries(new URL(request.url).searchParams);
 if(!b||Object.keys(b).some(k=>!['unit','event','action','from','to','data','tenant'].includes(k))||!uuidPattern.test(b.unit)||!uuidPattern.test(b.event)||!['report','finance','journeys','journeys_save'].includes(b.action)||!write&&b.action==='journeys_save'||write&&b.action!=='journeys_save')return json({error:'Consulta inválida.'},400);
 const r=await db(request).rpc('event_insights',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_event:b.event,p_action:b.action,p_data:write?b.data:{from:b.from||'',to:b.to||''}});
 if(r.error)return json({error:r.error.code==='42501'?'Seu acesso não permite consultar ou alterar estas informações.':'Confira o período e as jornadas selecionadas.'},r.error.code==='42501'?403:400);
 return json(r.data);
}catch{return json({error:'Consulta não confirmada.'},503)}}
