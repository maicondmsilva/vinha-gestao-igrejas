import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedChurchJson} from '../../lib/church-json';
import {cellReadQuery,cellWriteInput,cellOperationsPage,operationUuid} from '../../lib/cell-operations';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{
  const access=auth.access!,client=access.client as unknown as OperationsClient;let unitId:string,args:Record<string,unknown>,query:ReturnType<typeof cellReadQuery>|undefined;
  try{
   if(write){const p=new URL(request.url).searchParams;if(p.getAll('unitId').length!==1)throw Error();unitId=operationUuid(p.get('unitId'));const command=cellWriteInput(await boundedChurchJson(request));args={p_organization:access.membership.organization_id,p_unit:unitId,p_kind:command.kind,p_cell:command.cellId,p_id:command.id,p_version:command.version,p_data:command.data}}
   else{query=cellReadQuery(request);unitId=query.unitId;args={p_organization:access.membership.organization_id,p_unit:unitId,p_kind:query.kind,p_cell:query.cellId,p_record:query.recordId,p_after:query.after,p_search:query.search,p_from:query.from,p_to:query.to}}
  }catch{return NextResponse.json({error:'Revise os campos, a unidade e o período (até 366 dias). Buscas de pessoas exigem pelo menos dois caracteres.'},{status:400,headers})}
  if(!access.membership.units.some(unit=>unit.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
  const {data,error}=await client.rpc(write?'cell_operations_save':'cell_operations_read',args);
  if(error){const status=error.code==='42501'?403:['40001','23505'].includes(error.code)?409:error.code?.startsWith('22')||error.code==='23514'?400:503;return NextResponse.json({error:status===403?'Acesso não autorizado para esta unidade, papel ou módulos contratados.':status===409?'O registro mudou ou já existe. Atualize a lista antes de tentar novamente.':status===400?'Revise os dados. Participantes precisam estar ativos na unidade; presenças devem pertencer à chamada original do encontro.':'Não foi possível concluir. Atualize a lista antes de repetir a operação.'},{status,headers})}
  if(write){const id=operationUuid(data?.id);if(id!==args.p_id||!Number.isSafeInteger(data?.version)||data.version<1)throw Error();return NextResponse.json({id,version:data.version},{headers})}
  const result=cellOperationsPage(data,query!.kind);if(result.unitId!==unitId||result.cellId!==query!.cellId)throw Error();return NextResponse.json(result,{headers});
 }catch{return NextResponse.json({error:'Não foi possível validar a resposta. Atualize antes de repetir a operação.'},{status:503,headers})}
}
