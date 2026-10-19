import assert from 'node:assert/strict';
import {test} from 'node:test';
import {parseMemberCsv,validateImportRows,validCpf,normalizeBirthDate} from '../app/lib/member-import.ts';
import {peopleQuery,peopleSearchFilter} from '../app/lib/people-query.ts';
test('CSV handles quoted semicolons, multiline names, escaped quotes and BOM',()=>{
 const rows=parseMemberCsv('\uFEFFNome;E-mail\r\n"Maria; Silva";maria@example.test\r\n"Ana ""B""";ana@example.test');
 assert.equal(rows.length,2);assert.equal(rows[0].nome,'Maria; Silva');assert.equal(rows[1].nome,'Ana "B"');
 assert.throws(()=>parseMemberCsv('Nome;Nome\nA;B'));assert.throws(()=>parseMemberCsv('Nome\n"não fechado'));
});
test('import validates identity fields without assuming login or consent',()=>{
 assert.equal(validCpf('52998224725'),true);assert.equal(validCpf('11111111111'),false);
 assert.equal(normalizeBirthDate('29/02/2024'),'2024-02-29');assert.equal(normalizeBirthDate('31/02/2024'),null);
 const checked=validateImportRows([{nome:'Maria Silva',email:'MARIA@example.test',cpf:'529.982.247-25',nascimento:'01/02/1990'},{nome:'Outra pessoa',email:'maria@example.test'}]);
 assert.equal(checked[0].errors.length,0);assert.equal(checked[0].row.email,'maria@example.test');assert.ok(checked[1].errors.some(x=>x.includes('repetido')));
 assert.ok(validateImportRows([{nome:'X',role:'owner'}])[0].errors.length);assert.throws(()=>validateImportRows(new Array(501).fill({nome:'Pessoa'})));
});
test('database query bounds pages and treats PostgREST syntax as literal search input',()=>{
 assert.equal(peopleQuery(new Request('https://vinha.test/?page=2&limit=25')).from,25);
 for(const q of ['?limit=101','?page=-1','?page=1.2','?unitId=other','?status=administrator'])assert.throws(()=>peopleQuery(new Request('https://vinha.test/'+q)));
 const search=peopleSearchFilter('a,b)%_"');assert.ok(search.includes('\\%'));assert.ok(search.includes('\\_'));assert.equal(search.split('.ilike.').length-1,3);
});
