import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {boundedBody} from '../../../../lib/private-files';
import {cancellationCommand} from '../../../../lib/proration-cancellation-command';
const cancel=centralRoute(async(request,client)=>{
 if(request.headers.get('origin')!==new URL(request.url).origin)throw new OperationError('Origem inválida.',403);
 let data:ReturnType<typeof cancellationCommand>;
 try{data=cancellationCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,4096))))}catch{throw new OperationError('Revise contrato, fatura e justificativa.');}
 const result=await client.rpc('cancel_proration_invoice_pilot',{p_data:data});
 if(result.error)throw new OperationError(result.error.code==='42501'?'Acesso ao cancelamento negado.':'Cancelamento recusado. Faturas pagas, externas ou usadas em ciclos exigem revisão específica.',result.error.code==='42501'?403:409);
 if(!result.data||result.data.requestId!==data.requestId||result.data.contractId!==data.contractId||result.data.invoiceId!==data.invoiceId||result.data.status!=='cancelled')throw new OperationError('Resultado não confirmado. Preserve o pedido e consulte o histórico.',503);
 return{ok:true,cancellation:result.data,providerCancellationCreated:false};
});
export async function POST(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Cancelamento disponível somente no ambiente de homologação isolado.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return cancel(request);
}
