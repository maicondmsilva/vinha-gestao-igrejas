import {test} from 'node:test';
import assert from 'node:assert/strict';
import {requiresProrationReview} from '../app/lib/contract-write-guard.ts';
const current={status:'active',plan_id:'a',payer_unit_id:'payer',due_day:10,module_decisions:{kids:true,events:false}};
const next={planId:'a',payerUnitId:'payer',dueDay:10,modules:{events:false,kids:true}};
test('unchanged commercial fields allow contact-only edits regardless of JSON key order',()=>assert.equal(requiresProrationReview(current,{...next,profile:{email:'qa@example.invalid'}}),false));
test('active commercial changes require proportional review',()=>{
 for(const patch of [{planId:'b'},{payerUnitId:'other'},{dueDay:12},{modules:{kids:false}}])assert.equal(requiresProrationReview(current,{...next,...patch}),true);
});
test('new and draft contracts retain their existing onboarding flow',()=>{
 assert.equal(requiresProrationReview(null,next),false);
 assert.equal(requiresProrationReview({...current,status:'draft'},{...next,planId:'b'}),false);
});
