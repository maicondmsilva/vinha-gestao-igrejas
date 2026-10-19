import {NextResponse} from 'next/server';
import {centralRoute,OperationError} from '../../../../lib/supabase/operations';
import {ledgerPilotEnabled} from '../../../../lib/ledger-pilot';
import {uuidPattern} from '../../../../lib/private-files';
import {summarizeProrationDocument} from '../../../../lib/proration-documents';
const list=centralRoute(async(request,client)=>{
 const contractId=new URL(request.url).searchParams.get('contractId');
 if(!contractId||!uuidPattern.test(contractId))throw new OperationError('Selecione um contrato válido.');
 const result=await client.from('saas_proration_documents').select('id,kind,amount_cents,created_at,saas_proration_credit_uses(amount_cents,saas_proration_credit_returns(amount_cents))').eq('contract_id',contractId).order('created_at',{ascending:false}).limit(101);
 if(result.error)throw new OperationError('Consulta indisponível ou não autorizada.',503);
 if((result.data||[]).length>100)throw new OperationError('O histórico exige paginação antes de exibir um saldo completo.',409);
 return{documents:(result.data||[]).map(summarizeProrationDocument),pilot:true};
});
export async function GET(request:Request){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return NextResponse.json({error:'Consulta disponível somente no piloto isolado.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 return list(request);
}
