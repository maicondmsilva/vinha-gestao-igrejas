import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {boundedBody} from '../../../../lib/private-files';
import {payerChangeCommand} from '../../../../lib/proration-payer-command';
const change=centralRoute(async(request,client)=>{
 if(request.headers.get('origin')!==new URL(request.url).origin)throw new OperationError('Origem inválida.',403);
 let data:ReturnType<typeof payerChangeCommand>;
 try{data=payerChangeCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,4096))))}catch{throw new OperationError('Revise contrato, pagador, versão e justificativa.');}
 const result=await client.rpc('change_proration_payer_pilot',{p_data:data});
 if(result.error)throw new OperationError(result.error.code==='42501'?'Pagador indisponível ou acesso negado.':'Troca recusada. Atualize o ciclo e confira faturas já emitidas.',result.error.code==='42501'?403:409);
 if(!result.data||result.data.requestId!==data.requestId||result.data.contractId!==data.contractId||result.data.payerUnitId!==data.payerUnitId)throw new OperationError('Resultado não confirmado. Preserve o pedido e consulte o histórico.',503);
 return{ok:true,change:result.data};
});
export async function POST(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Troca de pagador disponível somente no ambiente de homologação isolado.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return change(request);
}
