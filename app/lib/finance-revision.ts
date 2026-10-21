import {financeCommand} from './finance-f1.ts';
import {uuidPattern} from './private-files.ts';
export function financeRevision(input:unknown){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Dados inválidos.');
 const c=input as Record<string,unknown>,d=c.data as Record<string,unknown>;
 if(c.action!=='edit_entry'||Object.keys(c).some(k=>!['action','unitId','data'].includes(k))||!d||typeof d!=='object'||Array.isArray(d)||Object.keys(d).some(k=>!['id','title','version','amount','description','account','category','center','competence','due','method','notes','kind','destination','person','supplier','party','paid','reason'].includes(k)))throw Error('Revisão inválida.');
 if(typeof d.title!=='string'||!uuidPattern.test(d.title)||!Number.isSafeInteger(d.version)||Number(d.version)<1)throw Error('Atualize o lançamento.');
 if(d.kind!==undefined){
  if(typeof d.reason!=='string'||d.reason.trim().length<2||d.reason.length>300||typeof d.paid!=='string')throw Error('Informe o motivo e a situação.');
  const normalized=financeCommand({action:'entry',unitId:c.unitId,data:{id:d.id,kind:d.kind,amount:d.amount,description:d.description,account:d.account,category:d.category,center:d.center||'',competence:d.competence,due:d.due,method:d.method,notes:d.notes||'',destination:d.destination||'',supplier:d.supplier||'',person:d.person||'',party:d.party||'',paid:d.paid}});
  return {unitId:normalized.unitId,data:{...normalized.data,title:d.title.toLowerCase(),version:d.version,reason:d.reason.trim()}};
 }
 if(['destination','person','supplier','party','paid','reason'].some(k=>k in d))throw Error('Revisão incompleta.');
 const normalized=financeCommand({action:'entry',unitId:c.unitId,data:{id:d.id,kind:'income',amount:d.amount,description:d.description,account:d.account,category:d.category,center:d.center||'',competence:d.competence,due:d.due,method:d.method,notes:d.notes||'',destination:'',supplier:'',person:'',party:'',paid:''}});
 const {kind:_,destination:__,supplier:___,person:____,party:_____,paid:______,...data}=normalized.data;
 return {unitId:normalized.unitId,data:{...data,title:d.title.toLowerCase(),version:d.version}};
}
