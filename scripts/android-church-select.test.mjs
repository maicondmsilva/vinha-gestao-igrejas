import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';

function fixture(disabled=false){
 let opened=false,value='a';const changes=[];
 const source=readFileSync(new URL('../android-app/src/ChurchSelect.tsx',import.meta.url),'utf8');
 const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,jsx:ts.JsxEmit.React}}).outputText.replace(/^import .*;\r?\n/gm,'').replace('export default function','function');
 const React={createElement:(type,props,...children)=>({type,props:{...props,children:children.flat()}})};
 const Component=new Function('React','useState','useEffect','Pressable','ScrollView','StyleSheet','Text','View',code+';return ChurchSelect;')(React,()=>[opened,next=>{opened=typeof next==='function'?next(opened):next}],fn=>fn(),'Pressable','ScrollView',{create:v=>v},'Text','View');
 return{changes,render:()=>Component({churches:[{id:'a',name:'Igreja A'},{id:'b',name:'Igreja B'}],value,onChange:id=>{value=id;changes.push(id)},disabled,color:'#111',background:'#fff',accent:'#285c45'})};
}
function nodes(tree){if(!tree||typeof tree!=='object')return[];return[tree,...(tree.props?.children||[]).flatMap(nodes)]}
test('igreja aparece em um único campo recolhido',()=>{const ui=nodes(fixture().render());assert.equal(ui.filter(n=>n.props.accessibilityRole==='combobox').length,1);assert.equal(ui.filter(n=>n.props.accessibilityRole==='radio').length,0);assert.equal(ui.find(n=>n.props.accessibilityRole==='combobox').props.accessibilityValue.text,'Igreja A')});
test('abrir e selecionar fecha a lista e preserva o identificador',()=>{const f=fixture();nodes(f.render()).find(n=>n.props.accessibilityRole==='combobox').props.onPress();const options=nodes(f.render()).filter(n=>n.props.accessibilityRole==='radio');assert.equal(options.length,2);options[1].props.onPress();assert.deepEqual(f.changes,['b']);const ui=nodes(f.render());assert.equal(ui.filter(n=>n.props.accessibilityRole==='radio').length,0);assert.equal(ui.find(n=>n.props.accessibilityRole==='combobox').props.accessibilityValue.text,'Igreja B')});
test('campo bloqueado mantém a seleção e não expõe lista',()=>{const f=fixture(true),ui=nodes(f.render()),field=ui.find(n=>n.props.accessibilityRole==='combobox');assert.equal(field.props.disabled,true);assert.equal(field.props.accessibilityState.disabled,true);assert.equal(ui.filter(n=>n.props.accessibilityRole==='radio').length,0);assert.deepEqual(f.changes,[])});
