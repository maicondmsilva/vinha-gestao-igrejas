import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {planningInput,planningError} from '../../lib/scales-planning';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{let input;try{
  if(write)input=planningInput(JSON.parse(new TextDecoder().decode(await boundedBody(request,100000))),true);
  else {const p=new URL(request.url).searchParams;for(const k of p.keys())if(!['unit','action','id','team','search','page','from','to','status','tenant'].includes(k)||p.getAll(k).length!==1)throw Error('Filtro inválido ou repetido.');const data:Record<string,unknown>={};for(const [k,v]of p)if(!['unit','action','tenant'].includes(k))data[k]=k==='page'?Number(v):v;input=planningInput({unit:p.get('unit'),action:p.get('action')||'list',data},false)}
 }catch(e){return json({error:e instanceof Error?e.message:'Revise os campos.'},400)}
 if(!auth.access!.membership.units.some(u=>u.id===input.unit))return json({error:'Igreja sem acesso.'},403);
 const client=auth.access!.client as unknown as OperationsClient,r=await client.rpc('scale_planning',{p_org:auth.access!.membership.organization_id,p_unit:input.unit,p_action:input.action,p_data:input.data});if(r.error){const e=planningError(r.error.code,r.error.message);return json({error:e.error},e.status)}return json(r.data);
 }catch{return json({error:'Não foi possível confirmar a operação. Consulte a escala antes de repetir.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
