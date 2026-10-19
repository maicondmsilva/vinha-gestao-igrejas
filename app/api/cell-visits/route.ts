import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedChurchJson} from '../../lib/church-json';
import {visitCommand,visitPage,visitQuery,visitUuid} from '../../lib/cell-visits';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{const access=auth.access!,client=access.client as unknown as OperationsClient;let unitId:string,args:Record<string,unknown>,query:ReturnType<typeof visitQuery>|undefined;
  try{if(write){const p=new URL(request.url).searchParams;if(p.getAll('unitId').length!==1)throw Error();unitId=visitUuid(p.get('unitId'));const c=visitCommand(await boundedChurchJson(request,8192));args={p_organization:access.membership.organization_id,p_unit:unitId,p_cell:c.cellId,p_id:c.id,p_version:c.version,p_data:c.data}}
   else{query=visitQuery(request);unitId=query.unitId;args={p_organization:access.membership.organization_id,p_unit:unitId,p_cell:query.cellId,p_from:query.from,p_to:query.to,p_after:query.after}}
  }catch{return NextResponse.json({error:'Revise os campos e o período de até 366 dias.'},{status:400,headers})}
  if(!access.membership.units.some(u=>u.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
  const {data,error}=await client.rpc(write?'cell_visits_save':'cell_visits_read',args);
  if(error){const status=error.code==='42501'?403:['40001','23505'].includes(error.code)?409:error.code?.startsWith('22')||error.code==='23514'?400:503;return NextResponse.json({error:status===403?'Acesso não autorizado para esta unidade, grupo ou contrato.':status===409?'A visita mudou ou o membro já tem uma visita registrada neste grupo e data. Atualize antes de repetir.':status===400?'Revise nome e data. A visita não pode ser futura; o membro selecionado deve estar ativo nesta unidade.':'Não foi possível concluir. Atualize antes de repetir.'},{status,headers})}
  if(write){if(visitUuid(data?.id)!==args.p_id||!Number.isSafeInteger(data?.version)||data.version<1)throw Error();return NextResponse.json({id:data.id,version:data.version},{headers})}
  const page=visitPage(data);if(page.unitId!==unitId||page.cellId!==query!.cellId||page.items.some(i=>i.visit_date<query!.from||i.visit_date>query!.to))throw Error();return NextResponse.json(page,{headers});
 }catch{return NextResponse.json({error:'Não foi possível validar a resposta. Atualize antes de repetir.'},{status:503,headers})}
}
