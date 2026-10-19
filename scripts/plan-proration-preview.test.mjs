import {test} from 'node:test';
import assert from 'node:assert/strict';
import {previewCumulativeProration} from '../app/lib/plan-proration-preview.ts';
const input={currentNetCents:10000,nextNetCents:16000,cycleStart:0,cycleEnd:3000,effectiveAt:1500,accumulatedNumerator:'0',roundedAdjustmentCents:'0'};
test('initial proportional preview matches half-cycle debit and marks estimate',()=>{const result=previewCumulativeProration(input);assert.equal(result.chargeCents,'3000');assert.equal(result.estimateOnly,true);assert.equal(result.automaticRefund,false)});
test('inverse change preserves cumulative rounding rather than inventing a cent',()=>{
 const first=previewCumulativeProration({...input,currentNetCents:100,nextNetCents:101,cycleEnd:3,effectiveAt:1});
 const inverse=previewCumulativeProration({...input,currentNetCents:101,nextNetCents:100,cycleEnd:3,effectiveAt:1,accumulatedNumerator:first.accumulatedNumerator,roundedAdjustmentCents:first.roundedAdjustmentCents});
 assert.equal(first.adjustmentCents,'1');assert.equal(inverse.adjustmentCents,'-1');assert.equal(inverse.roundedAdjustmentCents,'0');
});
test('previous cumulative fraction affects the next debit',()=>{assert.equal(previewCumulativeProration({...input,currentNetCents:100,nextNetCents:101,cycleEnd:3,effectiveAt:2,accumulatedNumerator:'1',roundedAdjustmentCents:'0'}).chargeCents,'1')});
test('invalid and inconsistent histories fail closed',()=>{for(const patch of [{accumulatedNumerator:'1.5'},{roundedAdjustmentCents:'1'},{accumulatedNumerator:'9'.repeat(51)}])assert.throws(()=>previewCumulativeProration({...input,...patch}))});
