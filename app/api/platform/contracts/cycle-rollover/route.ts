import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {boundedBody} from '../../../../lib/private-files';
import {rolloverCommand} from '../../../../lib/plan-change-command';
const rollover=centralRoute(async(request,client)=>{
 if(request.headers.get('origin')!==new URL(request.url).origin)throw new OperationError('Origem inválida.',403);
 let data:ReturnType<typeof rolloverCommand>;
 try{data=rolloverCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,4096))))}catch{throw new OperationError('Revise o contrato, a fatura e a versão do ciclo.')}
 const result=await client.rpc('rollover_proration_cycle_pilot',{p_data:data});
 if(result.error)throw new OperationError(result.error.code==='42501'?'Acesso ao faturamento negado.':result.error.code==='40001'?'Contrato alterado. Atualize a consulta e revise o ciclo.':'Virada recusada. Confira se o período já começou e se a fatura é a correta.',result.error.code==='42501'?403:409);
 if(!result.data||result.data.requestId!==data.requestId||result.data.contractId!==data.contractId)throw new OperationError('Resultado não confirmado. Preserve o pedido e consulte o histórico.',503);
 return{ok:true,cycle:result.data,providerChargeCreated:false};
});
export async function POST(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Virada de ciclo disponível somente em homologação isolada e autorizada.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return rollover(request);
}
