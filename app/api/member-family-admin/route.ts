import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {parseFamilyAdmin} from '../../lib/member-family-command';
import {familyError} from '../../../shared/member-family';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function POST(request:Request){try{const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);let body;try{body=parseFamilyAdmin(JSON.parse(new TextDecoder().decode(await boundedBody(request,16000))))}catch{return json({error:'Revise os campos.'},400)}if(!body)return json({error:'Operação inválida.'},400);const r=await db(request).rpc('member_family_admin',{p_org:auth.access!.membership.organization_id,p_unit:body.unit,p_action:body.action,p_id:body.id,p_version:body.version,p_data:body.data,p_offset:body.offset});if(r.error)return json({error:familyError(r.error.message+' '+r.error.code)},r.error.code==='42501'?403:r.error.code==='40001'?409:['22023','22P02','23514','23502'].includes(r.error.code)?400:503);return json(r.data)}catch{return json({error:'Conexão interrompida. Atualize antes de repetir.'},503)}}
