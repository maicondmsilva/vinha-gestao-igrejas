import {test} from 'node:test';
import assert from 'node:assert/strict';
import {eventCheckoutMethods} from '../shared/event-payment-methods.ts';
test('event narrows verified receiver methods without enabling extra methods',()=>{
 assert.deepEqual(eventCheckoutMethods(['pix','card','boleto'],['pix']),['pix']);
 assert.throws(()=>eventCheckoutMethods(['pix'],['card']));
 assert.throws(()=>eventCheckoutMethods(undefined,['pix']));
});
test('invalid or empty snapshot fails closed',()=>{
 for(const value of [[],['pix','pix'],['cash'],'pix',[null]])assert.throws(()=>eventCheckoutMethods(['pix','card'],value));
});
test('legacy orders inherit receiver configuration only without a snapshot',()=>{
 assert.deepEqual(eventCheckoutMethods(['pix'],null),['pix']);
 assert.deepEqual(eventCheckoutMethods(['card'],undefined),['card']);
});
