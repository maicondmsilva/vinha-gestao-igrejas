import assert from 'node:assert/strict';
import {test} from 'node:test';
import {boundedBody,detectedFile,memberFilePath,privateFileLimit} from '../app/lib/private-files.ts';
const org='a0000000-0000-4000-8000-000000000001',person='b0000000-0000-4000-8000-000000000001',file='c0000000-0000-4000-8000-000000000001.pdf';
test('private document paths never accept traversal, another folder, SVG or arbitrary names',()=>{
 assert.equal(memberFilePath(org,person,file),`${org}/${person}/${file}`);
 for(const value of ['../x',file+'/x','document.pdf',file.replace('.pdf','.svg'),file+'?key=x'])assert.equal(memberFilePath(org,person,value),null);
 assert.equal(memberFilePath('../',person,file),null);assert.equal(memberFilePath(org,'other',file),null);
});
test('content signature, not the caller MIME or extension, determines allowed formats',()=>{
 assert.deepEqual(detectedFile(new TextEncoder().encode('%PDF-1.7 test')),{extension:'pdf',mime:'application/pdf'});
 assert.deepEqual(detectedFile(Uint8Array.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])),{extension:'png',mime:'image/png'});
 assert.equal(detectedFile(new TextEncoder().encode('<svg onload=alert(1)>')),null);assert.equal(detectedFile(new Uint8Array()),null);
});
test('body limit applies while streaming even without Content-Length',async()=>{
 const request=new Request('https://vinha.test',{method:'POST',body:new ReadableStream({start(c){c.enqueue(new Uint8Array(5));c.enqueue(new Uint8Array(5));c.close()}}),duplex:'half'});
 await assert.rejects(boundedBody(request,8),/body_too_large/);
 assert.equal((await boundedBody(new Request('https://vinha.test',{method:'POST',body:'test'}),8)).length,4);
 assert.equal(privateFileLimit,4194304);
});
