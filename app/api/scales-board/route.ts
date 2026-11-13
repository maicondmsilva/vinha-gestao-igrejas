import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {boundedBody} from '../../lib/private-files';
import {boardCommand,boardQuery} from '../../lib/scale-board';
import {scaleOperationError} from '../../../shared/scale-operations';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
type Rpc={rpc:(n:string,a:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{code?:string;message:string}|null}>};
// Escalas › Quadro de montagem. O banco confere equipe, função, conflitos e permissão de publicar.
async function run(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{
  let input:{unit:string;action?:string;data:Record<string,unknown>};
  try{input=write?boardCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,16000)))):boardQuery(request)}catch{return json({error:'Revise o período e os dados do quadro.'},400)}
  if(!auth.access!.membership.units.some(u=>u.id===input.unit))return json({error:'Igreja sem acesso.'},403);
  const r=await (auth.access!.client as unknown as Rpc).rpc('scale_board',{p_org:auth.access!.membership.organization_id,p_unit:input.unit,p_action:input.action||'view',p_data:input.data});
  if(r.error)return json({error:scaleOperationError(r.error.message,r.error.code)},r.error.code==='42501'?403:r.error.code==='40001'?409:400);
  return json(r.data);
 }catch{return json({error:'Não foi possível confirmar. Atualize o quadro antes de repetir.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
