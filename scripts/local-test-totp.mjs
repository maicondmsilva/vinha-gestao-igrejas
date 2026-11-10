import {createHmac} from 'node:crypto';
// Synthetic local accounts only. Never log the secret or generated code.
export function localTestTotp(secret,seconds=Math.floor(Date.now()/1000),digits=6){
 if(!/^[A-Z2-7]+=*$/.test(secret)||!Number.isSafeInteger(seconds)||seconds<0||![6,8].includes(digits))throw Error('Invalid synthetic TOTP input');
 let bits='';for(const char of secret.replace(/=+$/,''))bits+='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(char).toString(2).padStart(5,'0');
 const key=Buffer.from((bits.match(/.{8}/g)||[]).map(byte=>parseInt(byte,2))),counter=Buffer.alloc(8);counter.writeBigUInt64BE(BigInt(Math.floor(seconds/30)));
 const hash=createHmac('sha1',key).update(counter).digest(),offset=hash[19]&15;
 return String((hash.readUInt32BE(offset)&0x7fffffff)%10**digits).padStart(digits,'0');
}
