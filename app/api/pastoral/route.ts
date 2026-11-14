import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {pastoralCommand,pastoralStaffError} from '../../lib/pastoral-command';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
/** Agenda pastoral no painel: GET consulta a semana (ou busca pessoas com ?q=); POST executa ações da equipe. */
export async function GET(request:Request){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);
 const q=new URL(request.url).searchParams,unit=q.get('unit')||'';if(!uuidPattern.test(unit))return json({error:'Selecione uma igreja válida.'},400);
 const org=a.access!.membership.organization_id,search=q.get('q');
 const r=search!==null?await db(request).rpc('pastoral_people',{p_org:org,p_unit:unit,p_query:search}):await db(request).rpc('pastoral_staff',{p_org:org,p_unit:unit,p_action:'overview',p_data:{from:q.get('from')||'',to:q.get('to')||''}});
 if(r.error){const e=pastoralStaffError(r.error.code,r.error.message);return json({error:e.error},e.status)}return json(r.data);
}catch{return json({error:'Conexão interrompida.'},503)}}
export async function POST(request:Request){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);
 let b;try{b=pastoralCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,20000))))}catch{}if(!b)return json({error:'Revise os campos.'},400);
 const r=await db(request).rpc('pastoral_staff',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_action:b.action,p_data:b.data});
 if(r.error){const e=pastoralStaffError(r.error.code,r.error.message);return json({error:e.error},e.status)}return json(r.data);
}catch{return json({error:'Conexão interrompida. Atualize antes de repetir.'},503)}}
