import assert from 'node:assert/strict';
import {test} from 'node:test';
import {quotePlanProration} from '../app/lib/plan-proration.ts';
const base={currentNetCents:10000,nextNetCents:16000,cycleStart:1000,cycleEnd:3000,effectiveAt:2000};
test('upgrade bills only remaining-cycle difference; downgrade produces next-invoice credit',()=>{
 const upgrade=quotePlanProration(base);assert.equal(upgrade.chargeCents,'3000');assert.equal(upgrade.creditCents,'0');
 const downgrade=quotePlanProration({...base,currentNetCents:16000,nextNetCents:10000});assert.equal(downgrade.chargeCents,'0');assert.equal(downgrade.creditCents,'3000');assert.equal(downgrade.automaticRefund,false);assert.equal(downgrade.creditDestination,'next_invoice');
});
test('cycle boundaries and unchanged net price have no invented extra period',()=>{
 assert.equal(quotePlanProration({...base,effectiveAt:1000}).adjustmentCents,'6000');assert.equal(quotePlanProration({...base,effectiveAt:3000}).adjustmentCents,'0');assert.equal(quotePlanProration({...base,nextNetCents:10000}).adjustmentCents,'0');
});
test('half-cent rounds symmetrically and preserves exact audit numerator',()=>{
 const p={...base,currentNetCents:0,nextNetCents:1};assert.equal(quotePlanProration(p).adjustmentCents,'1');assert.equal(quotePlanProration({...p,currentNetCents:1,nextNetCents:0}).adjustmentCents,'-1');assert.equal(quotePlanProration(p).basisNumerator,'1000');assert.equal(quotePlanProration(p).basisDenominator,'2000');
});
test('actual leap-month cycle uses its exact duration, not a fixed thirty-day divisor',()=>{
 const start=Date.parse('2028-02-01T03:00:00Z'),end=Date.parse('2028-03-01T03:00:00Z'),effective=Date.parse('2028-02-15T03:00:00Z');
 assert.equal(quotePlanProration({...base,cycleStart:start,cycleEnd:end,effectiveAt:effective,currentNetCents:0,nextNetCents:2900}).chargeCents,'1500');
});
test('invalid amounts, times and out-of-cycle changes are rejected without mutating input',()=>{
 for(const patch of [{currentNetCents:-1},{nextNetCents:1.5},{cycleStart:NaN},{cycleEnd:1000},{effectiveAt:999},{effectiveAt:3001},{nextNetCents:Number.MAX_SAFE_INTEGER+1}])assert.throws(()=>quotePlanProration({...base,...patch}));
 const copy={...base};quotePlanProration(copy);assert.deepEqual(copy,base);
});
