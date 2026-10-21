import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {uuidPattern} from '../../../../lib/private-files';
import {previewCumulativeProration} from '../../../../lib/plan-proration-preview';
import {exactProrationInteger,safeProrationNumber} from '../../../../lib/proration-integer';
import {readProrationCatalog,prorationCatalogPrice} from '../../../../lib/proration-catalog';
const preview=centralRoute(async(request,client,session)=>{
 if(!['owner','admin'].includes(session.role))throw new OperationError('Prévia restrita a gestores da Central.',403);
 const params=new URL(request.url).searchParams,contractId=params.get('contractId'),nextPlanId=params.get('nextPlanId');
 if(!contractId||!uuidPattern.test(contractId)||!nextPlanId||!/^[a-zA-Z0-9_-]{1,100}$/.test(nextPlanId))throw new OperationError('Selecione contrato e plano válidos.');
 const [contract,cycle,snapshot]=await Promise.all([
  client.from('saas_unit_contracts').select('id,status,plan_id,payer_unit_id,module_decisions,updated_at').eq('id',contractId).maybeSingle(),
  client.from('saas_proration_cycles').select('*').eq('contract_id',contractId).maybeSingle(),
  client.rpc('proration_catalog_preview_pilot',{p_plan:nextPlanId})
 ]);
 if([contract,cycle,snapshot].some(result=>result.error))throw new OperationError('Não foi possível validar os dados da prévia.',503);
 let catalog:ReturnType<typeof readProrationCatalog>;
 try{catalog=readProrationCatalog(snapshot.data,nextPlanId)}catch{throw new OperationError('Catálogo não confirmado. Atualize a consulta.',409)}
 const c=contract.data,cy=cycle.data,p=catalog.plan;
 if(!c||!cy||!p||c.status!=='active'||!p.active||p.billing_cycle!=='monthly'||cy.contract_updated_at!==c.updated_at)throw new OperationError('Contrato ou ciclo exige revisão antes da prévia.',409);
 const safe=(value:unknown)=>{try{return safeProrationNumber(value)}catch{throw new OperationError('Valor fora da precisão suportada.',409)}};
 let nextNet:number;try{nextNet=prorationCatalogPrice(catalog,c.module_decisions||{})}catch{throw new OperationError('Preço não confirmado.',409)}
 let estimate;
 try{estimate=previewCumulativeProration({currentNetCents:safe(cy.net_cents),nextNetCents:nextNet,cycleStart:safe(cy.cycle_start),cycleEnd:safe(cy.cycle_end),effectiveAt:Date.now(),accumulatedNumerator:exactProrationInteger(cy.accumulated_numerator,true),roundedAdjustmentCents:exactProrationInteger(cy.rounded_adjustment,true)})}catch{throw new OperationError('Período ou histórico exige revisão. Atualize a consulta.',409)}
 return{pilot:true,estimate,expectedCatalog:catalog,contractId,nextPlanId:p.id,nextPlanName:p.name,payerUnitId:c.payer_unit_id,expectedUpdatedAt:c.updated_at,baseInvoiceId:cy.invoice_id,confirmationAvailable:false,notice:'Estimativa sem reserva de preço. A confirmação deverá revalidar permissões, catálogo e ciclo na transação.'};
});
export async function GET(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Prévia disponível somente no ambiente de homologação isolado.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return preview(request);
}
