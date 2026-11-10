import {uuidPattern} from './private-files.ts';
type Balance={accountId:string;name:string;kind:string;balanceCents:string};
export function ledgerBalanceCsv(unitId:string,date:string,balances:Balance[]){
 if(!uuidPattern.test(unitId)||!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date+'T12:00:00Z').toISOString().slice(0,10)!==date||!Array.isArray(balances)||balances.length>500)throw Error('Relatório inválido.');
 const cell=(value:string)=>'"'+(/^[\s\uFEFF]*[=+\-@]/u.test(value)?"'"+value:value).replaceAll('"','""')+'"';
 const rows=[['unidade_id','data_corte','conta_id','nome','tipo','saldo_centavos','saldo_reais']];
 for(const b of balances){
  if(!uuidPattern.test(b.accountId)||typeof b.name!=='string'||b.name.length>100||!['asset','income','expense'].includes(b.kind)||typeof b.balanceCents!=='string'||! /^-?\d{1,40}$/.test(b.balanceCents))throw Error('Saldo inválido.');
  const cents=BigInt(b.balanceCents),absolute=cents<BigInt(0)?-cents:cents;
  const reais=(cents<BigInt(0)?'-':'')+(absolute/BigInt(100)).toString()+','+(absolute%BigInt(100)).toString().padStart(2,'0');
  rows.push([unitId,date,b.accountId,b.name,b.kind,b.balanceCents,reais]);
 }
 return '\uFEFF'+rows.map(row=>row.map(cell).join(';')).join('\r\n')+'\r\n';
}
