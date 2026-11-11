import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import type {OperationsClient} from '../../../lib/supabase/operations';
import {boundedBody} from '../../../lib/private-files';
import {receiverId} from '../../../lib/finance-receivers';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(r:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 let unit:string,data:Record<string,unknown>={};
 try{
  if(write){const v=JSON.parse(new TextDecoder().decode(await boundedBody(r,2048)));if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).some(k=>!['unit','receipt','target','version'].includes(k))||!Number.isSafeInteger(v.version)||v.version<0)throw Error();unit=receiverId(v.unit);data={receipt:receiverId(v.receipt),target:receiverId(v.target),version:v.version};if(!['owner','admin'].includes(a.membership.role)||!a.membership.units.some(u=>u.id===data.target))return json({error:'O responsável precisa de acesso às duas igrejas.'},403);
  }else{const p=new URL(r.url).searchParams;if([...p.keys()].some(k=>!['unit','tenant'].includes(k)||p.getAll(k).length!==1))throw Error();unit=receiverId(p.get('unit'))}
 }catch{return json({error:'Revise a igreja, o recebimento e a versão da destinação.'},400)}
 if(!a.membership.units.some(u=>u.id===unit))return json({error:'Igreja não autorizada.'},403);
 try{const result=await(a.client as unknown as OperationsClient).rpc('finance_digital_destination',{p_org:a.membership.organization_id,p_unit:unit,p_action:write?'set':'list',p_data:data});if(result.error)return json({error:result.error.code==='40001'?'Destinação alterada. Atualize antes de salvar.':'Destinação indisponível. Confira permissões, recebimento e vínculo entre igrejas.'},result.error.code==='40001'?409:403);return json(result.data)}catch{return json({error:'Não foi possível confirmar. Consulte a lista antes de repetir.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
