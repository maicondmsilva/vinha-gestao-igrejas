import {uuidPattern} from './private-files.ts';
export function cancellationCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Pedido inválido.');
 const input=value as Record<string,unknown>;
 for(const field of ['requestId','contractId','invoiceId'])if(typeof input[field]!=='string'||!uuidPattern.test(input[field]))throw Error('Identificador inválido.');
 if(typeof input.reason!=='string'||input.reason.trim().length<5||input.reason.trim().length>300)throw Error('Informe a justificativa.');
 return{requestId:String(input.requestId),contractId:String(input.contractId),invoiceId:String(input.invoiceId),reason:input.reason.trim()};
}
