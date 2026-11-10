import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readPlanPreview} from '../app/lib/plan-preview-response.ts';
const value={pilot:true,confirmationAvailable:false,contractId:'contract',nextPlanId:'plan',estimate:{estimateOnly:true,automaticRefund:false,creditDestination:'next_invoice',chargeCents:'3000',creditCents:'0',currentNetCents:'10000',nextNetCents:'16000',cycleStart:0,effectiveAt:1500,cycleEnd:3000}};
test('preview response is bound to selected contract and plan',()=>{assert.equal(readPlanPreview(value,'contract','plan').chargeCents,'3000');assert.throws(()=>readPlanPreview(value,'another','plan'));assert.throws(()=>readPlanPreview(value,'contract','another'))});
test('unsafe monetary values, expired periods and simultaneous debit/credit are refused',()=>{for(const patch of [{chargeCents:3000},{creditCents:'1'},{effectiveAt:3000},{automaticRefund:true},{chargeCents:'-1'}])assert.throws(()=>readPlanPreview({...value,estimate:{...value.estimate,...patch}},'contract','plan'))});
test('preview must not silently enable confirmation',()=>assert.throws(()=>readPlanPreview({...value,confirmationAvailable:true},'contract','plan')));
