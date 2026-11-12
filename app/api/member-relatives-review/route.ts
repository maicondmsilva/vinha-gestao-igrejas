import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
type Rpc={rpc:(n:string,a:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{code?:string;message:string}|null}>};
const fail=(code?:string)=>code==='42501'?json({error:'Você não pode analisar este pedido.'},403):code==='40001'?json({error:'O pedido já foi analisado ou mudou. Atualize a lista.'},409):code==='23505'?json({error:'Essas pessoas já estão ligadas.'},409):code==='22023'?json({error:'Revise a decisão e o motivo.'},400):json({error:'Não foi possível concluir. Atualize e tente de novo.'},503);
// Pessoas › Perfis pendentes › Familiares: pedidos de inclusão de familiar enviados pelo aplicativo.
async function run(request:Request,write:boolean){try{
 const auth=await authorizeSupabaseChurch(request,'units.manage',['people.pending_profiles:view','people.pending_profiles:approve']);if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let data:Record<string,unknown>={};
 if(write){try{const b=JSON.parse(new TextDecoder().decode(await boundedBody(request,4000)));
  if(!b||typeof b!=='object'||Object.keys(b).some((k:string)=>!['id','decision','person','journey','reason'].includes(k))||!uuidPattern.test(b.id||'')||!['approve','reject'].includes(b.decision)
   ||b.person!==undefined&&b.person!==''&&!uuidPattern.test(b.person)||b.journey!==undefined&&!['','Membro','Em integração','Visitante'].includes(b.journey)
   ||b.reason!==undefined&&(typeof b.reason!=='string'||b.reason.length>500)||b.decision==='reject'&&(typeof b.reason!=='string'||b.reason.trim().length<5))throw Error();
  data={id:b.id,decision:b.decision,...(b.person?{person:b.person}:{}),...(b.journey?{journey:b.journey}:{}),...(b.reason?{reason:b.reason.trim()}:{})}}catch{return json({error:'Revise a decisão. Para não aprovar, informe o motivo (mínimo de 5 caracteres).'},400)}}
 const r=await (auth.access!.client as unknown as Rpc).rpc('member_relatives_admin',{p_org:auth.access!.membership.organization_id,p_action:write?'review':'list',p_data:data});
 if(r.error)return fail(r.error.code);
 return json(r.data);
}catch{return json({error:'Conexão interrompida. Atualize antes de repetir.'},503)}}
export const GET=(r:Request)=>run(r,false);
export const PATCH=(r:Request)=>run(r,true);
