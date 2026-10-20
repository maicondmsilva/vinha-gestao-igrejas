import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedChurchJson} from '../../lib/church-json';
import {networkCommand,networkPage,networkQuery,networkUuid} from '../../lib/cell-networks';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{const access=auth.access!,client=access.client as unknown as OperationsClient;let unitId:string,args:Record<string,unknown>,query:ReturnType<typeof networkQuery>|undefined;
  try{if(write){const p=new URL(request.url).searchParams;if(p.getAll('unitId').length!==1)throw Error();unitId=networkUuid(p.get('unitId'));const c=networkCommand(await boundedChurchJson(request,8192));args={p_organization:access.membership.organization_id,p_unit:unitId,p_kind:c.kind,p_id:c.id,p_version:c.version,p_data:c.data}}else{query=networkQuery(request);unitId=query.unitId;args={p_organization:access.membership.organization_id,p_unit:unitId,p_kind:query.kind,p_network:query.networkId,p_after:query.after}}}catch{return NextResponse.json({error:'Revise os campos e selecione uma unidade válida.'},{status:400,headers})}
  if(!access.membership.units.some(u=>u.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
  const {data,error}=await client.rpc(write?'cell_networks_save':'cell_networks_read',args);
  if(error){const status=error.code==='42501'?403:['40001','23505'].includes(error.code)?409:error.code?.startsWith('22')||error.code==='23514'?400:503;return NextResponse.json({error:status===403?'Acesso não autorizado para esta unidade, papel, grupo ou contrato.':status===409?'O registro mudou ou já existe uma rede ativa com esse nome. Atualize antes de repetir.':status===400?'Revise os dados. Grupo, rede e membro escolhido devem estar ativos na mesma unidade.':'Não foi possível concluir. Atualize antes de repetir.'},{status,headers})}
  if(write){if(networkUuid(data?.id)!==args.p_id||!Number.isSafeInteger(data?.version)||data.version<1)throw Error();return NextResponse.json({id:data.id,version:data.version},{headers})}
  const page=networkPage(data);if(page.unitId!==unitId||page.kind!==query!.kind||page.networkId!==query!.networkId)throw Error();return NextResponse.json(page,{headers});
 }catch{return NextResponse.json({error:'Não foi possível validar a resposta. Atualize antes de repetir.'},{status:503,headers})}
}
