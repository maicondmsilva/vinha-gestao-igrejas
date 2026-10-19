import {uuidPattern} from './private-files.ts';
export function summaryUnit(request:Request){const params=new URL(request.url).searchParams;const ids=params.getAll('unitId');if(ids.length!==1||!uuidPattern.test(ids[0]))throw Error('Selecione uma unidade válida.');return ids[0]}
export function peopleSummary(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Relatório indisponível.');
 const body=value as Record<string,unknown>,raw=body.counts as Record<string,unknown>;
 if(typeof body.unitId!=='string'||!uuidPattern.test(body.unitId)||typeof body.generatedAt!=='string'||!Number.isFinite(Date.parse(body.generatedAt))||!raw||typeof raw!=='object')throw Error('Relatório indisponível.');
 const counts={} as Record<'total'|'members'|'visitors'|'integration'|'other',string>;
 for(const key of ['total','members','visitors','integration','other'] as const){if(typeof raw[key]!=='string'||!/^\d{1,20}$/.test(raw[key]))throw Error('Relatório indisponível.');counts[key]=raw[key] as string}
 if(BigInt(counts.total)!==BigInt(counts.members)+BigInt(counts.visitors)+BigInt(counts.integration)+BigInt(counts.other))throw Error('Relatório inconsistente.');
 return{unitId:body.unitId,generatedAt:body.generatedAt,counts};
}
