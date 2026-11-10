import {test} from 'node:test';
import assert from 'node:assert/strict';
import {cancellationCommand} from '../app/lib/proration-cancellation-command.ts';
const id='a0000000-0000-4000-8000-000000000001',command={requestId:id,contractId:id,invoiceId:id,reason:'Cancelamento sintético'};
test('cancellation whitelist never accepts client refund amounts or payer',()=>assert.deepEqual(cancellationCommand({...command,amountCents:999,payerUnitId:id,automaticRefund:true}),command));
test('cancellation requires stable identifiers and meaningful reason',()=>{for(const patch of [{requestId:'bad'},{invoiceId:null},{contractId:''},{reason:' '},{reason:'a'.repeat(301)}])assert.throws(()=>cancellationCommand({...command,...patch}))});
