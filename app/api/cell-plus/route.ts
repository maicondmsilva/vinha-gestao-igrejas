import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedChurchJson} from '../../lib/church-json';
import {plusCommand,plusPage,plusQuery,plusUuid} from '../../lib/cell-plus';
const headers={'Cache-Control':'private, no-store'};
export async function GET(r:Request){return handle(r,false)}
export async function POST(r:Request){return handle(r,true)}
async function handle(request:Request,write:boolean){const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{const access=auth.access!,client=access.client as unknown as OperationsClient;let unitId:string,args:Record<string,unknown>,query:ReturnType<typeof plusQuery>|undefined;
 try{if(write){const p=new URL(request.url).searchParams;if(p.getAll('unitId').length!==1)throw Error();unitId=plusUuid(p.get('unitId'));const c=plusCommand(await boundedChurchJson(request,32768));args={p_org:access.membership.organization_id,p_unit:unitId,p_kind:c.kind,p_id:c.id,p_version:c.version,p_data:c.data}}else{query=plusQuery(request);unitId=query.unitId;args={p_org:access.membership.organization_id,p_unit:unitId,p_kind:query.kind,p_network:query.networkId,p_after:query.after,p_from:query.from,p_to:query.to,p_cell:query.cellId}}}catch{return NextResponse.json({error:'Revise os campos, a unidade e o período (até 366 dias).'},{status:400,headers})}
 if(!access.membership.units.some(u=>u.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
 const {data,error}=await client.rpc(write?'cell_plus_save':'cell_plus_read',args);
 if(error){const status=error.code==='42501'?403:['40001','23505','40P01'].includes(error.code)?409:error.code?.startsWith('22')||error.code==='23514'?400:503;return NextResponse.json({error:status===403?'Esta ação não está autorizada no seu escopo atual.':status===409?'O registro mudou ou já existe um vínculo/indicação. Atualize antes de repetir.':status===400?'Revise os dados. Para aceitar indicação ou conceder supervisão, selecione um membro ativo; supervisores precisam de conta com acesso prévio à unidade.':'Consulta indisponível. Atualize ou reduza o escopo antes de repetir.'},{status,headers})}
 if(write){if(plusUuid(data?.id)!==args.p_id||!Number.isSafeInteger(data?.version)||data.version<1||!Number.isSafeInteger(data?.notificationsCreated)||data.notificationsCreated<0)throw Error();return NextResponse.json(data,{headers})}
 const p=plusPage(data);if(p.unitId!==unitId||p.kind!==query!.kind||p.networkId!==query!.networkId||p.cellId!==query!.cellId||p.from!==query!.from||p.to!==query!.to)throw Error();return NextResponse.json(p,{headers});
 }catch{return NextResponse.json({error:'Não foi possível validar a resposta. Atualize antes de repetir.'},{status:503,headers})}
}
