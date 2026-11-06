import test from 'node:test';
import assert from 'node:assert/strict';
import ExcelJS from 'exceljs';
import {PDFDocument} from 'pdf-lib';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
import {renderToStaticMarkup} from 'react-dom/server';
import {financeXlsx,financePdf,financePdfLayout,reportLogo,exportCell,reportContext,pdfCell} from '../app/lib/finance-export.ts';
import {financeReports,f6Query,f6Table,selectReportColumns,reportColumns,f6ExportQuery} from '../app/lib/finance-f6.ts';
const unit='cf600000-0000-4000-8000-000000000001';
export const fixture={rows:[{code:'0001',unit,unitName:'Sede fictícia',date:'2026-09-15',cashDate:'2026-09-15',due:'2026-09-16',competence:'2026-09-01',amount:'10000',kind:'income',basis:'actual',status:'posted',description:'Oferta de gratidão',account:'a',accountName:'Banco fictício',category:'c',categoryName:'Doações',subcategoryName:null,centerName:null,party:'=HYPERLINK("https://invalid")',method:'pix',reconciled:false,metadataMissing:false}],digital:[],budgets:[],bankPending:[],balances:[{unit,unitName:'Sede fictícia',account:'a',name:'Banco fictício',opening:'-350',closing:'9650'}],accounting:[],purposes:[],responsibles:[],individualAccess:true,generatedAt:'2026-10-23T18:00:00Z',exportId:'preparacao-ficticia',filters:{from:'2026-09-01',to:'2026-09-30',dateBy:'cash'},units:[unit]};
export const brand={organization:'Ministério fictício',churches:['Sede fictícia']};
test('PDF/XLSX são formatos explícitos, sem parâmetros adicionais',()=>{for(const format of ['pdf','xlsx'])assert.equal(f6Query(new Request(`https://local?units=${unit}&from=2026-09-01&to=2026-09-30&format=${format}`)).format,format)});
test('atalho de relatório usa a mesma seleção no formulário e na primeira consulta',()=>{const source=readFileSync(new URL('../app/FinanceReports.tsx',import.meta.url),'utf8');assert.match(source,/\[filters,setFilters\]=useState<Filters>\(\{\.\.\.initial,report:initialReport\}\)/);assert.match(source,/\[applied,setApplied\]=useState<Filters>\(\{\.\.\.initial,report:initialReport\}\)/)});
test('logo recusa URL remota, SVG e PNG malformado ou superdimensionado',()=>{for(const v of ['https://127.0.0.1/logo','data:image/svg+xml;base64,AAAA',42,'data:image/png;base64,AAAA'])assert.throws(()=>reportLogo(v));const b=Buffer.alloc(24);Buffer.from('89504e470d0a1a0a','hex').copy(b);b.write('IHDR',12);b.writeUInt32BE(2001,16);b.writeUInt32BE(2000,20);assert.throws(()=>reportLogo('data:image/png;base64,'+b.toString('base64')));assert.equal(reportLogo(''),undefined)});
test('Excel preserva identificadores, centavos, datas e fórmulas como texto literal',()=>{assert.equal(exportCell('Número','0001'),'0001');assert.equal(exportCell('Valor','-3,50'),-3.5);assert.equal(exportCell('Valor','10000000000000000,00'),'10000000000000000,00');assert.equal(exportCell('Descrição','=1+1'),'=1+1');assert.ok(exportCell('Competência','2026-09-01') instanceof Date)});
test('PDF formata datas sem modificar referências e descrições semelhantes a datas',()=>{assert.equal(pdfCell('Vencimento','2026-09-15'),'15/09/2026');assert.equal(pdfCell('Data de caixa','2026-09-15'),'15/09/2026');assert.equal(pdfCell('Referência','2026-09-15'),'2026-09-15');assert.equal(pdfCell('Descrição','2026-09-15'),'2026-09-15')});
test('Excel salvo mantém estilos, filtros, painéis, saldos e todos os registros',async()=>{const bytes=await financeXlsx(fixture,'book',brand),wb=new ExcelJS.Workbook();await wb.xlsx.load(bytes);assert.equal(wb.worksheets.length,2);const sheet=wb.worksheets[1];assert.equal(sheet.views[0].state,'frozen');assert.ok(sheet.autoFilter);assert.match(sheet.headerFooter.oddFooter,/Vinha/);const last=sheet.lastRow;assert.equal(last.getCell(1).value,'0001');assert.equal(last.getCell(14).value,100);assert.equal(last.getCell(14).type,ExcelJS.ValueType.Number);const members=new ExcelJS.Workbook();await members.xlsx.load(await financeXlsx(fixture,'members',brand));assert.match(members.worksheets[0].lastRow.getCell(1).value,/^=HYPERLINK/);assert.equal(members.worksheets[0].lastRow.getCell(1).type,ExcelJS.ValueType.String)});
test('todos os relatórios geram PDF e Excel e mantêm restrições individuais',async()=>{for(const[key]of financeReports){const pdf=await PDFDocument.load(await financePdf(fixture,key,brand));assert.ok(pdf.getPageCount()>0,key);assert.ok((await financeXlsx(fixture,key,brand)).length>1000,key)}await assert.rejects(financePdf({...fixture,individualAccess:false},'members',brand));await assert.rejects(financeXlsx({...fixture,individualAccess:false},'members',brand));});
test('PDF repete páginas, conserva logo fornecida e recusa perda silenciosa de caracteres',async()=>{const logo='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSioAAAAASUVORK5CYII=';const d={...fixture,rows:Array.from({length:100},(_,i)=>({...fixture.rows[0],code:String(i+1),description:'Encontro fictício com descrição completa '.repeat(8)}))};assert.ok((await PDFDocument.load(await financePdf(d,'book',{...brand,logo}))).getPageCount()>5);await assert.rejects(financePdf({...fixture,rows:[{...fixture.rows[0],description:'漢字'}]},'book',brand),/caracteres/);});
test('contexto identifica igrejas e base sem expor UUID de filtros',()=>{const text=reportContext({...fixture,filters:{...fixture.filters,account:'a'}},brand).join(' ');assert.match(text,/Banco fictício/);assert.match(text,/Caixa/);assert.ok(!text.includes(unit));});

test('PDF omite registro técnico sem remover identificação interna nem contexto útil',()=>{
 const text=reportContext(fixture,brand,false).join(' ');
 assert.ok(!text.includes('Registro de preparação'));assert.ok(!text.includes(fixture.exportId));
 assert.match(text,/Sede fictícia/);assert.match(text,/Período:/);assert.match(text,/Emitido em:/);
 assert.ok(reportContext(fixture,brand).join(' ').includes(fixture.exportId));assert.equal(fixture.exportId,'preparacao-ficticia');
 const source=readFileSync(new URL('../app/lib/finance-export.ts',import.meta.url),'utf8');assert.match(source,/reportContext\(d,brand,false\)\.slice\(1\)/);
});

test('PDF mantém todas as colunas juntas em paisagem, sem painéis horizontais',async()=>{
 for(const [key]of financeReports){const {headers}=f6Table(fixture,key),layout=financePdfLayout(headers);
  assert.equal(layout.widths.length,headers.length);assert.ok(layout.width>layout.height);assert.ok(layout.fontSize>=11);
  assert.ok(Math.abs(layout.widths.reduce((a,b)=>a+b,0)-(layout.width-60))<.001);
  assert.ok(layout.widths.every(w=>w>=43));
  const pdf=await PDFDocument.load(await financePdf(fixture,key,brand));
  for(const page of pdf.getPages()){assert.equal(page.getWidth(),layout.width);assert.equal(page.getHeight(),layout.height)}
 }
 const pdf=await PDFDocument.load(await financePdf(fixture,'book',brand));assert.equal(pdf.getPageCount(),1);
 const source=readFileSync(new URL('../app/lib/finance-export.ts',import.meta.url),'utf8');
 assert.ok(!source.includes('panelIndex'));assert.ok(!source.includes(' - parte '));
});

test('seleção de colunas é validada, mantém ordem e não muda totais nem dados originais',()=>{
 const original=f6Table(fixture,'book'),subset=selectReportColumns(original,[13,0,6]);
 assert.deepEqual(subset.headers,['Número','Descrição','Valor assinado']);
 assert.deepEqual(subset.rows[0],['0001','Oferta de gratidão','100,00']);assert.equal(original.headers.length,19);
 for(const v of [[],[0,0],[-1],[19],[1.5],[NaN]])assert.throws(()=>selectReportColumns(original,v));
 for(const v of ['',',','0,0','-1','40','1.5','0,','x'])assert.throws(()=>reportColumns(v));
 assert.deepEqual(reportColumns('0,6,13'),[0,6,13]);assert.equal(reportColumns(null),undefined);
 const req=(suffix)=>new Request(`https://local?units=${unit}&from=2026-09-01&to=2026-09-30&format=pdf${suffix}`);
 const query=f6ExportQuery(req('&columns=0,6,13'));assert.deepEqual(query.columns,[0,6,13]);assert.ok(!('columns' in query.data));
 assert.throws(()=>f6ExportQuery(req('&columns=0&columns=1')));
 assert.throws(()=>f6ExportQuery(new Request(req('&columns=0').url.replace('format=pdf','format=json'))));
});

test('menos colunas ampliam a fonte e a seleção vale para PDF e Excel',async()=>{
 assert.equal(financePdfLayout(['Número','Descrição','Valor assinado']).fontSize,13);
 assert.equal(financePdfLayout(Array(9).fill('Conta')).fontSize,12);
 assert.equal(financePdfLayout(f6Table(fixture,'book').headers).fontSize,11);
 const columns=[0,6,13],pdf=await PDFDocument.load(await financePdf(fixture,'book',brand,columns));
 assert.equal(pdf.getPageCount(),1);assert.equal(pdf.getPage(0).getWidth(),842);
 const wb=new ExcelJS.Workbook();await wb.xlsx.load(await financeXlsx(fixture,'book',brand,columns));
 assert.equal(wb.worksheets[1].columnCount,3);assert.deepEqual(wb.worksheets[1].lastRow.values.slice(1),['0001','Oferta de gratidão',100]);
 await assert.rejects(financePdf(fixture,'book',brand,[]));await assert.rejects(financeXlsx(fixture,'book',brand,[50]));
});

test('tela oferece seleção acessível, preserva uma coluna e atualiza a tabela',()=>{
 const require=createRequire(import.meta.url),source=ts.transpileModule(readFileSync(new URL('../app/FinanceReports.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
 const mount=(selection)=>{
  let index=0;const changes=[];
  const fakeRequire=(name)=>name==='react'?{useEffect:()=>{},useState:(initial)=>{const slot=index++;return [slot===2?fixture:slot===13?selection:initial,(value)=>changes.push({slot,value:typeof value==='function'?value(selection):value})]}}:name==='./FinancePagination'?{default:()=>null}:name==='./FinanceModule'?{Dialog:()=>null,PartyPicker:()=>null}:name==='./lib/finance-f6'?{financeReports,f6Table,selectReportColumns}:name==='./lib/finance-f1'?{financeMoney:(v)=>String(v),financeMoneyField:(v)=>v,financeDay:(v)=>String(v)}:name.endsWith('.css')?{}:require(name);
  const module={exports:{}};new Function('require','module','exports',source)(fakeRequire,module,module.exports);
  const tree=module.exports.default({units:[unit],from:'2026-09-01',to:'2026-09-30',catalog:[],canManage:true});
  const nodes=[];const walk=(node)=>{if(Array.isArray(node))return node.forEach(walk);if(node&&typeof node==='object'&&node.props){nodes.push(node);walk(node.props.children)}};walk(tree);
  return {tree,nodes,changes};
 };
 const full=mount({}),checks=full.nodes.filter(n=>n.type==='input'&&n.props.type==='checkbox');assert.equal(checks.length,19);assert.ok(checks.every(n=>n.props.checked));
 const picker=full.nodes.find(n=>n.type==='details'&&n.props.className.includes('f6-column-settings'));assert.equal(picker.props.open,undefined);
 const css=readFileSync(new URL('../app/finance-reports.css',import.meta.url),'utf8');
 assert.match(css,/\.f6-workspace \.f6-result \.f6-column-settings\{[^}]*width:100%;[^}]*max-width:none/);
 assert.match(css,/input\[type=checkbox\]\{[^}]*min-height:18px/);
 checks[6].props.onChange({target:{checked:false}});assert.ok(!full.changes[0].value.book.includes(6));
 const one=mount({book:[6]}),only=one.nodes.filter(n=>n.type==='input'&&n.props.type==='checkbox'&&n.props.checked);assert.equal(only.length,1);assert.equal(only[0].props.disabled,true);
 const html=renderToStaticMarkup(one.tree);assert.match(html,/Colunas do relatório/);assert.match(html,/Oferta de gratidão/);assert.ok(!html.includes('<th>Metadados</th>'));
 const restore=one.nodes.find(n=>n.type==='button'&&n.props.children==='Selecionar todas');restore.props.onClick();assert.equal(one.changes[0].value.book.length,19);
});
