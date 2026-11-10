import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {scaleCommand,scaleQuery,scaleFailure} from '../../lib/scales-foundation';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(request:Request,write:boolean){const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);try{let input;try{input=write?scaleCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,12000)))):scaleQuery(request)}catch(e){return json({error:e instanceof Error?e.message:'Cadastro inválido.'},400)}if(!auth.access!.membership.units.some(u=>u.id===input.unit))return json({error:'Igreja sem acesso.'},403);const client=auth.access!.client as unknown as OperationsClient;const result=await client.rpc('scale_foundation',{p_org:auth.access!.membership.organization_id,p_unit:input.unit,p_action:input.action,p_data:input.data});if(result.error){const failure=scaleFailure(result.error.code,result.error.message);return json({error:failure.error},failure.status)}return json(result.data)}catch{return json({error:'Não foi possível concluir. Atualize a consulta antes de repetir.'},503)}}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
