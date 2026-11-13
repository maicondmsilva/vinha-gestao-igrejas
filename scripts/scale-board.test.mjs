import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {boardQuery,boardCommand,boardPublishMessage,conflictLabels,weekRange} from '../app/lib/scale-board.ts';
const u='e0000000-0000-4000-8000-000000000001',s='e0000000-0000-4000-8000-000000000002',r='e0000000-0000-4000-8000-000000000003',m='e0000000-0000-4000-8000-000000000004';
test('consulta exige igreja e período válido de até 62 dias',()=>{
 assert.deepEqual(boardQuery(new Request(`https://v.test/api/scales-board?unit=${u}&from=2026-11-01&to=2026-11-30`)),{unit:u,data:{from:'2026-11-01',to:'2026-11-30'}});
 assert.throws(()=>boardQuery(new Request(`https://v.test/api/scales-board?unit=${u}&from=2026-11-01&to=2027-02-01`)));
 assert.throws(()=>boardQuery(new Request(`https://v.test/api/scales-board?unit=x&from=2026-11-01&to=2026-11-30`)));
 assert.throws(()=>boardQuery(new Request(`https://v.test/api/scales-board?unit=${u}&from=2026-11-30&to=2026-11-01`)));
});
test('escalar e publicar validam campos',()=>{
 assert.ok(boardCommand({unit:u,action:'assign',data:{service:s,role:r,ordinal:1,member:m,version:3}}));
 assert.ok(boardCommand({unit:u,action:'assign',data:{service:s,role:r,ordinal:1,member:null,version:3}}));
 assert.throws(()=>boardCommand({unit:u,action:'assign',data:{service:s,role:r,ordinal:0,member:m,version:3}}));
 assert.throws(()=>boardCommand({unit:u,action:'assign',data:{service:s,role:r,ordinal:1,member:m}}));
 assert.ok(boardCommand({unit:u,action:'publish',data:{services:[s]}}));
 assert.throws(()=>boardCommand({unit:u,action:'publish',data:{services:[]}}));
 assert.throws(()=>boardCommand({unit:u,action:'publish',data:{services:[s],override:true,reason:'curto'}}));
 assert.throws(()=>boardCommand({unit:u,organization:u,action:'publish',data:{services:[s]}}));
});
test('resultado do lote em português',()=>{
 assert.equal(boardPublishMessage({published:[s,s],failed:[]}),'2 escalas publicadas.');
 assert.match(boardPublishMessage({published:[s],failed:[{id:s,code:'22023',error:'scale_conflict'}]}),/1 escala publicada.*1 com conflito/);
});
test('rótulos de conflito e semana',()=>{
 assert.equal(conflictLabels.unavailable,'Indisponível');assert.ok(conflictLabels.availability&&conflictLabels.qualification);
 assert.deepEqual(weekRange('2026-11-13',14),{from:'2026-11-13',to:'2026-11-26'});
});
test('rota usa a igreja da sessão e o quadro está nas Escalas',()=>{
 const route=readFileSync(new URL('../app/api/scales-board/route.ts',import.meta.url),'utf8');assert.match(route,/p_org:auth\.access!\.membership\.organization_id/);assert.match(route,/scale_board/);
 const ws=readFileSync(new URL('../app/ScalesWorkspace.tsx',import.meta.url),'utf8');assert.match(ws,/\['montagem','Quadro de montagem'\]/);assert.match(ws,/<ScalesBoard/);
 const ui=readFileSync(new URL('../app/ScalesBoard.tsx',import.meta.url),'utf8');assert.match(ui,/Publicar selecionadas/);assert.match(ui,/action:'suggest'/);
 const css=readFileSync(new URL('../app/scales-ui.css',import.meta.url),'utf8');for(const x of css.matchAll(/font-size:(\d+)px/g))assert.ok(Number(x[1])>=12,x[0]);
});
