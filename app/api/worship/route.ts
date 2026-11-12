import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {boundedBody} from '../../lib/private-files';
import {worshipCommand,worshipFailure,worshipQuery} from '../../lib/worship';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
type Rpc={rpc:(n:string,a:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{code?:string;message:string}|null}>};
// Louvor: repertório e repertório do culto. O banco decide quem pode ver e alterar em cada igreja.
async function run(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{
  let input;
  try{input=write?worshipCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,60000)))):worshipQuery(request)}catch(e){return json({error:e instanceof Error?e.message:'Pedido inválido.'},400)}
  if(!auth.access!.membership.units.some(u=>u.id===input.unit))return json({error:'Igreja sem acesso.'},403);
  const r=await (auth.access!.client as unknown as Rpc).rpc(input.fn,{p_org:auth.access!.membership.organization_id,p_unit:input.unit,p_action:input.action,p_data:input.data});
  if(r.error){const f=worshipFailure(r.error.code,r.error.message);return json({error:f.error},f.status)}
  return json(r.data);
 }catch{return json({error:'Não foi possível concluir. Atualize e tente de novo.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
