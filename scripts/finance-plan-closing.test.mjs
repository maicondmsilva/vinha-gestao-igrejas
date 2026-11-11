import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=(f)=>readFileSync(new URL('../app/'+f,import.meta.url),'utf8');

test('relatórios oferecem modelos de colunas por nome (Resumo e Prestação de contas)',()=>{
 const s=read('FinanceReports.tsx');
 assert.match(s,/\['Resumo',\['Data de referência','Descrição','Categoria','Valor assinado'\]\]/);
 assert.match(s,/\['Prestação de contas',\[/);
 assert.match(s,/names\.every\(n=>availableTable\.headers\.includes\(n\)\)/,'modelo só aparece quando o relatório tem todas as colunas');
 assert.match(s,/Selecionar todas/);
});

test('Recebimentos digitais: rodapé com intervalo, total do período e páginas',()=>{
 const s=read('FinanceDigital.tsx');
 assert.match(s,/Página \{cursors\.length\+1\}/);
 assert.match(s,/>Anterior<\/button>/);
 assert.match(s,/>Próxima<\/button>/);
 assert.doesNotMatch(s,/Mais antigos|Mais recentes/);
 assert.match(s,/totals\?\.count/);
});

test('Contas recebedoras: passo a passo da chave recolhido',()=>{
 const s=read('FinanceReceiving.tsx');
 assert.match(s,/<details className="f1-steps"><summary>Onde encontro a chave\?<\/summary>/);
 assert.match(s,/Nunca informe sua senha/);
});
