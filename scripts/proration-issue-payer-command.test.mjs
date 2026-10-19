import {test} from 'node:test';
import assert from 'node:assert/strict';
import {issueProrationCommand} from '../app/lib/proration-issue-command.ts';
import {payerChangeCommand} from '../app/lib/proration-payer-command.ts';
const id='a0000000-0000-4000-8000-000000000001';
test('issue accepts only identifiers and explicit replacement, never browser amounts',()=>{const value={requestId:id,contractId:id,referenceMonth:'2026-11',replacesInvoiceId:id};assert.deepEqual(issueProrationCommand({...value,amountCents:1}),value);assert.throws(()=>issueProrationCommand({...value,replacesInvoiceId:'bad'}));assert.throws(()=>issueProrationCommand({...value,referenceMonth:'2026-13'}))});
test('payer change preserves precise version but never accepts transferring old credit',()=>{const value={requestId:id,contractId:id,payerUnitId:id,expectedUpdatedAt:'2026-10-18T12:00:00.123456Z',reason:'Solicitação sintética'};assert.deepEqual(payerChangeCommand({...value,transferCredits:true}),value);assert.throws(()=>payerChangeCommand({...value,reason:''}));assert.throws(()=>payerChangeCommand({...value,payerUnitId:'bad'}))});
