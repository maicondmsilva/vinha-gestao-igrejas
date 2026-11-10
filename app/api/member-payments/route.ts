import {createClient} from '@supabase/supabase-js';
import {db} from '../../lib/supabase/operations';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {trustedSessionRequest} from '../../lib/access-security';
import {dispatchDigitalCheckout,checkoutOrigin} from '../../lib/digital-checkout';
import {digitalConnection} from '../../lib/digital-provider';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function POST(request:Request){try{
 const token=request.headers.get('authorization');
 if(!token&&!trustedSessionRequest(request))return json({error:'Origem não autorizada.'},403);
 if(token&&!/^Bearer [A-Za-z0-9_.-]+$/.test(token))return json({error:'Sessão inválida.'},401);
 const client=token?createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{global:{headers:{Authorization:token}},auth:{persistSession:false,autoRefreshToken:false}}):db(request);
 const {data:{user},error}=await client.auth.getUser();if(error||!user)return json({error:'Entre na sua conta.'},401);
 const b=JSON.parse(new TextDecoder().decode(await boundedBody(request,2000)));
 if(!b||Object.keys(b).some(k=>!['org','unit','id'].includes(k))||![b.org,b.unit,b.id].every(x=>typeof x==='string'&&uuidPattern.test(x)))return json({error:'Pedido inválido.'},400);
 // The authenticated RPC validates ownership before any server credential is used.
 const args={p_org:b.org,p_unit:b.unit,p_action:'resume',p_data:{id:b.id}},reserved=await client.rpc('member_payments',args);
 if(reserved.error||!reserved.data?.ok)return json({error:'Pedido indisponível ou acesso alterado.'},403);
 if(reserved.data.paidObserved)return json({state:'observed'});
 if(reserved.data.expired)return json({error:'Link expirado. Consulte o histórico e a igreja antes de gerar outro pedido.'},409);
 const server=supabaseAdminClient(),a=reserved.data,c=await digitalConnection(server,a.receiver),origin=checkoutOrigin(process.env.FINANCE_CHECKOUT_ORIGIN||'https://app.vinhaigrejas.com.br');
 const result=await dispatchDigitalCheckout(server,{org:b.org,unit:b.unit,attempt:a.id,receiver:a.receiver},c,origin);
 const check=await client.rpc('member_payments',args);if(check.error)return json({error:'Acesso alterado. Consulte a igreja.'},403);
 return json(result);
 }catch{return json({error:'Checkout não confirmado. Atualize seu histórico; não repita o pagamento enquanto houver dúvida.'},503)}}
