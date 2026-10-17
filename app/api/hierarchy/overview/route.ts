import {NextResponse} from 'next/server';
import {sessionFrom} from '../../_auth';
import {db,uuid} from '../../../lib/supabase/operations';
import {hierarchyError} from '../../../lib/hierarchy-governance';
const moduleNames:Record<string,string>={dashboard:'Visão geral',people:'Membresia',finance:'Financeiro',kids:'Kids',events:'Eventos',cells:'Células',scales:'Escalas',reports:'Relatórios'};
export async function GET(request:Request){
 try{
  const session=await sessionFrom(request);
  if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});
  if(!['admin','pastor'].includes(session.role))return NextResponse.json({error:'Apenas a administração da igreja pode consultar a hierarquia.'},{status:403});
  const child=new URL(request.url).searchParams.get('child');
  if(!uuid(child))return NextResponse.json({error:'Selecione uma igreja vinculada válida.'},{status:400});
  const result=await db(request).rpc('organization_hierarchy_overview',{p_organization:session.churchId,p_child:child});
  if(result.error){const error=hierarchyError(result.error);return NextResponse.json({error:error.message},{status:error.status})}
  return NextResponse.json({...result.data,permissions:Object.entries(moduleNames).map(([code,name])=>({code,name,allowed:false,level:'none',personalData:false})),message:'Vínculo consultado no banco principal. Os dados internos de cada ministério permanecem separados; o compartilhamento operacional entre ministérios ainda não está liberado.'},{headers:{'cache-control':'no-store'}});
 }catch{return NextResponse.json({error:'Não foi possível consultar o vínculo. Atualize a página e tente novamente.'},{status:503})}
}
