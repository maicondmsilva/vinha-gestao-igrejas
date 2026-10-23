import {createHash,randomUUID} from 'node:crypto';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {receiverCommand,receiverId,receiverOpeningUrl} from '../../lib/finance-receivers';
import {mercadoReceiverConfigured,mercadoReceiverStart,mercadoReceiverExchange,mercadoReceiverIdentity,type MercadoReceiverToken} from '../../lib/receiver-mercado';
import {receiverContext,sealReceiver,openReceiver,receiverVaultConfigured} from '../../lib/receiver-vault';
import {asaasReceiverIdentity} from '../../lib/receiver-asaas';
import {mercadoKeyIdentity,mercadoKeyMaterial} from '../../lib/receiver-key-validation';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(r:Request){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 try{const p=new URL(r.url).searchParams;if([...p.keys()].some(k=>!['unit','tenant'].includes(k)||p.getAll(k).length!==1))return json({error:'Filtro inválido.'},400);const unit=receiverId(p.get('unit'));if(!a.membership.units.some(u=>u.id===unit))return json({error:'Igreja não autorizada.'},403);
 const result=await (a.client as unknown as OperationsClient).rpc('finance_receiver_settings',{p_org:a.membership.organization_id,p_unit:unit,p_action:'list',p_data:{}});if(result.error)return failure(result.error.code);
 return json({...result.data,security:{vaultConfigured:receiverVaultConfigured(),serverConfigured:Boolean(process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY)},connections:{sandbox:ready('sandbox'),production:ready('production'),asaas:receiverVaultConfigured()&&Boolean(process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY)},paymentMethodsEnabled:[...new Set(((result.data?.items||[]) as {payments_enabled?:boolean;methods:string[]}[]).filter(x=>x.payments_enabled).flatMap(x=>x.methods))],openingMode:'official'});
 }catch{return json({error:'Não foi possível carregar as contas recebedoras.'},503)}
}
function ready(e:'sandbox'|'production'){return receiverVaultConfigured()&&Boolean(process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY)&&mercadoReceiverConfigured(e)}
function failure(code?:string){return json({error:code==='42501'?'Sem autorização para administrar esta conta recebedora.':code==='40001'?'A conexão mudou. Atualize e confira o histórico antes de repetir.':code==='22023'?'Revise a titularidade, a conta financeira e as igrejas selecionadas.':'Não foi possível confirmar. Atualize a página e confira o histórico.'},code==='42501'?403:code==='40001'?409:code==='22023'?400:503)}
export async function POST(r:Request){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 if(!['owner','admin'].includes(a.membership.role))return json({error:'Somente proprietário ou administrador pode autorizar contas recebedoras.'},403);
 let c:ReturnType<typeof receiverCommand>;try{c=receiverCommand(JSON.parse(new TextDecoder().decode(await boundedBody(r,16384))))}catch(e){return json({error:e instanceof Error?e.message:'Dados inválidos.'},400)}
 if(!a.membership.units.some(u=>u.id===c.unit))return json({error:'Igreja não autorizada.'},403);
 const org=a.membership.organization_id,context=receiverContext(org,c.unit,c.provider,c.environment);
 try{
  if(c.action==='key'){
   if(!receiverVaultConfigured())return json({error:'O cofre de contas recebedoras ainda não foi configurado pela equipe Vinha.'},503);
   if(!process.env.SUPABASE_SECRET_KEY&&!process.env.SUPABASE_SERVICE_ROLE_KEY)return json({error:'O cofre está configurado, mas falta a credencial privada do servidor na Vercel. A equipe Vinha precisa concluir essa configuração antes de salvar tokens.'},503);
   const access=await(a.client as unknown as OperationsClient).rpc('finance_receiver_settings',{p_org:org,p_unit:c.unit,p_action:'list',p_data:{}});
   if(access.error)return failure(access.error.code);
   if(access.data?.canManage!==true)return failure('42501');
   const credential=String(c.data.credential),server=supabaseAdminClient();
   if(c.provider==='mercado_pago'){
    const identity=await mercadoKeyIdentity(credential,c.environment),material=mercadoKeyMaterial(credential,identity,String(c.data.publicKey||''),String(c.data.webhookSecret||''));
    const result=await server.rpc('finance_receiver_key_check',{p_actor:a.userId,p_org:org,p_unit:c.unit,p_action:'complete',p_data:{provider:c.provider,environment:c.environment,version:c.data.version,...identity,webhookConfigured:!!material.webhookSecret,sealed:sealReceiver(material,context)}});
    return result.error?failure(result.error.code):json({ok:true,identityValidated:true});
   }
   if(c.provider!=='asaas'){
    const result=await server.rpc('finance_receiver_manual_key',{p_actor:a.userId,p_org:org,p_unit:c.unit,p_data:{provider:c.provider,environment:c.environment,version:c.data.version,sealed:sealReceiver({credential},context)}});
    return result.error?failure(result.error.code):json({ok:true,pendingValidation:true});
   }
   const identity=await asaasReceiverIdentity(credential,c.environment);
   const result=await server.rpc('finance_receiver_server',{p_actor:a.userId,p_org:org,p_unit:c.unit,p_action:'key_complete',p_data:{provider:c.provider,environment:c.environment,version:c.data.version,...identity,sealed:sealReceiver({credential},context)}});return result.error?failure(result.error.code):json({ok:true});
  }
  if(c.action==='validate'||c.action==='activate'){
   if(!receiverVaultConfigured()||!process.env.SUPABASE_SECRET_KEY&&!process.env.SUPABASE_SERVICE_ROLE_KEY)return json({error:'Cofre ou servidor indisponível.'},503);
   const server=supabaseAdminClient(),args={p_actor:a.userId,p_org:org,p_unit:c.unit};
   if(c.action==='activate'){
    const result=await server.rpc('finance_receiver_key_check',{...args,p_action:'activate',p_data:c.data});return result.error?failure(result.error.code):json({ok:true,paymentsActivated:true});
   }
   const current=await server.rpc('finance_receiver_key_check',{...args,p_action:'inspect',p_data:c.data});if(current.error)return failure(current.error.code);
   const old=openReceiver<{credential?:string;access_token?:string;publicKey?:string;webhookSecret?:string}>(current.data.sealed,context),credential=old.credential||old.access_token||'';
   const identity=await mercadoKeyIdentity(credential,c.environment),material=mercadoKeyMaterial(credential,identity,old.publicKey,old.webhookSecret);
   const result=await server.rpc('finance_receiver_key_check',{...args,p_action:['connected','configured'].includes(current.data.status)?'renew':'complete',p_data:{...c.data,...identity,webhookConfigured:!!material.webhookSecret,sealed:sealReceiver(material,context)}});
   return result.error?failure(result.error.code):json({ok:true,identityValidated:true});
  }
  if(c.action==='connect'){
   if(c.provider!=='mercado_pago')return json({error:'Conector deste provedor aguarda homologação própria. Abra a conta no ambiente oficial; a Vinha não solicitará sua senha.'},409);
   if(!ready(c.environment))return json({error:'A equipe Vinha precisa configurar o aplicativo OAuth e o cofre neste ambiente antes da conexão.'},503);
   const start=mercadoReceiverStart(c.environment);if(new URL(start.redirect).origin!==new URL(r.url).origin)return json({error:'Conecte pelo domínio configurado para este ambiente.'},409);
   const hash=createHash('sha256').update(start.state).digest('hex'),server=supabaseAdminClient(),id=randomUUID();
   const result=await server.rpc('finance_receiver_server',{p_actor:a.userId,p_org:org,p_unit:c.unit,p_action:'begin',p_data:{id,environment:c.environment,stateHash:hash,verifier:sealReceiver({verifier:start.verifier},context+':verifier')}});if(result.error)return failure(result.error.code);
   const cookie=sealReceiver({actor:a.userId,org,unit:c.unit,environment:c.environment,state:start.state,tenant:a.membership.organization_slug||'',expires:Date.now()+600000},'receiver-oauth-cookie');
   const response=json({url:start.url});response.headers.append('Set-Cookie',`vinha_receiver_${hash.slice(0,16)}=${cookie}; Path=/api/finance-receivers/callback; HttpOnly; SameSite=Lax; Max-Age=600${new URL(r.url).protocol==='https:'?'; Secure':''}`);return response;
  }
  if(c.action==='refresh'){
   if(c.provider!=='mercado_pago'||!ready(c.environment))return json({error:'Renovação não configurada para este provedor e ambiente.'},503);
   const server=supabaseAdminClient(),args={p_actor:a.userId,p_org:org,p_unit:c.unit,p_data:c.data};const result=await server.rpc('finance_receiver_server',{...args,p_action:'secret'});if(result.error)return failure(result.error.code);
   const old=openReceiver<MercadoReceiverToken>(result.data.sealed,context),token=await mercadoReceiverExchange(c.environment,{refresh:old.refresh_token}),identity=await mercadoReceiverIdentity(token,c.environment);
   const done=await server.rpc('finance_receiver_server',{...args,p_action:'refreshed',p_data:{...c.data,...identity,sealed:sealReceiver(token,context)}});return done.error?failure(done.error.code):json({ok:true});
  }
  const result=await (a.client as unknown as OperationsClient).rpc('finance_receiver_settings',{p_org:org,p_unit:c.unit,p_action:c.action,p_data:c.data});if(result.error)return failure(result.error.code);
  return json({...result.data,...(c.action==='open'?{url:receiverOpeningUrl(c.provider,c.environment)}:{})});
 }catch(e){if(e instanceof Error&&['A conta Asaas ainda precisa de aprovação ou atualização cadastral no provedor.','Titular ou ambiente não confirmado.','Chave inválida.','Use a chave do ambiente selecionado.','Conta indisponível no provedor.','Titular não informado.','O Mercado Pago recusou a consulta da conta.'].includes(e.message))return json({error:e.message+' Confira o Access Token (não Public Key) e o ambiente. A configuração anterior foi preservada; nenhuma cobrança foi criada.'},422);return json({error:'Não foi possível validar a conta. Confira a credencial, o ambiente selecionado e o cadastro no provedor. A configuração anterior foi preservada; nenhuma cobrança foi criada.'},503)}
}
