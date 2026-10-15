import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {check,rpc,type OperationsClient} from '../../lib/supabase/operations';
export async function GET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:403});
 if(!['owner','admin'].includes(auth.access!.membership.role))return NextResponse.json({error:'Somente responsáveis administrativos podem consultar contratos.'},{status:403});
 try{const client=auth.access!.client as unknown as OperationsClient;return NextResponse.json({contracts:check(await client.from('saas_unit_contracts').select('*').eq('organization_id',auth.access!.membership.organization_id)),units:check(await client.from('organization_units').select('id,name,registration_code').eq('organization_id',auth.access!.membership.organization_id)),modules:await rpc(client,'unit_contract_module_directory')},{headers:{'cache-control':'no-store'}})}catch{return NextResponse.json({error:'Não foi possível consultar os contratos.'},{status:400})}
}
export async function POST(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return NextResponse.json({error:'Origem inválida.'},{status:403});
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:403});
 try{const d=await request.json<{unitId:string;modules:string[];dueDay:number;autopayRequested:boolean}>(),client=auth.access!.client as unknown as OperationsClient;await rpc(client,'request_unit_modules',{p_unit:d.unitId,p_modules:d.modules,p_due_day:Number(d.dueDay),p_autopay:!!d.autopayRequested});return NextResponse.json({ok:true})}catch{return NextResponse.json({error:'Não foi possível salvar a solicitação. Verifique a unidade e os módulos.'},{status:400})}
}
