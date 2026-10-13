import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
const roots=['app'];
const files=[];
const walk=dir=>{for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const file=path.join(dir,entry.name);if(entry.isDirectory()&&!['node_modules','.next','dist'].includes(entry.name))walk(file);else if(entry.isFile()&&file.endsWith('.tsx'))files.push(file)}};
for(const root of roots)walk(root);
const issues=[];
for(const file of files){const source=fs.readFileSync(file,'utf8'),ast=ts.createSourceFile(file,source,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX);const visit=node=>{if(ts.isJsxElement(node)&&node.openingElement.tagName.getText(ast)==='button'){const attrs=node.openingElement.attributes.properties,has=name=>attrs.some(attr=>attr.name?.getText(ast)===name),type=attrs.find(attr=>attr.name?.getText(ast)==='type')?.initializer?.getText(ast)||'',isSubmit=/submit/.test(type),insideForm=Boolean(function parent(n){if(!n?.parent)return false;return ts.isJsxElement(n.parent)&&n.parent.openingElement.tagName.getText(ast)==='form'||parent(n.parent)}(node));if(!has('onClick')&&!has('formAction')&&!has('disabled')&&!has('aria-current')&&!isSubmit&&!insideForm){const line=ast.getLineAndCharacterOfPosition(node.getStart(ast)).line+1,text=node.children.map(child=>child.getText(ast)).join('').replace(/<[^>]*>/g,' ').replace(/[{}]/g,' ').replace(/\s+/g,' ').trim().slice(0,70);issues.push(`${file}:${line} — ${text||'botão sem rótulo'}`)}}ts.forEachChild(node,visit)};visit(ast)}
const existingDebt=50;
if(issues.length>existingDebt){console.error(`A revisão encontrou ${issues.length} botões sem ação explícita; o limite atual é ${existingDebt}.\n${issues.join('\n')}\n\nTodo novo botão deve navegar, abrir um modal, enviar um formulário ou declarar aria-current/disabled.`);process.exit(1)}
if(issues.length)console.warn(`${issues.length} controles legados ainda usam a proteção global contra cliques silenciosos. O número não pode aumentar.`);else console.log('Todos os botões possuem uma ação explícita.');
