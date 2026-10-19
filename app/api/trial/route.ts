import {NextResponse} from 'next/server';
import {db} from '../../lib/supabase/operations';
import {trustedSessionRequest} from '../../lib/access-security';
import {organizationInviteToken} from '../../lib/organization-invite';
const json=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{'Cache-Control':'no-store, max-age=0, private'}});
export async function POST(request:Request){
 if(!trustedSessionRequest(request))return json({error:'Origem não autorizada.'},403);
 try{
  const client=db(request),{data:{user},error}=await client.auth.getUser();
  if(error||!user?.email_confirmed_at)return json({error:'Confirme seu e-mail e entre para liberar o teste.'},401);
  const pending=await client.rpc('pending_organization_invitation');
  if(pending.error)return json({error:'Não foi possível conferir seu acesso. Tente novamente.'},503);
  if(pending.data?.token){
   const token=organizationInviteToken(pending.data.token);
   if(!token)return json({error:'Não foi possível conferir o convite. Tente novamente.'},503);
   return json({error:'Sua conta já possui um convite. Continue pela ativação do ministério.',redirectUrl:`/ativar/${token}`},409);
  }
  const raw=await request.text();
  if(raw.length>12000)return json({error:'Cadastro muito extenso.'},413);
  let input:unknown;
  try{input=JSON.parse(raw)}catch{return json({error:'Cadastro inválido. Confira os campos e tente novamente.'},400)}
  if(!input||typeof input!=='object'||Array.isArray(input))return json({error:'Cadastro inválido.'},400);
  const result=await client.rpc('register_organization_trial',{p_data:input});
  if(result.error){
   if(result.error.message==='self_service_identity_unavailable'||result.error.code==='28000')return json({error:'Seu acesso precisa ser validado. Entre novamente com uma conta de e-mail confirmado.'},401);
   if(result.error.message==='user_already_has_organization')return json({error:'Sua conta já possui um ministério. Use Entrar para acessá-lo.'},409);
   return json({error:'Não foi possível liberar o teste. Confira os campos obrigatórios e tente novamente.'},400);
  }
  const created=result.data;
  if(created?.ok!==true||typeof created.slug!=='string'||!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(created.slug))return json({error:'Não foi possível confirmar o cadastro. Entre novamente para verificar seu acesso antes de tentar outra vez.'},503);
  return json({ok:true,slug:created.slug,alreadyCreated:created.alreadyCreated===true,redirectUrl:`/painel?tenant=${encodeURIComponent(created.slug)}`});
 }catch{return json({error:'Não foi possível confirmar o cadastro. Entre novamente para verificar seu acesso antes de tentar outra vez.'},503)}
}
