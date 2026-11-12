import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {boundedBody} from '../../../lib/private-files';
import {familyCommand,familyFailure,familyQuery} from '../../../lib/family';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
type Rpc={rpc:(n:string,a:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{code?:string;message:string}|null}>};
// Vínculos familiares. O banco confere se a pessoa pode ver ou editar as duas pessoas de cada vínculo.
async function run(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'people.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{
  let input;
  try{input=write?familyCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,8000)))):familyQuery(request)}catch(e){return json({error:e instanceof Error?e.message:'Pedido inválido.'},400)}
  const r=await (auth.access!.client as unknown as Rpc).rpc('person_family',{p_org:auth.access!.membership.organization_id,p_action:input.action,p_data:input.data});
  if(r.error){const f=familyFailure(r.error.code,r.error.message);return json({error:f.error},f.status)}
  return json(r.data);
 }catch{return json({error:'Não foi possível concluir. Atualize e tente de novo.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
