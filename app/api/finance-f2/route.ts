import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {financeReason} from '../../lib/finance-errors';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {financeF2Command,financeF2Query} from '../../lib/finance-f2';
const json=(v:unknown,status=200)=>Response.json(v,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(r:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 if(!['owner','admin','finance'].includes(a.membership.role))return json({error:'Sem permissão financeira.'},403);
 let action:string,unit:string,data:unknown;
 try{if(write){const c=financeF2Command(JSON.parse(new TextDecoder().decode(await boundedBody(r,16384))));action=c.action;unit=c.unitId;data=c.data}else{const q=financeF2Query(r);unit=q.unit;action=q.action;data={title:q.title,before:q.before}}}catch(e){return json({error:e instanceof Error?e.message:'Dados inválidos.'},400)}
 if(!a.membership.units.some(u=>u.id===unit))return json({error:'Unidade não autorizada.'},403);
 try{const res=await (a.client as unknown as OperationsClient).rpc('finance_f2',{p_org:a.membership.organization_id,p_unit:unit,p_action:action,p_data:data});if(res.error){const c=res.error.code;return json({error:financeReason(res.error.message)||(c==='42501'?'Acesso financeiro recusado.':c==='40001'||c==='23505'?'Registro alterado. Atualize e confira o histórico.':c==='22023'||c==='23514'?'Revise valores, saldo em aberto, datas e cadastros ativos.':'Não foi possível confirmar. Reenvie o mesmo pedido, sem criar outro.')},c==='42501'?403:c==='40001'||c==='23505'?409:c==='22023'||c==='23514'?400:503)}if(write&&(!res.data?.ok||res.data.id!==(data as {id:string}).id))return json({error:'Resultado incerto. Preserve e reenvie o mesmo pedido.'},503);return json(res.data)}catch{return json({error:'Conexão interrompida. Preserve o pedido para conferir.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
