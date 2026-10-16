import {NextResponse} from 'next/server';
import type {OperationsClient} from '../../../lib/supabase/operations';
import {createSupabaseRequestClient} from '../../../lib/supabase/request';
import {trustedSessionRequest} from '../../../lib/access-security';
import {organizationInviteToken,organizationInviteError} from '../../../lib/organization-invite';
const client=(request:Request)=>createSupabaseRequestClient(request) as unknown as OperationsClient;
const json=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{'Cache-Control':'no-store, max-age=0, private'}});
export async function GET(request:Request){
 const token=organizationInviteToken(new URL(request.url).searchParams.get('token'));
 if(!token)return json({error:'Convite inválido ou expirado.'},404);
 try{
  const result=await client(request).rpc('organization_invite_preview',{p_token:token});
  return result.error?json({error:organizationInviteError(result.error.message)},404):json(result.data);
 }catch{return json({error:'Não foi possível consultar o convite. Tente novamente.'},503)}
}
export async function POST(request:Request){
 if(!trustedSessionRequest(request))return json({error:'Origem da solicitação não autorizada.'},403);
 let value:string|null;
 try{const input=await request.json();value=organizationInviteToken(input?.token)}catch{return json({error:'Solicitação inválida.'},400)}
 if(!value)return json({error:'Convite inválido ou expirado.'},404);
 try{
  const supabase=client(request),{data:{user},error}=await supabase.auth.getUser();
  if(error||!user)return json({error:'Entre ou crie sua conta para ativar a organização.',loginRequired:true},401);
  const result=await supabase.rpc('accept_organization_invite',{p_token:value});
  if(result.error)return json({error:organizationInviteError(result.error.message)},result.error.code==='42501'?403:400);
  const activated=result.data as {slug?:string;alreadyAccepted?:boolean}|null;
  if(!activated||typeof activated.slug!=='string'||!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(activated.slug))return json({error:'Não foi possível confirmar a ativação. Entre novamente para verificar seu acesso.'},503);
  const {data:organization,error:organizationError}=await supabase.from('organizations').select('id').eq('slug',activated.slug).single();
  if(organizationError||!organization)return json({error:'A ativação foi gravada, mas não foi possível carregar o ambiente. Entre novamente para continuar.'},503);
  const {data:progress,error:progressError}=await supabase.from('saas_onboarding_progress').select('status').eq('organization_id',organization.id).maybeSingle();
  if(progressError)return json({error:'Não foi possível recuperar a configuração. Tente acessar novamente.'},503);
  const target=progress?.status==='completed'||(activated.alreadyAccepted&&!progress)?'/painel':'/onboarding';
  return json({ok:true,slug:activated.slug,alreadyAccepted:activated.alreadyAccepted,redirectUrl:target+'?tenant='+encodeURIComponent(activated.slug)});
 }catch{return json({error:'Não foi possível confirmar a ativação. Entre novamente para verificar seu acesso antes de tentar outra vez.'},503)}
}
