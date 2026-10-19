import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {cellInput,cellPage,cellUuid} from '../../lib/cell-directory';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 // units.read identifies the tenant only; RPC enforces role, actual unit and cells entitlement.
 const auth=await authorizeSupabaseChurch(request,'units.read');
 if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{
 const url=new URL(request.url),units=url.searchParams.getAll('unitId'),after=url.searchParams.getAll('after');
 if(units.length!==1||!cellUuid.test(units[0])||after.length>1||(after.length===1&&!cellUuid.test(after[0])))return NextResponse.json({error:'Selecione uma unidade válida.'},{status:400,headers});
 const unitId=units[0];
 if(!auth.access!.membership.units.some(u=>u.id===unitId))return NextResponse.json({error:'Unidade sem acesso.'},{status:403,headers});
 const client=auth.access!.client as unknown as OperationsClient;
 let args:Record<string,unknown>={p_organization:auth.access!.membership.organization_id,p_unit:unitId,p_after:after[0]||null};
 if(write){
  if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return NextResponse.json({error:'Formato inválido.'},{status:400,headers});
  const reader=request.body?.getReader();if(!reader)return NextResponse.json({error:'Cadastro ausente.'},{status:400,headers});
  const chunks:Uint8Array[]=[];let size=0;
  for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>8192){await reader.cancel();return NextResponse.json({error:'Cadastro muito extenso.'},{status:413,headers})}chunks.push(part.value)}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}
  let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));if(!body||Object.keys(body).sort().join(',')!=='data,id,version'||typeof body.id!=='string'||!cellUuid.test(body.id)||!Number.isSafeInteger(body.version)||body.version<0)throw Error();body.data=cellInput(body.data)}catch{return NextResponse.json({error:'Revise os campos do cadastro.'},{status:400,headers})}
  args={p_organization:auth.access!.membership.organization_id,p_unit:unitId,p_id:body.id,p_version:body.version,p_data:body.data};
 }
 const {data,error}=await client.rpc(write?'cell_directory_save':'cell_directory_list_v2',args);
 if(error){const code=error.code;return NextResponse.json({error:code==='42501'?'Células não autorizado para esta unidade, papel ou contrato.':code==='40001'?'Este cadastro mudou. Atualize a lista antes de tentar novamente.':['22023','23514','22P02'].includes(code)?'Revise os campos do cadastro.':'Não foi possível concluir. Atualize a lista antes de tentar novamente.'},{status:code==='42501'?403:code==='40001'?409:['22023','23514','22P02'].includes(code)?400:503,headers})}
 if(!write){const page=cellPage(data);if(page.unitId!==unitId)throw Error();return NextResponse.json(page,{headers})}
 if(!data||typeof data.id!=='string'||!cellUuid.test(data.id)||!Number.isSafeInteger(data.version)||data.version<1)throw Error();
 return NextResponse.json({id:data.id,version:data.version},{headers});
 }catch{return NextResponse.json({error:'Não foi possível concluir. Atualize a lista antes de tentar novamente.'},{status:503,headers})}
}
