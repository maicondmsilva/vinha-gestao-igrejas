import assert from 'node:assert/strict';
import {test} from 'node:test';
import {ledgerBalanceCsv} from '../app/lib/ledger-report.ts';
const id='a0000000-0000-4000-8000-000000000001';
const row={accountId:id,name:'Conta "A";teste',kind:'asset',balanceCents:'900719925474099300'};
test('CSV preserves exact cents and escapes delimiters and quotes',()=>{
 const csv=ledgerBalanceCsv(id,'2026-10-18',[row]);assert.match(csv,/900719925474099300/);assert.match(csv,/9007199254740993,00/);assert.ok(csv.includes('Conta ""A"";teste'));assert.ok(csv.startsWith('\uFEFF'));assert.equal(csv.split('\r\n').length,3);
});
test('CSV neutralizes spreadsheet formulas, including leading whitespace',()=>{
 for(const name of ['=HYPERLINK("x")',' +SUM(1)','\t@SUM(1)','-1+1'])assert.ok(ledgerBalanceCsv(id,'2026-10-18',[{...row,name}]).includes('"\''));
});
test('CSV rejects invalid scopes, dates, excessive rows and malformed balances',()=>{
 assert.throws(()=>ledgerBalanceCsv('bad','2026-10-18',[row]));assert.throws(()=>ledgerBalanceCsv(id,'2026-02-30',[row]));assert.throws(()=>ledgerBalanceCsv(id,'2026-10-18',Array(501).fill(row)));assert.throws(()=>ledgerBalanceCsv(id,'2026-10-18',[{...row,balanceCents:'1.23'}]));
});
