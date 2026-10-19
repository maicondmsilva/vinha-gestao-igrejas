import {centralRoute,rows,rpc,requireValue} from '../../../lib/supabase/operations';
import type {ContractForm} from '../../../admin-vinha/contratos/types';
import {ledgerPilotEnabled} from '../../../lib/ledger-pilot';
import {requiresProrationReview} from '../../../lib/contract-write-guard';
export const GET=centralRoute(async(_r,client)=>({units:await rows(client,'organization_units'),organizations:await rows(client,'organizations'),contracts:await rows(client,'saas_unit_contracts'),plans:await rows(client,'saas_plans'),modules:await rows(client,'saas_module_catalog'),planModules:await rows(client,'saas_plan_modules')}));
export const PUT=centralRoute(async(request,client)=>{
 requireValue(request.headers.get('origin')===new URL(request.url).origin,'Origem inválida.',403);
 const data=await request.json<ContractForm&{unitId:string}>();
 requireValue(data&&['draft','active','suspended'].includes(data.status)&&Number.isInteger(Number(data.dueDay))&&Number(data.dueDay)>=1&&Number(data.dueDay)<=28,'Revise contrato e vencimento.');
 requireValue(!data.profile?.email||/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.profile.email),'E-mail financeiro inválido.');
 if(process.env.VINHA_PLAN_PRORATION_PILOT==='true'&&ledgerPilotEnabled(process.env)){
  const current=await client.from('saas_unit_contracts').select('status,plan_id,payer_unit_id,due_day,module_decisions').eq('unit_id',data.unitId).maybeSingle();
  requireValue(!current.error,'Não foi possível validar o contrato atual.',503);
  requireValue(!requiresProrationReview(current.data,data as unknown as Record<string,unknown>),'Use o fluxo proporcional para alterar pacote, módulos, pagador ou vencimento de um contrato ativo.',409);
 }
 return{ok:true,id:await rpc(client,'save_unit_contract',{p_data:data})};
});
