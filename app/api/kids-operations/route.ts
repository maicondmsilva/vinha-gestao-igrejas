import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {kidsOperationCommand,kidsOperationsQuery,kidsOperationsPage,kidsAdmissionPage} from '../../lib/kids-operations';
const json=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 let query;try{query=kidsOperationsQuery(request)}catch{return json({error:'Selecione uma igreja e filtros válidos.'},400)}
 const access=auth.access!;if(!access.membership.units.some(u=>u.id===query.unitId))return json({error:'Igreja sem acesso.'},403);
 let command;
 if(write){
  if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return json({error:'Formato inválido.'},400);
  try{const reader=request.body?.getReader();if(!reader)throw Error();const chunks:Uint8Array[]=[];let size=0;
   for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>16384){await reader.cancel();return json({error:'Formulário muito extenso.'},413)}chunks.push(part.value)}
   const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length}command=kidsOperationCommand(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)));
  }catch{return json({error:'Revise os campos, os cadastros vinculados e a conferência de identidade.'},400)}
 }
 try{
  const client=access.client as unknown as OperationsClient;
  const r=await client.rpc(command?'kids_operations_save':query.q!==null?'kids_admission_choices':'kids_operations_page',{p_organization:access.membership.organization_id,p_unit:query.unitId,...command?{p_request:command.requestId,p_action:command.action,p_id:command.id,p_version:command.version,p_data:command.data}:query.q!==null?{p_session:query.sessionId,p_search:query.q}:{p_session:query.sessionId,p_after:query.after,p_search:query.search,p_status:query.status}});
  if(r.error){const code=r.error.code,m=r.error.message||'',status=['42501','28000'].includes(code)?403:['40001','40P01','23505'].includes(code)?409:code==='P0002'?404:['22023','22P02','23514','23502','22007','22008'].includes(code)?400:503;
   const messages:Record<string,string>={kids_children_present:'Há crianças presentes. Conclua todas as retiradas antes de encerrar.',kids_capacity_full:'A sala está lotada. Atualize a ocupação.',kids_reserved_capacity:'Há vagas reservadas por outras famílias. Atualize a consulta e confira as reservas com a administração.',kids_staff_insufficient:'A equipe mínima da sala não está disponível. Confira a escala e os acessos.',kids_staff_identity_required:'A pessoa da equipe precisa ser adulta, estar ativa em Pessoas e vinculada a uma conta confirmada com acesso à igreja.',kids_staff_overlap:'Essa pessoa já está escalada nesta sessão ou em outra com horário sobreposto.',kids_room_overlap:'A sala está em uso em outra sessão com horário sobreposto.',kids_guardian_required:'O adulto precisa ter autorização de retirada vigente. Confira sua identidade e o cadastro.',kids_receipt_recovery_required:'Comprovante expirado ou tentativas esgotadas. Solicite recuperação assistida à supervisão.',kids_hold_or_transfer_pending:'Há proteção de retirada ou transferência pendente. Procure a supervisão.',kids_age_outside_class:'A idade da criança não corresponde à turma.',kids_child_not_ready:'O cadastro da criança precisa estar ativo e revisado.',kids_receiving_team_required:'A equipe da sala de destino deve confirmar o recebimento.',kids_session_not_ready:'Confira o horário e adicione salas à sessão.',kids_room_in_use:'A sala não pode ser alterada durante uma sessão aberta.',kids_class_in_use:'A turma não pode ser alterada durante uma sessão aberta.'};
   return json({error:messages[m]||(status===403?'Operação não autorizada para esta conta, igreja ou contrato.':status===409?'Os dados mudaram ou já existe um registro. Atualize e confira antes de repetir.':status===400?'Revise os campos, a idade, a equipe e a situação da sessão.':status===404?'Registro não encontrado nesta igreja.':'Não foi possível confirmar a operação. Atualize e consulte o histórico antes de repetir.')},status);
  }
  return json(command?r.data:query.q!==null?{unitId:query.unitId,items:kidsAdmissionPage(r.data,query.unitId)}:kidsOperationsPage(r.data,query.unitId));
 }catch{return json({error:'Kids indisponível. A operação não foi confirmada; mantenha a criança sob os cuidados da equipe e confira o histórico.'},503)}
}
