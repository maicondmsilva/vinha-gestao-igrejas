import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');

test('Escalas usam uma folha de estilo só',()=>{
 for(const f of ['app/ScalesWorkspace.tsx','app/ScalesFoundation.tsx','app/ScalesWeekPanel.tsx','app/ScalesBoard.tsx','app/ScalesOperations.tsx']){
  const imports=[...read(f).matchAll(/import '\.\/(scales[a-z-]*\.css)'/g)].map(m=>m[1]);
  assert.ok(imports.every(i=>i==='scales-ui.css'),f+': '+imports.join(','));
 }
 assert.match(read('app/ScalesWorkspace.tsx'),/import '\.\/scales-ui\.css'/);
 for(const old of ['app/scales.css','app/scales-persistent.css','app/scales-planning.css','app/scales-foundation.css','app/scales-week.css','app/scales-board.css','app/ScaleOperations.tsx'])assert.ok(!existsSync(new URL('../'+old,import.meta.url)),old+' ainda existe');
});

test('padrão novo: letras legíveis em px e títulos sem serifa',()=>{
 const css=read('app/scales-ui.css');
 for(const m of css.matchAll(/font-size:\s*(\d+)px/g))assert.ok(Number(m[1])>=12,m[0]);
 assert.doesNotMatch(css,/font-size:\s*[\d.]+rem/);
 assert.doesNotMatch(css,/Georgia|serif/);
 assert.match(css,/\.sp-workspace h2\{[^}]*font-size:22px/);
 assert.match(css,/@media\(max-width:640px\)/);
});

test('app do voluntário mantém só a própria folha',()=>{
 const v=read('app/scales-volunteer.css');
 assert.match(v,/\.sv-portal/);assert.doesNotMatch(v,/\.so-panel|\.so-rows/);
});
