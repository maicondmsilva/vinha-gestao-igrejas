import {ledgerCommand} from './ledger-pilot.ts';
import {uuidPattern} from './private-files.ts';
type Store=Pick<Storage,'getItem'|'setItem'|'removeItem'>;
function key(scope:string){const parts=scope.split(':');if(parts.length!==2||parts.some(part=>!uuidPattern.test(part)))throw Error('Conta de recuperação não validada.');return 'vinha:ledger-pending:v1:'+scope}
function validate(value:unknown,units:string[]){
 const parsed=ledgerCommand(value);
 if(!['post','reverse'].includes(parsed.action)||!units.includes(parsed.unitId))throw Error('Pedido pendente exige revisão de acesso à unidade.');
 const raw=value as Record<string,unknown>;
 const fields=parsed.action==='post'?['action','unitId','requestId','date','memo','debit','credit','amount']:['action','unitId','requestId','date','memo','originalId'];
 return Object.fromEntries(fields.map(field=>[field,raw[field]]));
}
export function restoreLedgerPending(store:Store,scope:string,units:string[]){
 const raw=store.getItem(key(scope));if(raw===null)return null;
 if(raw.length>4096)throw Error('Registro de recuperação inválido. Não crie outro lançamento; procure o suporte.');
 return validate(JSON.parse(raw),units);
}
export function saveLedgerPending(store:Store,scope:string,units:string[],command:Record<string,unknown>){
 const value=validate(command,units),serialized=JSON.stringify(value),storageKey=key(scope);
 const existing=restoreLedgerPending(store,scope,units);
 if(existing&&JSON.stringify(existing)!==serialized)throw Error('Existe outro pedido pendente. Recupere o mesmo pedido antes de continuar.');
 store.setItem(storageKey,serialized);
 if(store.getItem(storageKey)!==serialized)throw Error('Não foi possível proteger o pedido antes do envio.');
 return value;
}
export function clearLedgerPending(store:Store,scope:string){store.removeItem(key(scope));if(store.getItem(key(scope))!==null)throw Error('Resultado confirmado, mas a recuperação local não pôde ser removida. Consulte o histórico.');}
