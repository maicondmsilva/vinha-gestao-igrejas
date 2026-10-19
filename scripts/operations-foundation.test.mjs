import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomBytes} from 'node:crypto';
import {assertDeploymentIsolation} from '../app/lib/deployment-safety.ts';
import {pilotReadiness,operationMetric} from '../app/lib/operational-readiness.ts';
import {sealRecoveryArtifact,openRecoveryArtifact,artifactDigest} from './recovery-envelope.mjs';
const ref='abcdefghijklmnopqrst';
const preview={VERCEL_ENV:'preview',NEXT_PUBLIC_VINHA_ENV:'test',NEXT_PUBLIC_VINHA_TEST_PROJECT_REF:ref,NEXT_PUBLIC_SUPABASE_URL:`https://${ref}.supabase.co`,VINHA_PROVIDER_MODE:'sandbox'};
test('preview fails closed without explicit isolated project, including aliases and malformed URLs',()=>{
 assert.doesNotThrow(()=>assertDeploymentIsolation(preview));
 for(const env of [{VERCEL_ENV:'preview'},{...preview,NEXT_PUBLIC_SUPABASE_URL:'https://aoxibaaydfgffrdqtkva.supabase.co'},{...preview,NEXT_PUBLIC_SUPABASE_URL:'https://custom-domain.test'},{...preview,NEXT_PUBLIC_SUPABASE_URL:'bad'},{...preview,VINHA_PROVIDER_MODE:'production'},{...preview,NEXT_PUBLIC_SUPABASE_URL:`https://secret@${ref}.supabase.co`}])assert.throws(()=>assertDeploymentIsolation(env));
 assert.doesNotThrow(()=>assertDeploymentIsolation({VERCEL_ENV:'production'}));
});
test('encrypted recovery artifacts authenticate bytes, key and fresh nonce',()=>{
 const key=randomBytes(32),plain=Buffer.from('SYNTHETIC ONLY'),a=sealRecoveryArtifact(plain,key),b=sealRecoveryArtifact(plain,key);
 assert.notDeepEqual(a,b);assert.deepEqual(openRecoveryArtifact(a,key),plain);assert.equal(a.includes(plain),false);
 const corrupt=Buffer.from(a);corrupt[corrupt.length-1]^=1;
 assert.throws(()=>openRecoveryArtifact(corrupt,key));assert.throws(()=>openRecoveryArtifact(a,randomBytes(32)));assert.throws(()=>sealRecoveryArtifact(plain,Buffer.alloc(3)));
 assert.equal(artifactDigest(a).length,64);
});
test('pilot does not pass missing, duplicated, stale or future evidence',()=>{
 const now=Date.parse('2026-10-17T12:00:00Z'),item={gate:'databaseRestore',passed:true,verifiedAt:'2026-10-16T12:00:00Z',reference:'evidence/restore-1'};
 assert.equal(pilotReadiness([item],now).find(x=>x.gate===item.gate).ready,true);
 for(const entries of [[],[item,item],[{...item,verifiedAt:'2026-01-01'}],[{...item,verifiedAt:'2027-01-01'}],[{...item,reference:''}],[{...item,passed:false}]])assert.equal(pilotReadiness(entries,now).some(x=>x.ready),false);
});
test('operational metrics drop unsolicited identity and never accept arbitrary error text',()=>{
 assert.deepEqual(operationMetric({operation:'ledger_post',outcome:'success',durationMs:12.8,email:'private@example.test',token:'private'}),{operation:'ledger_post',outcome:'success',durationMs:13});
 assert.throws(()=>operationMetric({operation:'private@example.test',outcome:'error',durationMs:1}));
});
