import {createHash} from 'node:crypto';
import type {Row} from './operations';
import {decryptSecret} from '../../api/payments/secrets';
export function billingChannelFingerprint(channel:Row,credential:string){
 const c=channel.provider_config||{};
 return createHash('sha256').update(JSON.stringify([credential,channel.provider,channel.sender_address,c.phoneNumberId,c.businessAccountId,c.billingLanguage,c.apiVersion,c.billingTemplates?.upcoming,c.billingTemplates?.overdue,c.billingTemplates?.paid])).digest('hex');
}
export async function billingChannelVerified(channel:Row){try{
 const credential=await decryptSecret(channel.credential_ciphertext,channel.credential_iv),verification=channel.provider_config?.billingVerification;
 return !!credential&&!!verification&&Date.now()-Date.parse(verification.at)<7*86400000&&verification.fingerprint===billingChannelFingerprint(channel,credential);
}catch{return false}}
