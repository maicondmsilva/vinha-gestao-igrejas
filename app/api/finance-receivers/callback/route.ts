import {createHash} from 'node:crypto';
import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {receiverContext,openReceiver,sealReceiver} from '../../../lib/receiver-vault';
import {mercadoReceiverExchange,mercadoReceiverIdentity} from '../../../lib/receiver-mercado';
import type {ReceiverEnvironment} from '../../../lib/finance-receivers';
type Cookie={actor:string;org:string;unit:string;environment:ReceiverEnvironment;state:string;tenant:string;expires:number};
export async function GET(r:Request){
 const url=new URL(r.url),state=url.searchParams.get('state')||'';let cookieName='',c:Cookie|undefined;
 const finish=(status:string)=>{const target=new URL('/painel',url.origin);target.search=new URLSearchParams({pagina:'financeiro',secao:'recebimentos',...(c?{unidade:c.unit,tenant:c.tenant}:{}),conexao:status}).toString();const response=new Response(null,{status:303,headers:{Location:target.href,'Cache-Control':'private, no-store','Referrer-Policy':'no-referrer'}});if(cookieName)response.headers.append('Set-Cookie',`${cookieName}=; Path=/api/finance-receivers/callback; HttpOnly; SameSite=Lax; Max-Age=0${url.protocol==='https:'?'; Secure':''}`);return response};
 try{
  if(!/^[A-Za-z0-9_-]{43}$/.test(state)||url.searchParams.getAll('state').length!==1||url.searchParams.getAll('code').length>1)return finish('recusada');
  const hash=createHash('sha256').update(state).digest('hex');cookieName='vinha_receiver_'+hash.slice(0,16);const raw=(r.headers.get('cookie')||'').split(/;\s*/).find(x=>x.startsWith(cookieName+'='))?.slice(cookieName.length+1);if(!raw)return finish('expirada');
  c=openReceiver<Cookie>(raw,'receiver-oauth-cookie');if(c.state!==state||c.expires<Date.now()||!['sandbox','production'].includes(c.environment))return finish('expirada');
  const authUrl=new URL(r.url);authUrl.searchParams.set('tenant',c.tenant);const auth=await authorizeSupabaseChurch(new Request(authUrl,r),'units.read');if(!auth?.access||auth.access.userId!==c.actor||auth.access.membership.organization_id!==c.org||!['owner','admin'].includes(auth.access.membership.role))return finish('acesso');
  const server=supabaseAdminClient(),args={p_actor:c.actor,p_org:c.org,p_unit:c.unit},claim=await server.rpc('finance_receiver_server',{...args,p_action:'claim',p_data:{environment:c.environment,stateHash:hash}});if(claim.error)return finish('expirada');
  const code=url.searchParams.get('code');if(url.searchParams.has('error')||!code||code.length>2048)return finish('recusada');
  const context=receiverContext(c.org,c.unit,'mercado_pago',c.environment),proof=openReceiver<{verifier:string}>(claim.data.verifier,context+':verifier');
  const token=await mercadoReceiverExchange(c.environment,{code,verifier:proof.verifier}),identity=await mercadoReceiverIdentity(token,c.environment);
  const result=await server.rpc('finance_receiver_server',{...args,p_action:'complete',p_data:{environment:c.environment,attempt:claim.data.id,...identity,sealed:sealReceiver(token,context)}});return finish(result.error?'alterada':'conectada');
 }catch{return finish('falha')}
}
