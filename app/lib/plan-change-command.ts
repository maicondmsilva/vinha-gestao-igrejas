import {uuidPattern} from './private-files.ts';
import {readProrationCatalog} from './proration-catalog.ts';
export function planConfirmationCommand(value:unknown){
 const command=planChangeCommand(value),input=value as Record<string,unknown>;
 const expectedCatalog=readProrationCatalog(input.expectedCatalog,String(command.nextPlanId));
 return {...command,requestId:String(command.requestId),contractId:String(command.contractId),expectedCatalog};
}
export function planChangeCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Dados inválidos.');
 const d=value as Record<string,unknown>;
 for(const field of ['requestId','contractId','baseInvoiceId'])if(typeof d[field]!=='string'||!uuidPattern.test(d[field]))throw Error('Identificador inválido.');
 if(typeof d.nextPlanId!=='string'||! /^[a-zA-Z0-9_-]{1,100}$/.test(d.nextPlanId))throw Error('Plano inválido.');
 if(typeof d.expectedUpdatedAt!=='string'||d.expectedUpdatedAt.length>50||!Number.isFinite(Date.parse(d.expectedUpdatedAt)))throw Error('Versão inválida.');
 if(!Number.isSafeInteger(d.cycleStart)||!Number.isSafeInteger(d.cycleEnd)||Number(d.cycleStart)<0||Number(d.cycleEnd)-Number(d.cycleStart)<86400000||Number(d.cycleEnd)-Number(d.cycleStart)>3024000000)throw Error('Ciclo inválido.');
 return Object.fromEntries(['requestId','contractId','baseInvoiceId','nextPlanId','expectedUpdatedAt','cycleStart','cycleEnd'].map(field=>[field,d[field]]));
}
export function rolloverCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Dados inválidos.');
 const d=value as Record<string,unknown>;
 for(const field of ['requestId','contractId','invoiceId'])if(typeof d[field]!=='string'||!uuidPattern.test(d[field]))throw Error('Identificador inválido.');
 if(typeof d.expectedUpdatedAt!=='string'||d.expectedUpdatedAt.length>50||!Number.isFinite(Date.parse(d.expectedUpdatedAt)))throw Error('Versão inválida.');
 return Object.fromEntries(['requestId','contractId','invoiceId','expectedUpdatedAt'].map(field=>[field,d[field]]));
}
