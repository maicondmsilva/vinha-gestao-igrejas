import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(request:Request){return run(request,false)}
export async function POST(request:Request){return run(request,true)}
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 const body=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,6000))):{unit:new URL(request.url).searchParams.get('unit'),action:'list',data:{}};
 if(!body||!uuidPattern.test(body.unit)||!['list','issue','revoke','verify','publish','price'].includes(body.action)||!body.data||typeof body.data!=='object'||Array.isArray(body.data))return json({error:'Revise os dados.'},400);
 const client=db(request),org=auth.access!.membership.organization_id;
 const r=body.action==='price'?await client.rpc('member_event_purchase',{p_org:org,p_unit:body.unit,p_action:'price',p_id:body.data.event,p_data:{amount:body.data.amount,purpose:body.data.purpose}}):body.action==='publish'?await client.rpc('member_payment_publish',{p_org:org,p_unit:body.unit,p_purpose:body.data.purpose,p_receiver:body.data.receiver,p_published:body.data.published}):await client.rpc('member_services_admin',{p_org:org,p_unit:body.unit,p_action:body.action,p_data:body.data});
 if(r.error)return json({error:'Não foi possível confirmar. Confira a igreja, as permissões e os dados atuais.'},r.error.code==='42501'?403:r.error.code==='40001'?409:400);
 return json(r.data);
 }catch{return json({error:'Falha de conexão ou dados inválidos. Atualize antes de repetir.'},503)}}
