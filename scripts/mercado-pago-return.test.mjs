import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
const path=new URL('../app/pagamentos/assinatura/retorno/page.tsx',import.meta.url);
test('retorno é informativo: não aceita parâmetros nem grava resultado financeiro',()=>{
 const source=readFileSync(path,'utf8');
 assert.match(source,/Pagamento não confirmado nesta página/);
 assert.match(source,/consulta automática da assinatura ainda não está disponível/);
 assert.doesNotMatch(source,/searchParams|useSearchParams|fetch\(|localStorage|sessionStorage|supabase|dangerouslySetInnerHTML/);
 for(const route of ['minha-assinatura','suporte','login']){
  assert.ok(source.includes(`href="/${route}"`));
  assert.ok(existsSync(new URL(`../app/${route}/page.tsx`,import.meta.url)));
 }
});
