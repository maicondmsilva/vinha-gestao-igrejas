import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {boundedBody} from '../../../../lib/private-files';
import {planConfirmationCommand} from '../../../../lib/plan-change-command';
const change=centralRoute(async(request,client)=>{
 if(request.headers.get('origin')!==new URL(request.url).origin)throw new OperationError('Origem inválida.',403);
 let data:ReturnType<typeof planConfirmationCommand>;
 try{data=planConfirmationCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,262144))))}catch{throw new OperationError('Revise identificadores, versão, catálogo e período do contrato.')}
 const result=await client.rpc('confirm_unit_contract_plan_pilot',{p_data:data});
 if(result.error)throw new OperationError(result.error.code==='42501'?'Acesso à alteração de contrato negado.':result.error.code==='40001'?'Contrato alterado ou ciclo não validado. Atualize a consulta antes de continuar.':'Alteração recusada. Revise a fatura-base e o ciclo; nenhuma cobrança externa foi efetuada.',result.error.code==='42501'?403:result.error.code==='40001'?409:400);
 if(!result.data||result.data.requestId!==data.requestId||result.data.contractId!==data.contractId)throw new OperationError('Resultado não confirmado. Preserve o identificador e consulte o histórico antes de repetir.',503);
 return{ok:true,change:result.data,providerChargeCreated:false};
});
export async function POST(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Alteração proporcional disponível somente em homologação isolada e autorizada.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return change(request);
}
