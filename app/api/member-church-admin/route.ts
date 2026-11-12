import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {churchError} from '../../../shared/member-church';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let action='list',id:string|null=null;const unit:string|null=null;let data:Record<string,string>={};
 if(write){try{const b=JSON.parse(new TextDecoder().decode(await boundedBody(request,12000)));if(!b||typeof b!=='object'||Object.keys(b).some(k=>!['action','id','unit','data'].includes(k)))throw Error();
  action=b.action;if(action!=='review')throw Error();
  {id=b.id;if(!uuidPattern.test(id||''))throw Error();if(action==='review'){if(!b.data||typeof b.data!=='object'||Object.keys(b.data).some(k=>!['decision','reason'].includes(k))||!['approved','rejected'].includes(b.data.decision)||typeof b.data.reason!=='string'||b.data.reason.trim().length<5||b.data.reason.length>1000)throw Error();data=b.data;}}
 }catch{return json({error:'Revise os campos e informe o motivo da decisão.'},400)}}
 const r=await db(request).rpc('member_church_admin',{p_org:auth.access!.membership.organization_id,p_action:action,p_id:id,p_unit:unit,p_data:data});
 if(r.error)return json({error:churchError(r.error.message)},r.error.code==='42501'?403:r.error.code==='40001'?409:r.error.code==='22023'?400:503);
 if(write&&r.data?.ok!==true)return json({error:'Operação não confirmada. Atualize antes de repetir.'},503);
 return json(r.data);
 }catch{return json({error:'Falha de conexão. Atualize antes de repetir.'},503)}}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
