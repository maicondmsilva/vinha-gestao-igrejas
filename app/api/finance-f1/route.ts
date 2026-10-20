import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {financeCommand,financeQuery} from '../../lib/finance-f1';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
function failure(code?:string){return json({error:code==='42501'?'Você não possui acesso financeiro a todas as unidades selecionadas.':code==='23505'?'Este cadastro ou saldo inicial já existe. Atualize a consulta.':code==='40001'||code==='40P01'?'O registro foi alterado por outra operação. Atualize antes de continuar.':code==='22023'||code==='22P02'||code==='23514'?'Revise os dados, os cadastros ativos e o período financeiro.':'Não foi possível confirmar a operação. Preserve o pedido e reenvie o mesmo identificador.'},code==='42501'?403:code==='23505'||code==='40001'||code==='40P01'?409:code==='22023'||code==='22P02'||code==='23514'?400:503)}
async function run(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||failure();
 const access=auth.access!;if(!['owner','admin','finance'].includes(access.membership.role))return failure('42501');
 try{
  const client=access.client as unknown as OperationsClient;
  if(!write&&new URL(request.url).searchParams.get('action')==='bootstrap'){
   const units=[];for(const u of access.membership.units){const check=await client.rpc('finance_f1',{p_org:access.membership.organization_id,p_units:[u.id],p_action:'choices',p_data:{search:'__'}});if(!check.error)units.push(u)}
   return json({units,scope:access.userId+':'+access.membership.organization_id,canShare:['owner','admin'].includes(access.membership.role)});
  }
  let action:string,units:string[],data:unknown;
  try{if(write){const parsed=financeCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,16384))));action=parsed.action;units=[parsed.unitId];data=parsed.data}else{const parsed=financeQuery(request);({action,units,data}=parsed)}}catch(e){return json({error:e instanceof Error?e.message:'Dados inválidos.'},400)}
  if(units.some(id=>!access.membership.units.some(u=>u.id===id)))return failure('42501');
  const result=await client.rpc('finance_f1',{p_org:access.membership.organization_id,p_units:units,p_action:action,p_data:data});if(result.error)return failure(result.error.code);
  if(write&&(!result.data?.ok||result.data.id!==(data as {id:string}).id))return failure();
  return json(result.data);
 }catch{return failure()}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
