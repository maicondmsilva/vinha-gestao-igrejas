import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(r:Request)=>run(r,false);export const POST=(r:Request)=>run(r,true);
async function run(request:Request,write:boolean){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Indisponível.'},503);const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,12000))):Object.fromEntries(new URL(request.url).searchParams);
 if(!b||Object.keys(b).some(k=>!['unit','session','action','id','version','data','tenant'].includes(k))||!uuidPattern.test(b.unit)||b.session&&!uuidPattern.test(b.session)||write&&(!['save','archive'].includes(b.action)||!uuidPattern.test(b.id)))return json({error:'Revise o registro.'},400);
 const r=await db(request).rpc('kids_resources',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_session:b.session||null,p_action:write?b.action:'list',p_id:b.id||null,p_version:b.version??null,p_data:b.data||{}});if(r.error)return json({error:r.error.code==='40001'?'Registro alterado. Atualize antes de repetir.':'Acesso ou registro indisponível para esta conta e sala.'},r.error.code==='42501'?403:r.error.code==='40001'?409:400);return json(r.data);
 }catch{return json({error:'Conexão interrompida. Consulte os registros antes de repetir.'},503)}}
