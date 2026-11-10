import {uuidPattern} from './private-files.ts';
export function payerChangeCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Pedido inválido.');
 const input=value as Record<string,unknown>;
 for(const field of ['requestId','contractId','payerUnitId'])if(typeof input[field]!=='string'||!uuidPattern.test(input[field]))throw Error('Identificador inválido.');
 if(typeof input.expectedUpdatedAt!=='string'||input.expectedUpdatedAt.length>50||!Number.isFinite(Date.parse(input.expectedUpdatedAt)))throw Error('Versão inválida.');
 if(typeof input.reason!=='string'||input.reason.trim().length<5||input.reason.trim().length>300)throw Error('Justificativa inválida.');
 return{requestId:String(input.requestId),contractId:String(input.contractId),payerUnitId:String(input.payerUnitId),expectedUpdatedAt:input.expectedUpdatedAt,reason:input.reason.trim()};
}
