import {randomBytes,createCipheriv,createDecipheriv,createHash} from 'node:crypto';
const header=Buffer.from('VINHA-BACKUP-1\n');
function keyBytes(key){if(!Buffer.isBuffer(key)||key.length!==32)throw Error('Chave de 32 bytes exigida.');return key}
// Bounded primitive, not a complete export or off-site backup scheduler.
export function sealRecoveryArtifact(plaintext,key){
 if(!Buffer.isBuffer(plaintext)||plaintext.length>64*1024*1024)throw Error('Artefato inválido ou maior que 64 MB.');
 const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',keyBytes(key),iv);cipher.setAAD(header);
 const ciphertext=Buffer.concat([cipher.update(plaintext),cipher.final()]);
 return Buffer.concat([header,iv,cipher.getAuthTag(),ciphertext]);
}
export function openRecoveryArtifact(envelope,key){
 if(!Buffer.isBuffer(envelope)||envelope.length<header.length+28||envelope.length>64*1024*1024+header.length+28||!envelope.subarray(0,header.length).equals(header))throw Error('Envelope inválido.');
 const offset=header.length,decipher=createDecipheriv('aes-256-gcm',keyBytes(key),envelope.subarray(offset,offset+12));
 decipher.setAAD(header);decipher.setAuthTag(envelope.subarray(offset+12,offset+28));
 return Buffer.concat([decipher.update(envelope.subarray(offset+28)),decipher.final()]);
}
export function artifactDigest(bytes){return createHash('sha256').update(bytes).digest('hex')}
