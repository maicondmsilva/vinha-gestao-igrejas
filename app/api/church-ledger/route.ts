import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {ledgerPilotEnabled,ledgerCommand} from '../../lib/ledger-pilot';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {ledgerBalanceCsv} from '../../lib/ledger-report';
const json=(value:unknown,status=200)=>NextResponse.json(value,{status,headers:{'Cache-Control':'private, no-store'}});
const unavailable=()=>json({error:'Livro financeiro disponível somente em homologação isolada e autorizada.',code:'LEDGER_PILOT_DISABLED'},503);
function failure(error?:{code?:string}){return json({error:error?.code==='42501'?'Acesso financeiro negado para esta unidade.':error?.code==='23505'?'Registro já existente. Atualize a lista antes de tentar novamente.':['22023','22P02','22007','22008','23514','23502'].includes(error?.code||'')?'Revise os dados e o período. A operação foi recusada.':error?.code==='40001'||error?.code==='40P01'?'Houve outra operação simultânea. Reenvie o mesmo pedido para confirmar.':'Não foi possível confirmar. Consulte o histórico antes de repetir.'},error?.code==='42501'?403:error?.code==='23505'?409:['22023','22P02','22007','22008','23514','23502'].includes(error?.code||'')?400:503)}
async function authorize(request:Request){
 const result=await authorizeSupabaseChurch(request,'units.read');
 if(!result||result.response)return{response:result?.response||unavailable()};
 if(!['owner','admin','finance'].includes(result.access!.membership.role))return{response:json({error:'Acesso exclusivo de responsáveis financeiros.'},403)};
 return{access:result.access!,client:result.access!.client as unknown as OperationsClient};
}
export async function GET(request:Request){
 if(!ledgerPilotEnabled(process.env))return unavailable();
 try{
  const auth=await authorize(request);if(auth.response)return auth.response;
  const {access,client}=auth,url=new URL(request.url),unitId=url.searchParams.get('unitId')||'',date=url.searchParams.get('date')||'',page=Number(url.searchParams.get('page')||1);
  if(!unitId)return json({units:access!.membership.units,recoveryScope:access!.userId+':'+access!.membership.organization_id});
  if(!uuidPattern.test(unitId)||!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isSafeInteger(page)||page<1||page>10000)return failure({code:'22023'});
  if(!access!.membership.units.some(unit=>unit.id===unitId))return failure({code:'42501'});
  const exportMode=url.searchParams.get('export');if(exportMode&&exportMode!=='balances')return failure({code:'22023'});
  const organization=access!.membership.organization_id;
  const balances=await client!.rpc('church_ledger_balances',{p_org:organization,p_unit:unitId,p_through:date});if(balances.error)return failure(balances.error);
  if(!Array.isArray(balances.data)||balances.data.some((row:Record<string,unknown>)=>!row||typeof row.accountId!=='string'||!uuidPattern.test(row.accountId)||typeof row.name!=='string'||typeof row.balanceCents!=='string'||!/^\-?\d+$/.test(row.balanceCents)))return failure();
  if(exportMode==='balances')return new Response(ledgerBalanceCsv(unitId,date,balances.data),{headers:{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':'attachment; filename="vinha-saldos-homologacao.csv"','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});
  const [journals,period]=await Promise.all([
   client!.from('church_ledger_journals').select('id,effective_date,memo,reversal_of,created_at',{count:'exact'}).eq('organization_id',organization).eq('unit_id',unitId).lte('effective_date',date).order('effective_date',{ascending:false}).order('id',{ascending:false}).range((page-1)*25,page*25-1),
   client!.from('church_ledger_periods').select('closed_through').eq('organization_id',organization).eq('unit_id',unitId).maybeSingle(),
  ]);
  if(journals.error||period.error)return failure(journals.error||period.error||undefined);
  return json({balances:balances.data,journals:journals.data,closedThrough:period.data?.closed_through||null,units:access!.membership.units,pagination:{page,total:journals.count||0,limit:25}});
 }catch{return failure()}
}
export async function POST(request:Request){
 if(!ledgerPilotEnabled(process.env))return unavailable();
 try{
  const auth=await authorize(request);if(auth.response)return auth.response;
  let input:ReturnType<typeof ledgerCommand>;
  try{input=ledgerCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,16384))))}catch{return failure({code:'22023'})}
  if(!auth.access!.membership.units.some(unit=>unit.id===input.unitId))return failure({code:'42501'});
  const scope={p_org:auth.access!.membership.organization_id,p_unit:input.unitId};
  const result=input.action==='account'?await auth.client!.rpc('create_church_ledger_account',{...scope,p_name:input.name,p_kind:input.kind}):input.action==='close'?await auth.client!.rpc('close_church_ledger_period',{...scope,p_through:input.date}):await auth.client!.rpc('post_church_journal',{...scope,p_request:input.requestId,p_date:input.date,p_memo:input.memo,p_lines:input.action==='reverse'?[]:[{accountId:input.debit,deltaCents:input.amountCents},{accountId:input.credit,deltaCents:-input.amountCents}],p_reversal:input.action==='reverse'?input.originalId:null});
  if(result.error)return failure(result.error);
  if(input.action!=='close'&&(typeof result.data!=='string'||!uuidPattern.test(result.data)))return failure();
  if((input.action==='post'||input.action==='reverse')&&result.data!==input.requestId)return failure();
  return json({ok:true,id:result.data});
 }catch{return failure()}
}
