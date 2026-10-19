import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import type {OperationsClient} from '../../../lib/supabase/operations';
import {summaryUnit,peopleSummary} from '../../../lib/people-summary';
export async function GET(request:Request){
 const headers={'Cache-Control':'private, no-store'};
 const auth=await authorizeSupabaseChurch(request,'people.read');
 if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 let unitId:string;try{unitId=summaryUnit(request)}catch{return NextResponse.json({error:'Selecione uma unidade válida.'},{status:400,headers})}
 if(!auth.access!.membership.units.some(unit=>unit.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
 const client=auth.access!.client as unknown as OperationsClient;
 const {data,error}=await client.rpc('people_summary_report',{p_organization:auth.access!.membership.organization_id,p_unit:unitId});
 if(error)return NextResponse.json({error:error.code==='42501'?'Relatório não autorizado para esta unidade ou contrato.':'Não foi possível carregar o relatório.'},{status:error.code==='42501'?403:503,headers});
 try{return NextResponse.json(peopleSummary(data),{headers})}catch{return NextResponse.json({error:'Não foi possível validar o relatório.'},{status:503,headers})}
}
