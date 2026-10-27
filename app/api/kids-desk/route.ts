import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {uuidPattern} from '../../lib/private-files';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(request:Request){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);const q=new URL(request.url).searchParams,unit=q.get('unit')||'',session=q.get('session'),view=q.get('view')||'reports';if(!uuidPattern.test(unit)||session&&!uuidPattern.test(session)||!['reports','notes'].includes(view))return json({error:'Consulta inválida.'},400);
 const r=await db(request).rpc('kids_desk',{p_org:a.access!.membership.organization_id,p_unit:unit,p_session:session||null,p_view:view,p_data:Object.fromEntries(['page','search','status','from','to'].flatMap(k=>q.has(k)?[[k,q.get(k)]]:[]))});if(r.error)return json({error:r.error.code==='42501'?'Seu acesso não permite consultar estes registros.':'Revise o período e os filtros.'},r.error.code==='42501'?403:400);return json(r.data);
 }catch{return json({error:'Consulta interrompida. Atualize antes de repetir.'},503)}}
