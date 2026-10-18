const required=['isolatedPreview','databaseRestore','storageRestore','rollbackRehearsal','monitoring','supportOwner','pilotApproval'] as const;
type Gate=typeof required[number];
export type OperationalEvidence={gate:Gate;passed:boolean;verifiedAt:string;reference:string};
export function pilotReadiness(evidence:OperationalEvidence[],now=Date.now()){
 return required.map(gate=>{const entries=evidence.filter(x=>x.gate===gate),item=entries.length===1?entries[0]:undefined;
 const timestamp=item?Date.parse(item.verifiedAt):NaN;
 return{gate,ready:!!item&&item.passed===true&&Number.isFinite(timestamp)&&timestamp<=now&&now-timestamp<=30*86400000&&/^[A-Za-z0-9][A-Za-z0-9._:/-]{2,199}$/.test(item.reference)};
 });
}
// Whitelisted metrics only: never serialize errors, paths, URLs, bodies or identities.
export function operationMetric(input:{operation:string;outcome:string;durationMs:number}){
 const operations=['login','member_import','ledger_post','cron','delivery','backup','restore'];
 const outcomes=['success','denied','error'];
 if(!operations.includes(input.operation)||!outcomes.includes(input.outcome)||!Number.isFinite(input.durationMs)||input.durationMs<0)throw Error('Métrica inválida.');
 return{operation:input.operation,outcome:input.outcome,durationMs:Math.min(Math.round(input.durationMs),86400000)};
}
