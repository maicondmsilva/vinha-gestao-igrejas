import type {OperationsClient} from './operations';
import {cellUuid} from '../cell-directory';
export function reminderBatch(value:unknown):{created:number;scanned:number;unreachable:number;nextCursor:string|null}{if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Lote inválido.');const d=value as Record<string,unknown>;if(Object.keys(d).sort().join(',')!=='created,nextCursor,scanned,unreachable'||['created','scanned','unreachable'].some(k=>!Number.isSafeInteger(d[k])||Number(d[k])<0)||Number(d.scanned)>100||Number(d.unreachable)>Number(d.scanned)||d.nextCursor!==null&&(typeof d.nextCursor!=='string'||!cellUuid.test(d.nextCursor)||d.scanned!==100))throw Error('Lote inválido.');return d as {created:number;scanned:number;unreachable:number;nextCursor:string|null}}
export async function processCellReportReminders(client:OperationsClient){let after:string|null=null,created=0,scanned=0,unreachable=0;const seen=new Set<string>();
 for(let batch=0;batch<10;batch++){
  const result=await client.rpc('cell_report_reminder_batch',{p_after:after});
  if(result.error)throw Error('Rotina interna de Células indisponível.');const data=reminderBatch(result.data);
  if(data.nextCursor&&(seen.has(data.nextCursor)||after!==null&&data.nextCursor<=after))throw Error('Não foi possível validar a rotina interna de Células.');
  created+=data.created;scanned+=data.scanned;unreachable+=data.unreachable;after=data.nextCursor;if(!after)break;seen.add(after);
 }
 return {created,scanned,unreachable,hasMore:after!==null,nextCursor:after};
}
