import {test} from 'node:test';
import assert from 'node:assert/strict';
import {localTestTotp} from './local-test-totp.mjs';
test('synthetic TOTP follows RFC 6238 SHA1 vectors',()=>{const secret='GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';assert.equal(localTestTotp(secret,59,8),'94287082');assert.equal(localTestTotp(secret,1111111109,8),'07081804');assert.equal(localTestTotp(secret,59),'287082')});
