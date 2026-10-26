type Job={id:string;token:string;project:string};
type Result={state:'submitted'|'delivered'|'failed'|'uncertain'|'queued';ticket?:string;error?:string};
export async function sendMemberPush(job:Job,transport:typeof fetch=fetch,accessToken?:string):Promise<Result>{
 try{
 const r=await transport('https://exp.host/--/api/v2/push/send',{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/json',...(accessToken?{Authorization:'Bearer '+accessToken}:{})},body:JSON.stringify({to:job.token,title:'Novidade na sua igreja',body:'Abra o aplicativo para consultar sua caixa de entrada.',sound:'default',channelId:'igreja',data:{screen:'inbox'},ttl:3600})});
 if(r.status===429)return{state:'queued'};
 if(!r.ok)return{state:r.status>=500?'uncertain':'failed'};
 const text=await r.text();if(text.length>16384)return{state:'uncertain'};
 const d=JSON.parse(text).data;if(d?.status==='ok'&&typeof d.id==='string'&&d.id.length<200)return{state:'submitted',ticket:d.id};
 return{state:'failed',error:d?.details?.error==='DeviceNotRegistered'?'DeviceNotRegistered':undefined};
 }catch{return{state:'uncertain'}}
}
export async function memberPushReceipts(ids:string[],transport:typeof fetch=fetch,accessToken?:string){
 const r=await transport('https://exp.host/--/api/v2/push/getReceipts',{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/json',...(accessToken?{Authorization:'Bearer '+accessToken}:{})},body:JSON.stringify({ids})});
 if(!r.ok)throw Error('Receipts unavailable');const text=await r.text();if(text.length>131072)throw Error('Invalid receipts');return JSON.parse(text).data as Record<string,{status:string;details?:{error?:string}}>;
}
