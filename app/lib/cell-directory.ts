export const cellUuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export type CellInput={name:string;leader_name:string;meeting_day:number;meeting_time:string;meeting_format:'presential'|'online'|'hybrid';location:string;status:'active'|'archived'};
export type CellRecord=CellInput&{id:string;version:number};
export function cellInput(value:unknown):CellInput{
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('invalid');
 const v=value as Record<string,unknown>, keys=['name','leader_name','meeting_day','meeting_time','meeting_format','location','status'];
 if(Object.keys(v).length!==keys.length||keys.some(k=>!(k in v)))throw Error('invalid');
 for(const [key,min,max] of [['name',2,120],['leader_name',0,120],['location',0,300]] as const){if(typeof v[key]!=='string'||v[key].trim().length<min||v[key].length>max||/[\x00-\x1f\x7f]/.test(v[key]))throw Error('invalid')}
 if(!Number.isInteger(v.meeting_day)||Number(v.meeting_day)<0||Number(v.meeting_day)>6||typeof v.meeting_time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(v.meeting_time)||typeof v.meeting_format!=='string'||!['presential','online','hybrid'].includes(v.meeting_format)||typeof v.status!=='string'||!['active','archived'].includes(v.status))throw Error('invalid');
 return {...v,name:String(v.name).trim(),leader_name:String(v.leader_name).trim(),location:String(v.location).trim()} as CellInput;
}
export function cellPage(value:unknown):{unitId:string;items:CellRecord[];canManage:boolean;nextCursor:string|null}{
 const v=value as Record<string,unknown>;
 if(!v||typeof v.unitId!=='string'||!cellUuid.test(v.unitId)||!Array.isArray(v.items)||v.items.length>100||typeof v.canManage!=='boolean'||(v.nextCursor!==null&&(typeof v.nextCursor!=='string'||!cellUuid.test(v.nextCursor))))throw Error('invalid');
 const items=v.items.map((raw:unknown)=>{const r=raw as CellRecord;if(!r||!cellUuid.test(r.id)||!Number.isSafeInteger(r.version)||r.version<1)throw Error('invalid');const {id,version,...input}=r;return {...cellInput(input),id,version}});
 if(new Set(items.map(i=>i.id)).size!==items.length)throw Error('invalid');
 return {unitId:v.unitId,items,canManage:v.canManage,nextCursor:v.nextCursor as string|null};
}
