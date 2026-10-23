import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import type {OperationsClient} from '../../../lib/supabase/operations';
import {boundedBody} from '../../../lib/private-files';
import {checkoutCommand,checkoutOrigin,dispatchDigitalCheckout} from '../../../lib/digital-checkout';
import {digitalConnection} from '../../../lib/digital-provider';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function POST(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 if(!['owner','admin'].includes(a.membership.role))return json({error:'Somente o responsável autorizado pode iniciar o checkout de validação.'},403);
 let command:ReturnType<typeof checkoutCommand>,origin:string;
 try{command=checkoutCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request,2048))));origin=checkoutOrigin(process.env.FINANCE_CHECKOUT_ORIGIN||'https://app.vinhaigrejas.com.br')}catch{return json({error:'Revise os dados ou a configuração do domínio de checkout.'},400)}
 if(!a.membership.units.some(u=>u.id===command.unit))return json({error:'Igreja não autorizada.'},403);
 try{
  const client=a.client as unknown as OperationsClient;
  const reserved=await client.rpc('finance_checkout_reserve',{p_org:a.membership.organization_id,p_unit:command.unit,p_order:command.order,p_name:command.name});
  if(reserved.error||!reserved.data)return json({error:'Pedido indisponível ou já em processamento. Confira o histórico antes de repetir.'},reserved.error?.code==='42501'?403:409);
  const attempt=reserved.data as {id:string;receiver:string;expired:boolean};
  if(attempt.expired)return json({error:'Tentativa expirada. Solicite conferência; não crie um pagamento duplicado.'},409);
  const server=supabaseAdminClient(),connection=await digitalConnection(server,attempt.receiver);
  await dispatchDigitalCheckout(server,{org:a.membership.organization_id,unit:command.unit,attempt:attempt.id,receiver:attempt.receiver},connection,origin);
  // Revalidate actor/session/module after the external call, before disclosing the link.
  const check=await client.rpc('finance_checkout_reserve',{p_org:a.membership.organization_id,p_unit:command.unit,p_order:command.order,p_name:command.name});
  if(check.error)return json({error:'Acesso alterado durante a operação. Solicite conferência.'},403);
  const result=await dispatchDigitalCheckout(server,{org:a.membership.organization_id,unit:command.unit,attempt:attempt.id,receiver:attempt.receiver},connection,origin);
  return json(result);
 }catch{return json({error:'Checkout não confirmado. Não há confirmação de pagamento. A tentativa não será reenviada automaticamente; solicite conferência.'},503)}
}
