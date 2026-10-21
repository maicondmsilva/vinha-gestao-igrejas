import {financeDate} from './finance-f1.ts';
import {uuidPattern} from './private-files.ts';
function id(v:unknown){if(typeof v!=='string'||!uuidPattern.test(v))throw Error('Selecione um registro válido.');return v.toLowerCase()}
function reason(v:unknown,min=10){if(typeof v!=='string'||v.trim().length<min||v.length>300)throw Error('Informe uma justificativa detalhada.');return v.trim()}
function exact(o:Record<string,unknown>,keys:string[]){if(Object.keys(o).some(k=>!keys.includes(k)))throw Error('Campo não permitido.')}
function ids(v:unknown){if(!Array.isArray(v)||v.length<1||v.length>100)throw Error('Selecione entre 1 e 100 movimentos.');const result=v.map(id);if(new Set(result).size!==result.length)throw Error('Registro repetido.');return result}
export function financeF5Command(raw:unknown){
 if(!raw||typeof raw!=='object'||Array.isArray(raw))throw Error('Pedido inválido.');const c=raw as Record<string,unknown>;exact(c,['unitId','action','data']);const unitId=id(c.unitId);if(!c.data||typeof c.data!=='object'||Array.isArray(c.data))throw Error('Dados inválidos.');const d=c.data as Record<string,unknown>,requestId=id(d.id);
 if(c.action==='import'){exact(d,['id','account','filename','ofx','confirmed']);if(d.confirmed!==true||typeof d.ofx!=='string'||typeof d.filename!=='string'||!/^[^\\/\x00-\x1f]{1,155}\.ofx$/i.test(d.filename))throw Error('Confirme a conta e selecione um arquivo OFX.');return{unitId,action:'import' as const,data:{id:requestId,account:id(d.account),filename:d.filename},ofx:d.ofx}}
 if(c.action==='match'){exact(d,['id','account','bank','book','reason']);return{unitId,action:'match' as const,data:{id:requestId,account:id(d.account),bank:ids(d.bank),book:ids(d.book),reason:reason(d.reason,2)}}}
 if(c.action==='undo'){exact(d,['id','group','reason']);return{unitId,action:'undo' as const,data:{id:requestId,group:id(d.group),reason:reason(d.reason)}}}
 if(c.action==='ignore'){exact(d,['id','transaction','version','ignored','reason']);if(!Number.isSafeInteger(d.version)||Number(d.version)<1||typeof d.ignored!=='boolean')throw Error('Atualize o movimento.');return{unitId,action:'ignore' as const,data:{id:requestId,transaction:id(d.transaction),version:d.version,ignored:d.ignored,reason:reason(d.reason)}}}
 if(c.action==='close'||c.action==='reopen'){exact(d,['id','through','expectedClosed','reason','allowPending']);if(typeof d.allowPending!=='boolean'||typeof d.expectedClosed!=='string')throw Error('Atualize o fechamento.');return{unitId,action:c.action,data:{id:requestId,through:financeDate(d.through),expectedClosed:d.expectedClosed?financeDate(d.expectedClosed):'',reason:reason(d.reason),allowPending:d.allowPending}}}
 throw Error('Operação inválida.');
}
export type ReconciliationBook={id:string;date:string;amount:string;memo:string;matched:boolean;internal?:boolean;code?:string;provider?:string;provider_reference?:string;receipt_id?:string;kind?:string;provider_net?:string};
export type ReconciliationBank={id:string;date:string;amount:string;memo:string;reference:string;matched:boolean;ignored:boolean;ignore_reason?:string;version:number;possible_duplicate:boolean};
export function reconciliationSuggestions(bank:ReconciliationBank,books:ReconciliationBook[]){
 const candidates=books.filter(b=>!b.matched&&!b.internal&&Math.abs(Date.parse(b.date)-Date.parse(bank.date))<=3*86400000),result:{ids:string[];label:string}[]=[];
 for(const b of candidates)if(b.amount===bank.amount)result.push({ids:[b.id],label:b.provider_reference&&bank.reference&&b.provider_reference===bank.reference?'Valor, data e referência':'Valor e proximidade da data — revisar'});
 const receiptGroups=new Map<string,ReconciliationBook[]>();for(const b of candidates)if(b.receipt_id){const group=receiptGroups.get(b.receipt_id)||[];group.push(b);receiptGroups.set(b.receipt_id,group)}
 for(const group of receiptGroups.values())if(group.length>1&&group.reduce((n,b)=>n+BigInt(b.amount),BigInt(0))===BigInt(bank.amount))result.push({ids:group.map(b=>b.id),label:'Recebimento do provedor e taxas vinculadas — revisar o líquido'});
 return result.slice(0,10);
}
