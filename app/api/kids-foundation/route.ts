import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {kidsCommand,kidsPage,kidsQuery} from '../../lib/kids-foundation';
import {memberChoicePage} from '../../lib/member-choice';
const headers={'Cache-Control':'private, no-store'};
const json=(data:unknown,status=200)=>NextResponse.json(data,{status,headers});
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');
 if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 let query;try{query=kidsQuery(request)}catch{return json({error:'Selecione uma igreja e filtros válidos.'},400)}
 const access=auth.access!;
 if(!access.membership.units.some(u=>u.id===query.unitId))return json({error:'Igreja sem acesso.'},403);
 let command;
 if(write){
  if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return json({error:'Formato inválido.'},400);
  try{
   const reader=request.body?.getReader();if(!reader)throw Error();const chunks:Uint8Array[]=[];let size=0;
   for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>16384){await reader.cancel();return json({error:'Cadastro muito extenso.'},413)}chunks.push(part.value)}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}
   command=kidsCommand(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)));
  }catch{return json({error:'Revise os campos do cadastro.'},400)}
 }
 try{
  const client=access.client as unknown as OperationsClient;
  const result=await client.rpc(write?'kids_save':query.q!==null?'kids_choices':'kids_directory',{
   p_organization:access.membership.organization_id,p_unit:query.unitId,
   ...(command?{p_request:command.requestId,p_action:command.action,p_id:command.id,p_version:command.version,p_data:command.data}:query.q!==null?{p_search:query.q}:{p_profile:query.profileId,p_after:query.after,p_search:query.search}),
  });
  if(result.error){const code=result.error.code,status=code==='42501'||code==='28000'?403:code==='40001'||code==='23505'?409:code==='P0002'?404:['22023','22P02','23514','22007','22008','23502'].includes(code)?400:503;
   return json({error:status===403?'Kids não autorizado para esta conta, igreja ou contrato.':status===409?'Cadastro alterado ou pessoa já cadastrada. Atualize e consulte os registros existentes antes de repetir.':status===404?'Cadastro não encontrado nesta igreja.':status===400?'Revise os dados, a idade e as autorizações informadas.':'Não foi possível confirmar a operação. Atualize antes de tentar novamente.'},status);
  }
  return json(command?result.data:query.q!==null?memberChoicePage(result.data,query.unitId):kidsPage(result.data,query.unitId));
 }catch{return json({error:'Kids temporariamente indisponível. Nenhuma confirmação de gravação foi recebida.'},503)}
}
