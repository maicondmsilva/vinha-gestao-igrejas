import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {peopleFilters,hasAdvanced,ageRange,bulkInput,mergeInput,convertInput,exportRow,safeCell,timelineGroups,eventDate,peopleToolError} from '../app/lib/people-tools.ts';
const u='b0000000-0000-4000-8000-000000000001',v='b0000000-0000-4000-8000-000000000002';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const qs=s=>new URLSearchParams(s);
test('filtros avançados da lista',()=>{
 assert.deepEqual(peopleFilters(qs(`cell=${u}&gender=Feminino&ageMin=18&ageMax=29&baptized=sim&tag=Louvor&converts=1`)),{cell:u,gender:'Feminino',ageMin:18,ageMax:29,baptized:true,tag:'Louvor',converts:true});
 assert.deepEqual(peopleFilters(qs('baptized=nao')),{baptized:false});
 assert.equal(hasAdvanced(peopleFilters(qs('q=ana&status=Membro'))),false,'busca simples segue o caminho antigo');
 assert.throws(()=>peopleFilters(qs('cell=abc')));assert.throws(()=>peopleFilters(qs('gender=x')));
 assert.throws(()=>peopleFilters(qs('ageMin=40&ageMax=20')));assert.throws(()=>peopleFilters(qs('baptized=talvez')));
 assert.deepEqual(ageRange('18-29'),{ageMin:'18',ageMax:'29'});assert.deepEqual(ageRange('60-'),{ageMin:'60'});assert.deepEqual(ageRange('0-11'),{ageMax:'11'});assert.deepEqual(ageRange(''),{});
});
test('ações em lote validam a forma do pedido',()=>{
 assert.deepEqual(bulkInput({unit:u,action:'journey',ids:[v,v],value:'Membro'}),{unit:u,action:'journey',data:{ids:[v],value:'Membro'}});
 assert.equal(bulkInput({unit:u,action:'tag',ids:[v],value:'  Retiro  '}).data.value,'Retiro');
 assert.throws(()=>bulkInput({unit:u,action:'journey',ids:[v],value:'Líder'}));
 assert.throws(()=>bulkInput({unit:u,action:'tag',ids:[],value:'x'}));
 assert.throws(()=>bulkInput({unit:u,action:'notify',ids:Array(251).fill(v).map((_,i)=>v.slice(0,-3)+String(i).padStart(3,'0')),title:'Oi',body:'Mensagem',request:u}),/250/);
 assert.throws(()=>bulkInput({unit:u,action:'notify',ids:[v],title:'Oi',body:'Mensagem'}),/Pedido/);
 assert.throws(()=>bulkInput({unit:u,action:'apagar',ids:[v]}));
});
test('unificar e acompanhar convertidos',()=>{
 assert.deepEqual(mergeInput({unit:u,action:'merge',keep:u,remove:v}),{unit:u,action:'merge',data:{keep:u,remove:v}});
 assert.throws(()=>mergeInput({unit:u,action:'merge',keep:u,remove:u}));
 assert.deepEqual(convertInput({unit:u,person:v,status:'in_cell',followup:'',note:'ok'}).data,{person:v,status:'in_cell',followup:'',note:'ok'});
 assert.throws(()=>convertInput({unit:u,person:v,status:'feito'}));
 assert.throws(()=>convertInput({unit:u,person:v,convertedAt:'13/11/2026'}));
 assert.equal(peopleToolError('55000').status,409);assert.equal(peopleToolError('42501').status,403);
});
test('exportação protege contra fórmulas e usa datas brasileiras',()=>{
 assert.equal(safeCell('=HYPERLINK("x")'),'\'=HYPERLINK("x")');assert.equal(safeCell('+5511'),"'+5511");assert.equal(safeCell('Ana'),'Ana');
 const row=exportRow({name:'@Ana',email:'',phone:'',status:'Membro',group:'',birthDate:'1990-05-02',gender:'',maritalStatus:'',baptized:'Sim',baptismDate:'',tags:'',since:'',campus:'',address:'',number:'',district:'',city:'',state:'',zip:''});
 assert.equal(row.name,"'@Ana");assert.equal(row.birthDate,'02/05/1990');assert.equal(row.code,'');
});
test('histórico agrupado por mês',()=>{
 const g=timelineGroups([{at:'2026-11-10T15:00:00Z'},{at:'2026-11-02'},{at:'2026-09-01'}]);
 assert.equal(g.length,2);assert.equal(g[0].items.length,2);assert.match(g[0].label,/novembro/);
 assert.equal(eventDate('2026-11-02'),'02/11/2026');
});
test('rotas e telas ligadas',()=>{
 const r=read('app/lib/supabase/people-tools-routes.ts');
 for(const f of ['people_duplicates','person_timeline','people_converts','people_bulk'])assert.match(r,new RegExp(f));
 assert.match(r,/p_org:a\.membership\.organization_id/);assert.match(r,/membership\.units\.some/);
 assert.match(read('app/api/people/route.ts'),/people_search/);
 const d=read('app/PeopleDirectory.tsx');for(const s of ['Novos convertidos','Duplicados','Exportar Excel','Ações em lote','Enviar agora','Faixa etária','Rede'])assert.ok(d.includes(s),s);
 assert.match(read('app/DashboardApp.tsx'),/<PersonTimeline person=/);
 assert.match(read('app/PeopleDuplicates.tsx'),/não pode ser desfeita/);
 assert.match(read('shared/contract/push.ts'),/people: ids\(250/);
});
