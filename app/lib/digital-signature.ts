import {createHmac,timingSafeEqual} from 'node:crypto';
export function verifyDigitalMercadoSignature(request:Request,secret:string,now=Date.now()){
 const u=new URL(request.url),id=u.searchParams.get('data.id'),requestId=request.headers.get('x-request-id'),sig=request.headers.get('x-signature')||'';if(!secret||!id||u.searchParams.getAll('data.id').length!==1||!/^[a-zA-Z0-9_-]{1,100}$/.test(id)||!requestId||!/^[a-zA-Z0-9_-]{1,120}$/.test(requestId))return false;
 const parts=sig.split(',').map(x=>x.trim().split('='));if(parts.length!==2||new Set(parts.map(x=>x[0])).size!==2)return false;const ts=parts.find(x=>x[0]==='ts')?.[1]||'',hash=parts.find(x=>x[0]==='v1')?.[1]||'';if(!/^\d{10,13}$/.test(ts)||! /^[a-f0-9]{64}$/.test(hash))return false;const at=Number(ts)*(ts.length===10?1000:1);if(Math.abs(now-at)>300000)return false;
 const expected=createHmac('sha256',secret).update(`id:${id.toLowerCase()};request-id:${requestId};ts:${ts};`).digest();return timingSafeEqual(expected,Buffer.from(hash,'hex'));
}
