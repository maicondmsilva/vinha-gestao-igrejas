import test from 'node:test';
import assert from 'node:assert/strict';
import {f6Csv,f6Query,f6Table} from '../app/lib/finance-f6.ts';

test('F7 CSV preserva valores negativos sem permitir fórmulas',()=>{
 const csv=f6Csv({headers:['Valor'],rows:[['-50,00'],['-HYPERLINK("x")'],['\u0001=SUM(1)'],['+10']],notice:''});
 assert.ok(csv.includes('"-50,00"'));assert.ok(!csv.includes('"\'-50,00"'));
 assert.ok(csv.includes("'-HYPERLINK"));assert.ok(csv.includes("'\u0001=SUM"));assert.ok(csv.includes("'+10"));
});
test('F7 exportação inclui posição de caixa e protege nomes externos',()=>{
 const csv=f6Csv({headers:['Valor'],rows:[],notice:'Conferir'},[],[{unitName:'=SUM(1)',name:'Banco',opening:'10000',closing:'9650'}]);
 assert.match(csv,/saldo anterior: 100,00/);assert.match(csv,/saldo final: 96,50/);assert.ok(csv.includes("'=SUM(1)"));
});
test('F7 cliente não controla indicador interno de auditoria',()=>{
 assert.throws(()=>f6Query(new Request('https://local/?units=cf770000-0000-4000-8000-000000000001&from=2026-09-01&to=2026-09-30&export=true')));
});
test('F7 orçamento sem movimento usa nome autorizado, nunca UUID',()=>{
 const data={rows:[],budgets:[{id:'b',unit:'uuid-interno',unitName:'Campus Norte',month:'2026-09-01',category:'c',categoryName:'Doações',center:null,centerName:null,amount:'10000',version:1}],digital:[],bankPending:[],balances:[],accounting:[],individualAccess:true};
 const table=f6Table(data,'budget');assert.equal(table.rows[0][1],'Campus Norte');assert.ok(!JSON.stringify(table).includes('uuid-interno'));
});
