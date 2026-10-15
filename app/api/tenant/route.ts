import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {check,rpc,type OperationsClient} from '../../lib/supabase/operations';
export async function GET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.read');
 if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase não configurado.'},{status:503});
 try{
  const access=auth.access!,client=access.client as unknown as OperationsClient,organization=access.membership.organization_id;
  const [summary,units,people]=await Promise.all([
   rpc(client,'tenant_subscription_summary',{p_organization:organization}),
   client.from('organization_units').select('id',{count:'exact',head:true}).eq('organization_id',organization).eq('status','active'),
   client.from('people').select('id',{count:'exact',head:true}).eq('organization_id',organization).neq('status','rejected'),
  ]);
  check(units);check(people);
  return NextResponse.json({...summary,usage:{units:units.count||0,people:people.count||0}},{headers:{'cache-control':'no-store'}});
 }catch{return NextResponse.json({error:'Não foi possível consultar a assinatura. Nenhum plano foi alterado.'},{status:503})}
}
