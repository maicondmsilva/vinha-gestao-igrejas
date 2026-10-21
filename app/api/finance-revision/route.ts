import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {financeRevision} from '../../lib/finance-revision';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export async function POST(r:Request){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 const a=auth.access!;if(!['owner','admin','finance'].includes(a.membership.role))return json({error:'Sem permissão financeira.'},403);
 let c:ReturnType<typeof financeRevision>;try{c=financeRevision(JSON.parse(new TextDecoder().decode(await boundedBody(r,8192))))}catch{return json({error:'Revise os campos da edição.'},400)}
 if(!a.membership.units.some(u=>u.id===c.unitId))return json({error:'Igreja não autorizada.'},403);
 try{const result=await(a.client as unknown as OperationsClient).rpc('finance_revise_pending',{p_org:a.membership.organization_id,p_unit:c.unitId,p_data:c.data});
 if(result.error){const code=result.error.code;return json({error:code==='42501'?'Sem acesso ao lançamento.':code==='40001'?'O lançamento mudou. Atualize antes de editar.':code==='22023'?'Somente previsões manuais sem baixas ou série podem ser editadas. Confira também os cadastros ativos.':'Resultado não confirmado. Preserve o mesmo pedido para conferir.'},code==='42501'?403:code==='40001'?409:code==='22023'?400:503)}
 if(result.data?.ok!==true||result.data.id!==c.data.id)return json({error:'Resultado não confirmado. Preserve o pedido.'},503);
 return json(result.data);
 }catch{return json({error:'Não foi possível confirmar. Preserve o mesmo pedido.'},503)}
}
