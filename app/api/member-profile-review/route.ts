import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {memberFields,memberError} from '../../../shared/member-profile';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let b:{id?:string;fields?:string[];reason?:string}={};
 if(write){try{b=JSON.parse(new TextDecoder().decode(await boundedBody(request,8000)));if(!b||!uuidPattern.test(b.id||'')||!Array.isArray(b.fields)||new Set(b.fields).size!==b.fields.length||b.fields.some(k=>!memberFields.some(([f])=>f===k))||typeof b.reason!=='string'||b.reason.trim().length<5||b.reason.length>1000||Object.keys(b).some(k=>!['id','fields','reason'].includes(k)))throw Error();}catch{return json({error:'Selecione os campos e informe um motivo com pelo menos cinco caracteres.'},400)}}
 const r=await db(request).rpc('member_profile_review',{p_org:auth.access!.membership.organization_id,p_action:write?'review':'list',p_id:b.id||null,p_fields:b.fields||[],p_reason:b.reason||''});
 if(r.error)return json({error:memberError(r.error.code,r.error.message)},r.error.code==='42501'?403:r.error.code==='40001'?409:r.error.code==='22023'?400:503);
 if(write&&(r.data?.ok!==true||r.data.id!==b.id))return json({error:'Revisão não confirmada. Atualize a lista antes de repetir.'},503);
 return json(r.data);
 }catch{return json({error:'Conexão interrompida. Atualize antes de repetir.'},503)}}
export const GET=(r:Request)=>run(r,false);
export const PATCH=(r:Request)=>run(r,true);
