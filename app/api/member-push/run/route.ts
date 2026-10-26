import {timingSafeEqual} from 'node:crypto';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {sendMemberPush,memberPushReceipts} from '../../../lib/member-push';
export async function GET(request:Request){
 const expected=process.env.CRON_SECRET,actual=request.headers.get('authorization')||'';
 if(!expected||Buffer.byteLength(actual)!==Buffer.byteLength('Bearer '+expected)||!timingSafeEqual(Buffer.from(actual),Buffer.from('Bearer '+expected)))return Response.json({error:'Acesso restrito.'},{status:403});
 if(process.env.MEMBER_PUSH_ENABLED!=='true')return Response.json({enabled:false});
 try{
 const client=supabaseAdminClient(),rpc=async(action:string,data:Record<string,unknown>={})=>{const r=await client.rpc('member_push_work',{p_action:action,p_data:data});if(r.error)throw Error('Push operation failed');return r.data};
 const previous=await rpc('receipts');
 if(previous.items.length){const receipts=await memberPushReceipts(previous.items.map((j:{ticket:string})=>j.ticket),fetch,process.env.EXPO_ACCESS_TOKEN);for(const j of previous.items){const r=receipts[j.ticket];if(r)await rpc('settle',{id:j.id,state:r.status==='ok'?'delivered':'failed',error:r.details?.error});}}
 const jobs=await rpc('claim');let submitted=0;
 for(const j of jobs.items){const result=await sendMemberPush(j,fetch,process.env.EXPO_ACCESS_TOKEN);await rpc('settle',{id:j.id,...result});if(result.state==='submitted')submitted++;}
 return Response.json({submitted});
 }catch{return Response.json({error:'Processamento não confirmado.'},{status:503})}
}
