import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {boundedBody} from '../../../../lib/private-files';
import {issueProrationCommand} from '../../../../lib/proration-issue-command';
const issue=centralRoute(async(request,client)=>{
 if(request.headers.get('origin')!==new URL(request.url).origin)throw new OperationError('Origem inválida.',403);
 let data:ReturnType<typeof issueProrationCommand>;
 try{data=issueProrationCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,4096))))}catch{throw new OperationError('Revise o contrato, o período e o identificador do pedido.')}
 const result=await client.rpc('issue_proration_cycle_invoice_pilot',{p_data:data});
 if(result.error)throw new OperationError(result.error.code==='42501'?'Acesso ao faturamento negado.':'Emissão recusada. Revise o ciclo e a existência de fatura para o período.',result.error.code==='42501'?403:409);
 if(!result.data||result.data.requestId!==data.requestId||result.data.contractId!==data.contractId)throw new OperationError('Resultado não confirmado. Preserve o pedido e consulte o histórico.',503);
 return{ok:true,invoice:result.data,providerChargeCreated:false};
});
export async function POST(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Faturamento proporcional disponível somente em homologação isolada e autorizada.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return issue(request);
}
