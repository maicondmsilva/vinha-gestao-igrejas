import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readProrationCatalog,prorationCatalogPrice} from '../app/lib/proration-catalog.ts';
import {planConfirmationCommand} from '../app/lib/plan-change-command.ts';
const snapshot={plan:{id:'next',base_price_cents:10000},modules:[{code:'kids',monthly_price_cents:1000}],links:[{plan_id:'next',module_code:'kids',included:true}]};
test('preview pricing comes from preserved snapshot and never bills included add-on twice',()=>{const catalog=readProrationCatalog(snapshot,'next');assert.deepEqual(catalog,snapshot);assert.equal(prorationCatalogPrice(catalog,{kids:true}),10000);assert.equal(prorationCatalogPrice({...catalog,links:[]},{kids:true}),11000)});
test('invalid and ambiguous catalog snapshots fail closed',()=>{for(const value of [{...snapshot,modules:[...snapshot.modules,...snapshot.modules]},{...snapshot,links:[{...snapshot.links[0],plan_id:'other'}]},{...snapshot,plan:{id:'next',base_price_cents:null}},null])assert.throws(()=>readProrationCatalog(value,'next'))});
test('confirmation requires exact target catalog and whitelists identifiers',()=>{const id='a0000000-0000-4000-8000-000000000001',command={requestId:id,contractId:id,baseInvoiceId:id,nextPlanId:'next',expectedUpdatedAt:'2026-10-18T12:00:00Z',cycleStart:0,cycleEnd:86400000,expectedCatalog:snapshot};assert.deepEqual(planConfirmationCommand({...command,amountCents:1}),command);assert.throws(()=>planConfirmationCommand({...command,expectedCatalog:null}));assert.throws(()=>planConfirmationCommand({...command,nextPlanId:'other'}))});
