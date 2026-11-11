import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {financeCommand} from '../app/lib/finance-f1.ts';
import {financeReason} from '../app/lib/finance-errors.ts';

const id='ab900000-0000-4000-8000-000000000001',unit='ab900000-0000-4000-8000-000000000002';
const editor=readFileSync(new URL('../app/FinanceEntryEditor.tsx',import.meta.url),'utf8');

test('excluir aceita só id e versão, sem motivo',()=>{
 assert.deepEqual(financeCommand({action:'delete',unitId:unit,data:{id,version:2}}),{action:'delete',unitId:unit,data:{id,version:2}});
 assert.throws(()=>financeCommand({action:'delete',unitId:unit,data:{id,version:2,reason:'x'}}));
 assert.throws(()=>financeCommand({action:'delete',unitId:unit,data:{id,version:0}}));
 assert.throws(()=>financeCommand({action:'delete',unitId:unit,data:{id:'x',version:1}}));
});

test('excluir pede confirmação na tela e não aparece para provedor, baixa ou estornado',()=>{
 assert.match(editor,/Excluir este lançamento\?/);
 assert.match(editor,/action:'delete'/);
 assert.match(editor,/canDeleteFinanceEntry\(e:Entry\)\{return \['pending','posted','cancelled'\]\.includes\(e\.status\)/);
 for(const rule of ['!e.reversal_id','!e.settlement_id','!e.digital_kind'])assert.ok(editor.includes(rule),rule);
});

test('motivos de recusa da exclusão têm texto claro',()=>{
 assert.match(financeReason('entry_already_reversed'),/estornado/);
 assert.match(financeReason('entry_from_statement'),/extrato/);
 assert.match(financeReason('use_settlement_reversal_first'),/Estorne a baixa/);
});
