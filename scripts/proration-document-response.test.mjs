import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseProrationDocuments} from '../app/lib/proration-document-response.ts';
const document={id:'synthetic',kind:'credit',createdAt:'2026-10-18T12:00:00Z',amountCents:'1500',usedCents:'1000',remainingCents:'500',externalChargeCreated:false};
test('document response confirms exact credit and empty history',()=>{assert.deepEqual(parseProrationDocuments({pilot:true,documents:[document]}),[document]);assert.deepEqual(parseProrationDocuments({pilot:true,documents:[]}),[])});
test('invalid balances and external charges never display as confirmed',()=>{for(const patch of [{remainingCents:'600'},{usedCents:1000},{amountCents:'-1'},{createdAt:'bad'},{externalChargeCreated:true}])assert.throws(()=>parseProrationDocuments({pilot:true,documents:[{...document,...patch}]}))});
test('duplicate, truncated and non-pilot responses fail closed',()=>{for(const value of [{pilot:false,documents:[]},{pilot:true,documents:[document,document]},{pilot:true,documents:Array(101).fill(document)},null])assert.throws(()=>parseProrationDocuments(value))});
test('internal additional document is accepted without credit balance',()=>{assert.equal(parseProrationDocuments({pilot:true,documents:[{...document,kind:'additional_invoice',usedCents:'0',remainingCents:null}]})[0].remainingCents,null)});
