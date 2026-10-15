import {createHmac,timingSafeEqual} from 'node:crypto';
function equal(a:Buffer,b:Buffer){return a.length===b.length&&timingSafeEqual(a,b)}
export function verifyResend(raw:string,headers:Headers,secret:string,now=Date.now()){
 const id=headers.get('svix-id'),timestamp=headers.get('svix-timestamp'),signature=headers.get('svix-signature');
 if(!id||!timestamp||!signature||!/^\d+$/.test(timestamp)||Math.abs(now/1000-Number(timestamp))>300||!secret.startsWith('whsec_'))return false;
 const expected=createHmac('sha256',Buffer.from(secret.slice(6),'base64')).update(`${id}.${timestamp}.${raw}`).digest();
 return signature.split(' ').some(s=>s.startsWith('v1,')&&equal(expected,Buffer.from(s.slice(3),'base64')));
}
export function verifyMeta(raw:string,signature:string|null,secret:string){
 if(!secret||!signature||!/^sha256=[a-f0-9]{64}$/.test(signature))return false;
 return equal(createHmac('sha256',secret).update(raw).digest(),Buffer.from(signature.slice(7),'hex'));
}
