import {PDFDocument,StandardFonts,rgb,type PDFFont,type PDFPage} from 'pdf-lib';
import {f6Table,financeReports,type F6Data,type ReportKey} from './finance-f6.ts';

export type ExportBrand={organization:string;churches:string[];logo?:string};
const moneyHeaders=new Set(['Entradas','Saídas','Resultado','Entradas realizadas','Saídas realizadas','A receber em aberto','A pagar em aberto','Bruto','Taxas efetivas','Líquido informado','Devolvido','Orçado','Realizado','Realizado − orçado','Valor','Débito','Crédito','Valor assinado','Saldo anterior','Saldo final']);
const day=(s:string)=>/^\d{4}-\d{2}-\d{2}$/.test(s)?s.split('-').reverse().join('/'):s;
export const pdfCell=(header:string,value:string)=>/^(Data|Competência$|Vencimento$)/.test(header)?day(value):value;
const clean=(s:unknown)=>String(s??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'');
export function reportLogo(value:unknown){
 if(value==null||value==='')return undefined;
 if(typeof value!=='string'||value.length>400000||!/^data:image\/png;base64,[A-Za-z0-9+/]+=*$/.test(value))throw Error('Use uma logo PNG de até 250 KB.');
 const bytes=Buffer.from(value.split(',')[1],'base64');
 if(bytes.length>256000||bytes.length<24||bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||bytes.subarray(12,16).toString()!=='IHDR')throw Error('Logo PNG inválida.');
 const w=bytes.readUInt32BE(16),h=bytes.readUInt32BE(20);
 if(!w||!h||w>2000||h>2000||w*h>2000000)throw Error('A logo deve ter até 2 milhões de pixels e 2.000 pixels por lado.');
 return bytes;
}
export function exportCell(header:string,value:string):string|number|Date{
 if(moneyHeaders.has(header)&&/^-?\d+,\d{2}$/.test(value)){
  const cents=BigInt(value.replace(',',''));
  // Excel stores only 15 significant digits. Keep larger exact values as text.
  if(cents<=BigInt('999999999999999')&&cents>=BigInt('-999999999999999'))return Number(cents)/100;
 }
 if(header==='Movimentos'&&/^\d+$/.test(value)&&Number.isSafeInteger(Number(value)))return Number(value);
 if(/^(Data|Competência$|Vencimento$)/.test(header)&&/^\d{4}-\d{2}-\d{2}$/.test(value))return new Date(value+'T12:00:00Z');
 return clean(value);
}
function sections(d:F6Data,key:ReportKey){const table=f6Table(d,key);return[
 ...(d.balances?.length&&['book','account','accountability'].includes(key)?[{title:'Saldos por conta (caixa, sem filtros de classificação)',headers:['Igreja','Conta','Saldo anterior','Saldo final'],rows:d.balances.map(b=>[b.unitName,b.name,decimal(b.opening),decimal(b.closing)])}]:[]),
 {title:financeReports.find(([id])=>id===key)![1],...table}
 ];}
function decimal(s:string){const n=BigInt(s),v=(n<BigInt(0)?-n:n).toString().padStart(3,'0');return(n<BigInt(0)?'-':'')+v.slice(0,-2)+','+v.slice(-2)}
export function reportContext(d:F6Data,brand:ExportBrand){
 const labels:Record<string,string>={dateBy:'Base de data',account:'Conta',category:'Categoria',subcategory:'Subcategoria',center:'Centro de custo',person:'Membro',supplier:'Fornecedor',purpose:'Finalidade',responsible:'Responsável',provider:'Provedor',method:'Forma',origin:'Origem',status:'Situação',reference:'Referência',min:'Valor mínimo (centavos)',max:'Valor máximo (centavos)'};
 const descriptions:Record<string,string>={cash:'Caixa / liquidação',competence:'Competência',due:'Vencimento',income:'Recebimento',expense:'Pagamento',posted:'Realizado',pending:'Pendente',mercado_pago:'Mercado Pago',asaas:'Asaas',safe2pay:'Safe2Pay',pix:'Pix',card:'Cartão',boleto:'Boleto'};
 const resolve=(key:string,value:string)=>{
  const field:Record<string,[string,string]>={account:['account','accountName'],category:['category','categoryName'],subcategory:['category','subcategoryName'],center:['center','centerName'],person:['person','party'],supplier:['supplier','supplierName']};
  if(field[key]){const [id,name]=field[key];return String(d.rows.find(r=>(r as unknown as Record<string,unknown>)[id]===value)?.[name as keyof typeof d.rows[number]]||'Cadastro selecionado')}
  if(key==='purpose')return d.purposes.find(p=>p.id===value)?.name||'Finalidade selecionada';
  if(key==='responsible')return d.responsibles.find(p=>p.id===value)?.name||'Responsável selecionado';
  return descriptions[value]||value;
 };
 return [brand.organization,...brand.churches.map(n=>'Igreja: '+n),`Período: ${day(d.filters.from)} a ${day(d.filters.to)}`,
  ...Object.entries(d.filters).filter(([k,v])=>v&&labels[k]).map(([k,v])=>labels[k]+': '+resolve(k,v)),
  'Emitido em: '+new Date(d.generatedAt).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})+' (Brasília)',
  'Registro de preparação: '+(d.exportId||'não informado')];
}
export async function financeXlsx(d:F6Data,key:ReportKey,brand:ExportBrand){
 const {default:ExcelJS}=await import('exceljs');
 const wb=new ExcelJS.Workbook();wb.creator='Vinha';wb.created=new Date(d.generatedAt);wb.title=financeReports.find(([id])=>id===key)![1];
 for(const [i,section]of sections(d,key).entries()){
  const ws=wb.addWorksheet(i===0&&sections(d,key).length>1?'Saldos':'Relatório',{properties:{defaultRowHeight:22},pageSetup:{paperSize:9,orientation:'landscape',fitToPage:true,fitToWidth:1,fitToHeight:0},headerFooter:{oddFooter:'Vinha | Página &P de &N'}});
  ws.columns=section.headers.map(h=>({width:moneyHeaders.has(h)?22:h.includes('Descrição')||h==='Histórico'?44:27}));
  const title=ws.addRow([section.title]);title.height=34;title.font={name:'Calibri',size:18,bold:true,color:{argb:'FF214F3C'}};ws.mergeCells(1,1,1,section.headers.length);
  for(const text of reportContext(d,brand)){const r=ws.addRow([text]);ws.mergeCells(r.number,1,r.number,section.headers.length);r.alignment={wrapText:true,vertical:'middle'};r.height=30;r.font={name:'Calibri',size:11,color:{argb:'FF52695B'}}}
  const notice=ws.addRow([f6Table(d,key).notice]);ws.mergeCells(notice.number,1,notice.number,section.headers.length);notice.alignment={wrapText:true};notice.height=48;
  const header=ws.addRow(section.headers);header.height=32;header.font={bold:true,color:{argb:'FFFFFFFF'},size:11};header.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF285C45'}};header.alignment={wrapText:true,vertical:'middle'};
  for(const values of section.rows){const row=ws.addRow(values.map((v,j)=>exportCell(section.headers[j],v)));row.font={name:'Calibri',size:11};row.alignment={vertical:'top',wrapText:true};row.height=Math.max(24,...values.map((v,j)=>Math.ceil(v.length/(ws.getColumn(j+1).width||25))*15));row.eachCell((cell,j)=>{if(moneyHeaders.has(section.headers[j-1])&&typeof cell.value==='number'){cell.numFmt='"R$" #,##0.00;[Red]("R$" #,##0.00)';cell.alignment={horizontal:'right',vertical:'top'}}else if(cell.value instanceof Date)cell.numFmt='dd/mm/yyyy';if(row.number%2===0)cell.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FFF0F5F1'}}});}
  ws.autoFilter={from:{row:header.number,column:1},to:{row:Math.max(header.number,ws.rowCount),column:section.headers.length}};ws.views=[{state:'frozen',ySplit:header.number}];ws.pageSetup.printTitlesRow=`${header.number}:${header.number}`;
 }
 return new Uint8Array(await wb.xlsx.writeBuffer());
}
// Keep every column together. Wider ledgers use larger landscape paper rather
// than horizontal panels or an unreadably small font.
export function financePdfLayout(headers:string[]){
 const widths=headers.map(h=>h==='Número'||h==='Movimentos'?43:/^(Data|Competência$|Vencimento$)/.test(h)?62:moneyHeaders.has(h)?76:/Descrição|Histórico/.test(h)?135:/Igreja|Conta|Contribuinte|Referência|Metadados/.test(h)?96:70);
 const required=widths.reduce((a,b)=>a+b,0)+60;
 const [width,height]=[[842,595],[1191,842],[1684,1191],[2384,1684]].find(([w])=>w>=required)||[Math.ceil(required),1684];
 return {width,height,widths:widths.map(w=>w*(width-60)/(required-60))};
}
export async function financePdf(d:F6Data,key:ReportKey,brand:ExportBrand){
 const doc=await PDFDocument.create(),font=await doc.embedFont(StandardFonts.Helvetica),bold=await doc.embedFont(StandardFonts.HelveticaBold);
 const rawLogo=reportLogo(brand.logo),logo=rawLogo?await doc.embedPng(rawLogo):null;
 const reportSections=sections(d,key),layout=financePdfLayout(f6Table(d,key).headers);
 const ink=rgb(.12,.28,.21),muted=rgb(.35,.43,.38),paper=rgb(.94,.97,.95),{width,height}=layout,margin=30,usable=width-margin*2;
 // WinAnsi includes Portuguese. Explicitly refuse unsupported scripts, never erase names silently.
 const safe=(s:string)=>{const text=clean(s).replace(/[\u2010-\u2015]/g,'-').replaceAll('×','x').replaceAll('−','-');try{font.encodeText(text)}catch{throw Error('Este PDF contém caracteres não suportados. Exporte em Excel para preservar o texto integral.')}return text};
 const wrap=(text:string,max:number,f:PDFFont=font,size=9)=>{const lines:string[]=[];let line='';for(const char of safe(text)){if(char==='\n'){lines.push(line);line='';continue}if(f.widthOfTextAtSize(line+char,size)>max){const space=line.lastIndexOf(' ');if(space>0){lines.push(line.slice(0,space));line=line.slice(space+1)+char}else{lines.push(line);line=char}}else line+=char}lines.push(line);return lines};
 let page!:PDFPage,y=0;
 const write=(text:string,x:number,at:number,f=font,size=9,color=ink)=>page.drawText(safe(text),{x,y:at,font:f,size,color});
 const newPage=()=>{if(doc.getPageCount()>=2000)throw Error('PDF muito extenso. Reduza o período ou exporte em Excel.');page=doc.addPage([width,height]);y=height-margin;if(logo){const scaled=logo.scale(Math.min(92/logo.width,42/logo.height));page.drawImage(logo,{x:margin,y:y-scaled.height,width:scaled.width,height:scaled.height})}else{page.drawRectangle({x:margin,y:y-38,width:34,height:34,color:ink});write('V',margin+9,y-29,bold,21,rgb(1,1,1));write('Vinha',margin+42,y-17,bold,15);write('Gestão que frutifica',margin+42,y-31,font,7)}const x=margin+145;const nameLines=wrap(brand.organization,usable-145,bold,14);for(const line of nameLines){write(line,x,y-14,bold,14);y-=17}y-=35;};
 newPage();
 const block=(text:string,size=9,f=font)=>{for(const line of wrap(text,usable,f,size)){if(y<55)newPage();write(line,margin,y,f,size);y-=size+5}y-=4};
 block(financeReports.find(([id])=>id===key)![1],16,bold);
 for(const text of reportContext(d,brand).slice(1))block(text);
 block(f6Table(d,key).notice,8);
 for(const section of reportSections){
   if(y<130)newPage();block(section.title,11,bold);
   const preferred=financePdfLayout(section.headers).widths,total=preferred.reduce((a,b)=>a+b,0),widths=preferred.map(w=>w*usable/total),xs=widths.map((_,j)=>margin+widths.slice(0,j).reduce((a,b)=>a+b,0));
   const heading=()=>{const lines=section.headers.map((h,j)=>wrap(h,widths[j]-12,bold)),h=Math.max(...lines.map(l=>l.length))*12+14;if(y-h<80)newPage();page.drawRectangle({x:margin,y:y-h,width:usable,height:h,color:paper});lines.forEach((ls,j)=>ls.forEach((s,k)=>write(s,xs[j]+6,y-14-k*12,bold)));y-=h;};
   heading();
   if(!section.rows.length)block('Nenhum registro corresponde aos filtros.');
   for(const row of section.rows){const lines=section.headers.map((h,j)=>wrap(pdfCell(h,row[j]),widths[j]-12));let offset=0;const max=Math.max(...lines.map(l=>l.length));
    // Move ordinary rows intact; only a cell taller than a full page continues.
    if(y-(max*12+10)<52){newPage();heading()}
    while(offset<max){if(y<76){newPage();heading()}const count=Math.min(max-offset,Math.max(1,Math.floor((y-62)/12)));lines.forEach((ls,j)=>ls.slice(offset,offset+count).forEach((s,k)=>{const x=moneyHeaders.has(section.headers[j])?xs[j]+widths[j]-6-font.widthOfTextAtSize(s,9):xs[j]+6;write(s,x,y-13-k*12)}));y-=count*12+10;page.drawLine({start:{x:margin,y},end:{x:width-margin,y},thickness:.4,color:rgb(.85,.89,.86)});offset+=count;}}
   y-=18;
 }
 doc.getPages().forEach((p,i)=>{p.drawLine({start:{x:margin,y:35},end:{x:width-margin,y:35},thickness:.6,color:rgb(.76,.81,.77)});p.drawText('Vinha - Gestão que frutifica',{x:margin,y:20,font:bold,size:8,color:ink});p.drawText(`Página ${i+1} de ${doc.getPageCount()}`,{x:width-margin-85,y:20,font,size:8,color:muted})});doc.setTitle(financeReports.find(([id])=>id===key)![1]);doc.setAuthor(brand.organization);
 return doc.save();
}
