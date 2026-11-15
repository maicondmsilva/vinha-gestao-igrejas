import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {birthdaysQuery} from '../../../lib/birthdays';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
type Rpc={rpc:(n:string,a:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{code?:string;message:string}|null}>};
// Pessoas › Aniversariantes. O banco confere a igreja e quem pode ver cada pessoa.
export async function GET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{
  let input;try{input=birthdaysQuery(request)}catch(e){return json({error:e instanceof Error?e.message:'Pedido inválido.'},400)}
  if(!auth.access!.membership.units.some(u=>u.id===input.unit))return json({error:'Igreja sem acesso.'},403);
  const r=await (auth.access!.client as unknown as Rpc).rpc('people_birthdays',{p_org:auth.access!.membership.organization_id,p_unit:input.unit,p_range:input.range});
  if(r.error)return json({error:r.error.code==='42501'?'Você não pode ver os aniversariantes desta igreja.':'Não foi possível consultar agora.'},r.error.code==='42501'?403:503);
  return json({...(r.data as object),church:auth.access!.membership.organization_name});
 }catch{return json({error:'Não foi possível consultar agora.'},503)}
}
