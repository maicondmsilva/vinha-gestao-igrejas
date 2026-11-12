import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {memberFields,memberError} from '../../../shared/member-profile';
import {profileJourneys} from '../../../shared/member-profile-diff';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
// Pessoas › Perfis pendentes. Abre para dono/administrador/pastor ou para quem recebeu
// "Perfis pendentes"; o banco confere a igreja de cada pedido.
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage',['people.pending_profiles:view','people.pending_profiles:approve']);if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let b:{id?:string;fields?:string[];reason?:string;person?:string;journey?:string}={};
 if(write){try{b=JSON.parse(new TextDecoder().decode(await boundedBody(request,8000)));
  if(!b||!uuidPattern.test(b.id||'')||!Array.isArray(b.fields)||new Set(b.fields).size!==b.fields.length||b.fields.some(k=>!memberFields.some(([f])=>f===k))||typeof b.reason!=='string'||b.reason.trim().length<5||b.reason.length>1000
   ||b.person!==undefined&&b.person!==''&&!uuidPattern.test(b.person)||b.journey!==undefined&&b.journey!==''&&!profileJourneys.some(([j])=>j===b.journey)
   ||Object.keys(b).some(k=>!['id','fields','reason','person','journey'].includes(k)))throw Error();}catch{return json({error:'Selecione os campos e informe um motivo com pelo menos cinco caracteres.'},400)}}
 const r=await db(request).rpc('member_profile_review2' as never,{p_org:auth.access!.membership.organization_id,p_action:write?'review':'list',p_id:b.id||null,p_data:write?{fields:b.fields,reason:b.reason,person:b.person||'',journey:b.journey||''}:{}} as never) as unknown as {data:{ok?:boolean;id?:string}|null;error:{code?:string;message:string}|null};
 if(r.error)return json({error:memberError(r.error.code,r.error.message)},r.error.code==='42501'?403:r.error.code==='40001'?409:r.error.code==='22023'?400:503);
 if(write&&(r.data?.ok!==true||r.data.id!==b.id))return json({error:'Revisão não confirmada. Atualize a lista antes de repetir.'},503);
 return json(r.data);
 }catch{return json({error:'Conexão interrompida. Atualize antes de repetir.'},503)}}
export const GET=(r:Request)=>run(r,false);
export const PATCH=(r:Request)=>run(r,true);
