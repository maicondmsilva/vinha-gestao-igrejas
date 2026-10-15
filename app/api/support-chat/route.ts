import {NextResponse} from 'next/server';
import {randomBytes} from 'node:crypto';
import {db,rpc} from '../../lib/supabase/operations';
import {supabaseChurchSession} from '../../lib/supabase/church-session';
const cookieName='vinha_support_chat';
function identity(request:Request){const value=(request.headers.get('cookie')||'').split(';').map(x=>x.trim()).find(x=>x.startsWith(cookieName+'='))?.slice(cookieName.length+1)||'';const[id,secret]=value.split('.');return{id:/^[0-9a-f-]{36}$/.test(id||'')?id:null,secret:/^[0-9a-f]{64}$/.test(secret||'')?secret:null}}
function failure(e:unknown){const message=e instanceof Error?e.message:'';return NextResponse.json({error:message.includes('rate_limit')?'Limite de mensagens atingido. Aguarde alguns minutos.':message.includes('chat_closed')?'Atendimento encerrado. Você pode iniciar uma nova conversa.':message.includes('chat_access_denied')?'Esta conversa não está disponível para esta conta. Inicie um novo atendimento.':'Não foi possível acessar o atendimento. Tente novamente.'},{status:message.includes('rate_limit')?429:400})}
export async function GET(request:Request){try{const client=db(request),current=identity(request);if(new URL(request.url).searchParams.has('departments')){const{data,error}=await client.from('saas_chat_departments').select('id,name').eq('active',true).order('name');if(error)throw error;return NextResponse.json({departments:data},{headers:{'cache-control':'no-store'}})}if(!current.id)return NextResponse.json({conversation:null,messages:[]},{headers:{'cache-control':'no-store'}});const result=await rpc(client,'support_chat',{p_action:'read',p_id:current.id,p_secret:current.secret});return NextResponse.json(result,{headers:{'cache-control':'no-store'}})}catch(e){return failure(e)}}
export async function POST(request:Request){try{
 if(request.headers.get('origin')!==new URL(request.url).origin)return NextResponse.json({error:'Origem não autorizada.'},{status:403});
 const raw=await request.text();if(raw.length>12000)return NextResponse.json({error:'Mensagem muito extensa.'},{status:413});const data=JSON.parse(raw),client=db(request);
 if(data.website||data.accepted!==true&&data.action==='start')return NextResponse.json({error:'Confirme o aviso de privacidade.'},{status:400});
 if(data.action==='start'){
  const session=await supabaseChurchSession(request),secret=randomBytes(32).toString('hex');
  const result=await rpc(client,'support_chat',{p_action:'start',p_secret:secret,p_data:{name:data.name,email:data.email,body:data.body,departmentId:data.departmentId||null,organizationId:session?.churchId||null}});
  const response=NextResponse.json({ok:true,id:result.id});response.cookies.set(cookieName,`${result.id}.${secret}`,{httpOnly:true,secure:new URL(request.url).protocol==='https:',sameSite:'lax',path:'/',maxAge:2592000});return response;
 }
 if(data.action!=='send')return NextResponse.json({error:'Ação inválida.'},{status:400});const current=identity(request);if(!current.id)return NextResponse.json({error:'Inicie uma conversa.'},{status:400});
 return NextResponse.json(await rpc(client,'support_chat',{p_action:'send',p_id:current.id,p_secret:current.secret,p_data:{body:data.body}}));
}catch(e){return failure(e)}}
