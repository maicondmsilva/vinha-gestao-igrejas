import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(v:unknown,status=200)=>Response.json(v,{status,headers:{'Cache-Control':'private, no-store'}});
export async function POST(r:Request){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 if(!['owner','admin','finance'].includes(a.membership.role))return json({error:'Sem permissão financeira.'},403);
 let c:{unitId:string;data:Record<string,unknown>};
 try{const raw=JSON.parse(new TextDecoder().decode(await boundedBody(r,8192))),d=raw.data;
  if(raw.action!=='annotate_entry'||Object.keys(raw).some(k=>!['action','unitId','data'].includes(k))||!uuidPattern.test(raw.unitId)||!d||typeof d!=='object'||Array.isArray(d)||Object.keys(d).some(k=>!['id','entry','version','description','notes','reason'].includes(k))||!uuidPattern.test(d.id)||!uuidPattern.test(d.entry)||!Number.isSafeInteger(d.version)||d.version<0||typeof d.description!=='string'||d.description.trim().length<2||d.description.length>300||typeof d.notes!=='string'||d.notes.length>2000||typeof d.reason!=='string'||d.reason.trim().length<2||d.reason.length>300)throw Error();
  c={unitId:raw.unitId,data:d};
 }catch{return json({error:'Informe a descrição e o motivo da alteração.'},400)}
 if(!a.membership.units.some(u=>u.id===c.unitId))return json({error:'Igreja não autorizada.'},403);
 try{const result=await(a.client as unknown as OperationsClient).rpc('finance_annotate_entry',{p_org:a.membership.organization_id,p_unit:c.unitId,p_data:c.data});if(result.error)return json({error:result.error.code==='40001'?'O lançamento mudou. Atualize antes de salvar.':result.error.code==='42501'?'Sem acesso a este lançamento.':'Não foi possível salvar a descrição. Atualize antes de repetir.'},result.error.code==='40001'?409:result.error.code==='42501'?403:400);return json(result.data)}catch{return json({error:'Resultado não confirmado. Preserve o mesmo pedido para conferir.'},503)}
}
