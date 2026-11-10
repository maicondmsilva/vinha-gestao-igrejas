import {eventModuleError} from '../../../shared/event-validation';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {programmingCommand} from '../../lib/programming-command';
import {agendaError} from '../../../shared/member-agenda';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(request:Request)=>run(request,false);
export const POST=(request:Request)=>run(request,true);
async function run(request:Request,write:boolean){try{
 // Each action is authorized by the database (agenda and entrance grants for secretaries and leaders).
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let command;
 if(write){try{command=programmingCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,100000))))}catch{return json({error:'Revise os dados informados.'},400)}if(!command)return json({error:'Revise os dados, datas e versões.'},400)}
 else{const q=new URL(request.url).searchParams,unit=q.get('unit')||'',action=q.get('action')||'list',id=q.get('id');if(!uuidPattern.test(unit)||id&&!uuidPattern.test(id)||!['list','calendar','detail','attendees','categories'].includes(action))return json({error:'Consulta inválida.'},400);command={unit,action,id,version:null,data:Object.fromEntries(['search','status','kind','category','section','page','size','sort','from','to'].flatMap(k=>q.has(k)?[[k,q.get(k)]]:[]))}}
 const client=db(request),[r,zone]=await Promise.all([client.rpc('programming_admin',{p_org:auth.access!.membership.organization_id,p_unit:command.unit,p_action:command.action,p_id:command.id,p_version:command.version,p_data:command.data}),write?null:client.rpc('unit_timezone',{p_unit:command.unit})]);
 if(r.error)return json({error:eventModuleError(r.error.message,r.error.code)||(r.error.code==='23505'?'Já existe uma categoria com esse nome. Atualize a lista.':agendaError(r.error.message))},r.error.code==='42501'?403:['40001','23505'].includes(r.error.code)?409:['22023','22007','22008','22P02','23514'].includes(r.error.code)?400:503);
 if(write&&r.data?.ok!==true)return json({error:'Operação não confirmada. Consulte os registros antes de repetir.'},503);
 // Reads carry the church's time zone so the panel shows and edits times in it.
 return json(!write&&r.data&&typeof r.data==='object'&&!Array.isArray(r.data)&&typeof zone?.data==='string'?{...r.data,timezone:zone.data}:r.data);
 }catch{return json({error:'Não foi possível confirmar a operação. Atualize a consulta antes de repetir.'},503)}}
