import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedChurchJson} from '../../lib/church-json';
import {flowCommand,flowQuery,flowPage,flowUuid} from '../../lib/cell-flows';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{const access=auth.access!,client=access.client as unknown as OperationsClient;let unitId:string,args:Record<string,unknown>,query:ReturnType<typeof flowQuery>|undefined;
  try{if(write){const p=new URL(request.url).searchParams;if(p.getAll('unitId').length!==1)throw Error();unitId=flowUuid(p.get('unitId'));const c=flowCommand(await boundedChurchJson(request,4096));args={p_organization:access.membership.organization_id,p_unit:unitId,p_kind:c.kind,p_id:c.id,p_version:c.version,p_data:c.data}}else{query=flowQuery(request);unitId=query.unitId;args={p_organization:access.membership.organization_id,p_unit:unitId,p_kind:query.kind,p_after:query.after}}}catch{return NextResponse.json({error:'Revise os campos e a unidade selecionada.'},{status:400,headers})}
  if(!access.membership.units.some(u=>u.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
  const {data,error}=await client.rpc(write?'cell_flows_save':'cell_flows_read',args);
  if(error){const status=error.code==='42501'?403:['40001','23505','40P01'].includes(error.code)?409:error.code?.startsWith('22')||error.code==='23514'?400:503;return NextResponse.json({error:status===403?'Acesso, unidade, membro ou emissor não estão mais disponíveis para esta operação.':status===409?'O vínculo mudou, já existe uma solicitação pendente ou o membro já está no destino. Atualize antes de repetir.':status===400?'Revise a hierarquia: não são permitidos ciclos ou mais de 32 níveis. Transferências exigem vínculos válidos na mesma unidade.':'Não foi possível concluir. Atualize antes de repetir.'},{status,headers})}
  if(write){if(flowUuid(data?.id)!==args.p_id||!Number.isSafeInteger(data?.version)||data.version<1)throw Error();return NextResponse.json({id:data.id,version:data.version},{headers})}
  const page=flowPage(data);if(page.unitId!==unitId||page.kind!==query!.kind)throw Error();return NextResponse.json(page,{headers});
 }catch{return NextResponse.json({error:'Não foi possível validar a resposta. Atualize antes de repetir.'},{status:503,headers})}
}
