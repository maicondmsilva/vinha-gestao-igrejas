import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {financeDate} from '../../lib/finance-f1';
import {receiverId} from '../../lib/finance-receivers';
import {digitalCommand} from '../../lib/finance-f4';
import {digitalConnection,digitalSync} from '../../lib/digital-provider';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
async function run(r:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 if(!['owner','admin','finance'].includes(a.membership.role))return json({error:'Sem permissão financeira.'},403);
 let unit:string,action:string,data:Record<string,unknown>;
 try{if(write){const c=digitalCommand(JSON.parse(new TextDecoder().decode(await boundedBody(r,16384))));unit=c.unit;action=c.action;data=c.data}else{const p=new URL(r.url).searchParams;if([...p.keys()].some(k=>!['unit','tenant','before','from','to','receipt'].includes(k)||p.getAll(k).length!==1))throw Error('Filtro inválido.');unit=receiverId(p.get('unit'));action='list';const before=p.get('before')||'';if(before){const [at,key,...rest]=before.split('|');if(rest.length||!/^\d{4}-\d\d-\d\dT.*(?:Z|[+-]\d\d:\d\d)$/.test(at)||!Number.isFinite(Date.parse(at)))throw Error('Página inválida.');receiverId(key)}const from=p.get('from')||'',to=p.get('to')||'';if((from||to)&&(!from||!to||financeDate(to)<financeDate(from)||(Date.parse(to)-Date.parse(from))/86400000>366))throw Error('Período inválido.');data={before,from,to};if(p.get('receipt')){action='detail';data={id:receiverId(p.get('receipt'))}}}}catch(e){return json({error:e instanceof Error?e.message:'Dados inválidos.'},400)}
 if(!a.membership.units.some(u=>u.id===unit))return json({error:'Igreja não autorizada.'},403);
 if(action==='purpose'&&!['owner','admin'].includes(a.membership.role))return json({error:'Somente administradores podem definir a destinação.'},403);
 try{
  const client=a.client as unknown as OperationsClient;
  // First database authorization rechecks unit/module, even for manual provider sync.
  const res=await client.rpc('finance_digital',{p_org:a.membership.organization_id,p_unit:unit,p_action:action==='sync'?'list':action,p_data:action==='sync'?{}:data});
  if(res.error){const code=res.error.code;return json({error:code==='42501'?'Acesso ou conexão recusado.':code==='40001'?'Registro alterado. Atualize antes de repetir.':code==='22023'||code==='23514'?'Revise classificação, conta de destino e valores.':'Não foi possível confirmar. Confira a lista antes de repetir.'},code==='42501'?403:code==='40001'?409:code==='22023'||code==='23514'?400:503)}
  if(action==='sync'){const server=supabaseAdminClient(),c=await digitalConnection(server,String(data.receiver));if(c.org!==a.membership.organization_id||!c.beneficiaries.includes(unit)||c.environment!==data.environment)return json({error:'Conexão fora do escopo.'},403);return json(await digitalSync(server,String(data.receiver),c,String(data.externalId)))}
  return json(res.data);
 }catch{return json({error:'Consulta ao provedor não confirmada. Nenhuma cobrança foi criada. Confira a fila de revisão.'},503)}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
