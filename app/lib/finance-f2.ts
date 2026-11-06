import {financeCents,financeCommand,financeDate,financeMoneyInput} from './finance-f1.ts';
import {uuidPattern} from './private-files.ts';
const uuid=(v:unknown)=>{if(typeof v!=='string'||!uuidPattern.test(v))throw Error('Identificador inválido.');return v.toLowerCase()};
const txt=(v:unknown,max=300)=>{if(typeof v!=='string'||v.trim().length<2||v.length>max)throw Error('Informe a justificativa.');return v.trim()};
const version=(v:unknown)=>{if(!Number.isSafeInteger(v)||Number(v)<1)throw Error('Atualize o registro antes de continuar.');return Number(v)};
const cents=(v:unknown)=>{const canonical=financeMoneyInput(v);return canonical!==null&&/^0+(?:,0{1,2})?$/.test(canonical)?'0':financeCents(v)};
function keys(d:Record<string,unknown>,allowed:string[]){if(Object.keys(d).some(k=>!allowed.includes(k)))throw Error('Campo não permitido.')}
export function financeF2Command(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Dados inválidos.');const r=value as Record<string,unknown>;keys(r,['action','unitId','data']);
 if(!r.data||typeof r.data!=='object'||Array.isArray(r.data))throw Error('Dados inválidos.');const d=r.data as Record<string,unknown>,unitId=uuid(r.unitId),id=uuid(d.id);
 if(r.action==='settle'){
  keys(d,['id','title','version','principal','interest','fine','discount','fee','feeCategory','account','date','method','reason']);
  const principal=financeCents(d.principal),interest=cents(d.interest),fine=cents(d.fine),discount=cents(d.discount),fee=cents(d.fee),gross=BigInt(principal)+BigInt(interest)+BigInt(fine)-BigInt(discount);
  if(BigInt(discount)>BigInt(principal)||gross<=BigInt(0)||gross>BigInt('999999999999')||BigInt(fee)>BigInt('999999999999')||!['cash','pix','card','boleto','bank','other'].includes(String(d.method)))throw Error('Revise os valores e a forma da baixa.');
  return {action:'settle',unitId,data:{id,title:uuid(d.title),version:version(d.version),principal,interest,fine,discount,fee,feeCategory:BigInt(fee)>BigInt(0)?uuid(d.feeCategory):'',account:uuid(d.account),date:financeDate(d.date),method:String(d.method),reason:txt(d.reason)}};
 }
 if(r.action==='reverse'){
  keys(d,['id','settlement','date','reason']);return{action:'reverse',unitId,data:{id,settlement:uuid(d.settlement),date:financeDate(d.date),reason:txt(d.reason)}};
 }
 if(r.action==='reschedule'){
  keys(d,['id','title','version','due','reason']);return{action:'reschedule',unitId,data:{id,title:uuid(d.title),version:version(d.version),due:financeDate(d.due),reason:txt(d.reason)}};
 }
 if(r.action==='series'){
  keys(d,['id','mode','count','frequency','entry']);const count=Number(d.count);
  if(!Number.isInteger(count)||count<2||count>60||!['installments','recurring'].includes(String(d.mode))||!['monthly','weekly'].includes(String(d.frequency)))throw Error('Escolha de 2 a 60 ocorrências.');
  const entry=financeCommand({action:'entry',unitId,data:d.entry});if(entry.action!=='entry'||!['income','expense'].includes(entry.data.kind)||entry.data.paid)throw Error('A série deve conter somente previsões de entrada ou saída.');
  if(d.mode==='installments'&&BigInt(entry.data.amountCents)<BigInt(count))throw Error('O total precisa comportar ao menos um centavo por parcela.');
  return{action:'series',unitId,data:{id,mode:String(d.mode),count,frequency:String(d.frequency),entry:entry.data}};
 }
 throw Error('Ação inválida.');
}
export function financeF2Query(request:Request){const p=new URL(request.url).searchParams;for(const k of p.keys())if(p.getAll(k).length!==1||!['unit','title','tenant','action','before'].includes(k))throw Error('Filtro inválido.');const action=p.get('action')||'history',before=p.get('before')||'';if(!['history','activity'].includes(action)||before&&!/^[1-9][0-9]{0,18}$/.test(before))throw Error('Filtro inválido.');return{unit:uuid(p.get('unit')),title:uuid(p.get('title')),action,before}}
export function financeSchedule(amount:bigint,count:number,mode:string,start:string,frequency:string){
 financeDate(start);if(!Number.isInteger(count)||count<2||count>60||!['installments','recurring'].includes(mode)||!['monthly','weekly'].includes(frequency)||amount<BigInt(1)||amount>BigInt('999999999999')||mode==='installments'&&amount<BigInt(count))throw Error('Série inválida.');
 const base=new Date(start+'T12:00:00Z');return Array.from({length:count},(_,i)=>{let date:Date;if(frequency==='weekly'){date=new Date(base);date.setUTCDate(base.getUTCDate()+7*i)}else{date=new Date(Date.UTC(base.getUTCFullYear(),base.getUTCMonth()+i+1,0,12));date.setUTCDate(Math.min(base.getUTCDate(),date.getUTCDate()))}return{due:date.toISOString().slice(0,10),cents:(mode==='recurring'?amount:amount/BigInt(count)+(BigInt(i)<amount%BigInt(count)?BigInt(1):BigInt(0))).toString()}});
}
