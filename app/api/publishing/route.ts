import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {publishingCommand} from '../../lib/publishing-command';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(request:Request)=>run(request,false);export const POST=(request:Request)=>run(request,true);
async function run(request:Request,write:boolean){try{const a=await authorizeSupabaseChurch(request,'units.read');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);
 let b;if(write){try{b=publishingCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,24000))))}catch{}if(!b)return json({error:'Revise os campos, links e destinatários.'},400)}else{const q=new URL(request.url).searchParams,unit=q.get('unit')||'';if(!uuidPattern.test(unit))return json({error:'Selecione uma igreja válida.'},400);b={unit,action:'list',id:null,version:null,data:Object.fromEntries(['kind','search','status','page','size'].flatMap(k=>q.has(k)?[[k,q.get(k)]]:[]))}}
 const r=await db(request).rpc('publishing_admin',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_action:b.action,p_id:b.id,p_version:b.version,p_data:b.data});
 if(r.error)return json({error:r.error.code==='42501'?'Seu acesso não permite esta publicação ou algum dos destinos.':r.error.code==='40001'?'O conteúdo, grupo ou acesso mudou. Atualize e confira os destinatários antes de repetir.':'Revise os campos, vínculos e igrejas de destino.'},r.error.code==='42501'?403:r.error.code==='40001'?409:400);
 if(write&&r.data?.ok!==true)return json({error:'Sem confirmação. Consulte a lista antes de repetir.'},503);return json(r.data);
 }catch{return json({error:'Conexão interrompida. Consulte a lista antes de repetir.'},503)}}
