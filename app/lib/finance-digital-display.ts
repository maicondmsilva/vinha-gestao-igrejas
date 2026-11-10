type DisplayReceipt={event_name?:string;event_number?:string;id:string;purpose:string;party_name:string;source_reference:string;environment:string;posted_gross:string;posted_fee:string;posted_refund:string;review_reason:string|null;snapshot:Record<string,unknown>|null};
/** Totals are posted ledger values of the loaded page, never pending amounts or sandbox money. */
export function digitalPageTotals(items:readonly DisplayReceipt[]){
 let gross=BigInt(0),fees=BigInt(0),refunds=BigInt(0),review=0;
 for(const item of items){if(item.environment!=='production')continue;gross+=BigInt(item.posted_gross||'0');fees+=BigInt(item.posted_fee||'0');refunds+=BigInt(item.posted_refund||'0');if(item.review_reason)review++}
 return{gross,fees,refunds,net:gross-fees-refunds,review};
}
export function digitalRecordState(item:Pick<DisplayReceipt,'snapshot'>){return typeof item.snapshot?.state==='string'?item.snapshot.state:'waiting'}
export function digitalRecordMatches(item:DisplayReceipt,query:string,status:string){
 const normalized=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR');
 const state=digitalRecordState(item),matches=!status||(status==='review'?Boolean(item.review_reason):status==='sandbox'?item.environment==='sandbox':state===status);
 return matches&&normalized([item.event_name||'',item.event_number||'',item.id,item.purpose,item.party_name,item.source_reference,String(item.snapshot?.externalId||'')].join(' ')).includes(normalized(query.trim()));
}
