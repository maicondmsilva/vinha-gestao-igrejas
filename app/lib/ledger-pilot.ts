import {assertDeploymentIsolation} from './deployment-safety.ts';
import {uuidPattern} from './private-files.ts';
export function ledgerPilotEnabled(env:Record<string,string|undefined>){
 if(env.VINHA_LEDGER_PILOT!=='true'||env.VERCEL_ENV==='production')return false;
 if(!env.VERCEL_ENV&&['development','test'].includes(env.NODE_ENV||'')&&env.NEXT_PUBLIC_VINHA_ENV==='local'&&env.NEXT_PUBLIC_SUPABASE_URL==='http://127.0.0.1:54321')return true;
 if(env.NEXT_PUBLIC_VINHA_ENV!=='test')return false;
 try{assertDeploymentIsolation(env);return true}catch{return false}
}
export function moneyCents(value:string){
 const clean=value.trim();if(!/^(?:0|[1-9][0-9]{0,10})(?:,[0-9]{1,2})?$/.test(clean))throw Error('Use um valor positivo, sem separador de milhar: 1234,56.');
 const [whole,decimal='']=clean.split(',');const amount=Number(whole)*100+Number(decimal.padEnd(2,'0'));
 if(!Number.isSafeInteger(amount)||amount<=0)throw Error('Valor inválido.');return amount;
}
export function ledgerCurrency(value:string){
 if(!/^-?\d+$/.test(value))return 'Valor indisponível';
 const negative=value.startsWith('-'),digits=value.replace(/^-/,'').replace(/^0+(?=\d)/,'').padStart(3,'0');
 return`${negative?'-':''}R$ ${digits.slice(0,-2).replace(/\B(?=(\d{3})+(?!\d))/g,'.')},${digits.slice(-2)}`;
}
export function ledgerCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Dados inválidos.');
 const input=value as Record<string,unknown>;
 if(typeof input.unitId!=='string'||!uuidPattern.test(input.unitId))throw Error('Selecione uma unidade.');
 const action=input.action;
 if(action==='account'){
  if(typeof input.name!=='string'||input.name.trim().length<2||input.name.trim().length>100||!['asset','income','expense'].includes(String(input.kind)))throw Error('Revise nome e tipo da conta.');
  return{action,unitId:input.unitId,name:input.name.trim(),kind:String(input.kind)} as const;
 }
 if(typeof input.date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(input.date)||new Date(input.date+'T12:00:00Z').toISOString().slice(0,10)!==input.date)throw Error('Data inválida.');
 if(action==='close')return{action,unitId:input.unitId,date:input.date} as const;
 if(!['post','reverse'].includes(String(action))||typeof input.requestId!=='string'||!uuidPattern.test(input.requestId)||typeof input.memo!=='string'||input.memo.trim().length<2||input.memo.length>300)throw Error('Lançamento inválido.');
 if(action==='reverse'){
  if(typeof input.originalId!=='string'||!uuidPattern.test(input.originalId))throw Error('Movimento original inválido.');
  return{action,unitId:input.unitId,date:input.date,requestId:input.requestId,memo:input.memo.trim(),originalId:input.originalId} as const;
 }
 if(typeof input.debit!=='string'||typeof input.credit!=='string'||!uuidPattern.test(input.debit)||!uuidPattern.test(input.credit)||input.debit===input.credit||typeof input.amount!=='string')throw Error('Selecione duas contas distintas e o valor.');
 return{action:'post',unitId:input.unitId,date:input.date,requestId:input.requestId,memo:input.memo.trim(),debit:input.debit,credit:input.credit,amountCents:moneyCents(input.amount)} as const;
}
