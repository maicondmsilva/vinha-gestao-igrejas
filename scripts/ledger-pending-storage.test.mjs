import assert from 'node:assert/strict';
import {test} from 'node:test';
import {restoreLedgerPending,saveLedgerPending,clearLedgerPending} from '../app/lib/ledger-recovery.ts';
const a='a0000000-0000-4000-8000-000000000001',b='b0000000-0000-4000-8000-000000000002',c='c0000000-0000-4000-8000-000000000003';
const scope=a+':'+b,command={action:'post',unitId:c,requestId:a,date:'2026-10-18',memo:'Teste sintético',debit:a,credit:b,amount:'1,23'};
function store(){const values=new Map();return{values,getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)}}
test('pending survives new reader, preserves exact request and excludes extra credentials',()=>{
 const s=store();saveLedgerPending(s,scope,[c],{...command,token:'must-not-persist'});assert.deepEqual(restoreLedgerPending(s,scope,[c]),command);assert.doesNotMatch([...s.values.values()].join(),/token|must-not-persist/);clearLedgerPending(s,scope);assert.equal(restoreLedgerPending(s,scope,[c]),null);
});
test('other actor or ministry cannot restore a pending command and unauthorized unit blocks',()=>{
 const s=store();saveLedgerPending(s,scope,[c],command);assert.equal(restoreLedgerPending(s,b+':'+b,[c]),null);assert.equal(restoreLedgerPending(s,a+':'+c,[c]),null);assert.throws(()=>restoreLedgerPending(s,scope,[b]));
});
test('corruption and different pending requests fail closed without overwriting',()=>{
 const s=store();saveLedgerPending(s,scope,[c],command);assert.throws(()=>saveLedgerPending(s,scope,[c],{...command,requestId:b}));assert.deepEqual(restoreLedgerPending(s,scope,[c]),command);const k=[...s.values.keys()][0];s.setItem(k,'bad JSON');assert.throws(()=>restoreLedgerPending(s,scope,[c]));assert.equal(s.getItem(k),'bad JSON');
});
test('unavailable or silently broken storage never confirms protection',()=>{
 const s=store();s.setItem=()=>{};assert.throws(()=>saveLedgerPending(s,scope,[c],command));assert.throws(()=>saveLedgerPending(s,'unverified',[c],command));
});
