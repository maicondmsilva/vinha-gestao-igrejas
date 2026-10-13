import {NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
import {createSupabaseRequestClient} from '../../../lib/supabase/request';

type UntypedClient=ReturnType<typeof createClient>;
const client=(request:Request)=>createSupabaseRequestClient(request) as unknown as UntypedClient;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const errorMessage=(message:string)=>message.includes('invite_email_mismatch')?'Entre com o mesmo e-mail que recebeu o convite.':message.includes('invite_expired')?'Este convite expirou. Solicite um novo link à equipe da Vinha.':message.includes('invite_already_used')?'Este convite já foi utilizado por outra conta.':message.includes('authentication_required')?'Entre ou crie sua conta para ativar a organização.':'Convite inválido ou indisponível.';

export async function GET(request:Request){
 const token=new URL(request.url).searchParams.get('token')||'';
 if(!uuid.test(token))return NextResponse.json({error:'Convite inválido ou expirado.'},{status:404});
 const result=await client(request).rpc('organization_invite_preview',{p_token:token});
 if(result.error)return NextResponse.json({error:errorMessage(result.error.message)},{status:404});
 return NextResponse.json(result.data);
}

export async function POST(request:Request){
 const {token}=await request.json<{token?:string}>(),value=String(token||'');
 if(!uuid.test(value))return NextResponse.json({error:'Convite inválido ou expirado.'},{status:404});
 const supabase=client(request),{data:{user}}=await supabase.auth.getUser();
 if(!user)return NextResponse.json({error:'Entre ou crie sua conta para ativar a organização.',loginRequired:true},{status:401});
 const result=await supabase.rpc('accept_organization_invite',{p_token:value});
 if(result.error)return NextResponse.json({error:errorMessage(result.error.message)},{status:result.error.message.includes('mismatch')?403:400});
 const activated=result.data as {slug:string;alreadyAccepted:boolean};
 return NextResponse.json({ok:true,slug:activated.slug,alreadyAccepted:activated.alreadyAccepted,redirectUrl:`/onboarding?tenant=${activated.slug}`});
}
