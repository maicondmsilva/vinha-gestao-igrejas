import type {ReportRow} from './finance-f6';
/** Group only rows inside the server-authorized period/filter. Never use the
 * lifetime receipt total to calculate a period's cash flow. */
export function unifiedReportRows(rows:ReportRow[]):ReportRow[]{
 const groups=new Map<string,ReportRow[]>();
 for(const row of rows){const key=row.receipt?`${row.unit}/${row.account}/${row.receipt}`:`entry/${row.journal}/${row.id}/${groups.size}`;const group=groups.get(key)||[];group.push(row);groups.set(key,group)}
 return [...groups.values()].map(group=>{
  if(!group[0].receipt)return group[0];
  const root=group.find(r=>r.digital_kind==='gross')||group[0],dates=[...new Set(group.map(r=>r.date))].sort();
  const total=(kind:string)=>group.filter(r=>r.digital_kind===kind).reduce((n,r)=>n+BigInt(r.amount),BigInt(0));
  const money=(n:bigint)=>{const abs=(n<BigInt(0)?-n:n).toString().padStart(3,'0');return(n<BigInt(0)?'-':'')+abs.slice(0,-2)+','+abs.slice(-2)};
  const components=`No período: recebido R$ ${money(total('gross'))}; taxas R$ ${money(-total('fee')-total('fee_credit'))}; devolvido R$ ${money(-total('refund'))}`;
  return {...root,description:`Recebimento digital${root.event_name?' · '+root.event_name+(root.event_number?' · ID '+root.event_number:''):''} · ${components}`,date:dates.length>1?`${dates[0]} a ${dates.at(-1)}`:dates[0],cashDate:dates.length>1?null:root.cashDate,amount:group.reduce((n,r)=>n+BigInt(r.amount),BigInt(0)).toString(),kind:'income',reconciled:group.every(r=>r.reconciled),metadataMissing:group.some(r=>r.metadataMissing),status:root.paymentState||root.digital_payment?.state||root.status};
 });
}
