import {uuidPattern} from './private-files.ts';
export function issueProrationCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Pedido inválido.');
 const input=value as Record<string,unknown>;
 for(const field of ['requestId','contractId'])if(typeof input[field]!=='string'||!uuidPattern.test(input[field]))throw Error('Identificador inválido.');
 if(typeof input.referenceMonth!=='string'||!/^\d{4}-(0[1-9]|1[0-2])$/.test(input.referenceMonth))throw Error('Competência inválida.');
 const command={requestId:String(input.requestId),contractId:String(input.contractId),referenceMonth:input.referenceMonth};
 if(input.replacesInvoiceId===undefined)return command;
 if(typeof input.replacesInvoiceId!=='string'||!uuidPattern.test(input.replacesInvoiceId))throw Error('Fatura substituída inválida.');
 return{...command,replacesInvoiceId:input.replacesInvoiceId};
}
