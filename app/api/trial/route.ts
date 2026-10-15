import {NextResponse} from 'next/server';
import {db,rpc} from '../../lib/supabase/operations';
export async function POST(request:Request){
 try{
  if(request.headers.get('origin')!==new URL(request.url).origin)return NextResponse.json({error:'Origem não autorizada.'},{status:403});
  const client=db(request),{data:{user}}=await client.auth.getUser();
  if(!user?.email_confirmed_at)return NextResponse.json({error:'Confirme seu e-mail e entre para liberar o teste.'},{status:401});
  const pending=await rpc(client,'pending_organization_invitation');if(pending?.token)return NextResponse.json({error:'Sua conta já possui um convite. Continue pela ativação do ministério.',redirectUrl:`/ativar/${pending.token}`},{status:409});
  const raw=await request.text();if(raw.length>12000)return NextResponse.json({error:'Cadastro muito extenso.'},{status:413});
  const data=JSON.parse(raw);const result=await rpc(client,'register_organization_trial',{p_data:data});
  return NextResponse.json({...result,redirectUrl:`/painel?tenant=${encodeURIComponent(result.slug)}`});
 }catch(e){const message=e instanceof Error?e.message:'';return NextResponse.json({error:message.includes('user_already_has_organization')?'Sua conta já possui um ministério. Use Entrar para acessá-lo.':'Não foi possível liberar o teste. Confira os campos obrigatórios e tente novamente.'},{status:400})}
}
