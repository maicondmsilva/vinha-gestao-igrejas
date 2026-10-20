import {cellUuid} from './cell-directory';
export type HierarchyItem={id:string;name:string;status:'active'|'archived';parent_id:string|null;parent_name:string|null;version:number;path:string};
export type TransferItem={id:string;source_id:string;source_cell_id:string;target_cell_id:string;source_name:string;target_name:string;person_id:string;person_name:string;source_version:number;status:'pending'|'accepted'|'rejected'|'cancelled';version:number;created_at:string;resolved_at:string|null;can_cancel:boolean};
export type FlowKind='hierarchy'|'transfers';
export type FlowPage={unitId:string;kind:FlowKind;items:(HierarchyItem|TransferItem)[];nextCursor:string|null;canManage:boolean};
function object(v:unknown):Record<string,unknown>{if(!v||typeof v!=='object'||Array.isArray(v))throw Error('invalid_cell_flow');return v as Record<string,unknown>}
function keys(v:Record<string,unknown>,k:string[]){if(Object.keys(v).sort().join(',')!==[...k].sort().join(','))throw Error('invalid_cell_flow')}
export function flowUuid(v:unknown):string{if(typeof v!=='string'||!cellUuid.test(v))throw Error('invalid_cell_flow');return v}
function integer(v:unknown,min:number){if(!Number.isSafeInteger(v)||Number(v)<min||Number(v)>2147483647)throw Error('invalid_cell_flow');return v as number}
function text(v:unknown,min=1,max=4096){if(typeof v!=='string'||v.trim().length<min||v.length>max||/[\x00-\x1f\x7f]/.test(v))throw Error('invalid_cell_flow');return v}
function date(v:unknown){const t=text(v,1,64);if(!Number.isFinite(Date.parse(t)))throw Error('invalid_cell_flow');return t}
export function flowCommand(value:unknown){const v=object(value);keys(v,['kind','id','version','data']);const id=flowUuid(v.id),version=integer(v.version,0),d=object(v.data);
 if(v.kind==='hierarchy'){keys(d,['parent_id']);const parent_id=d.parent_id===null?null:flowUuid(d.parent_id);if(parent_id===id)throw Error('invalid_cell_flow');return {kind:'hierarchy',id,version,data:{parent_id}}}
 if(v.kind==='request'){keys(d,['source_id','target_cell_id','source_version']);if(version!==0)throw Error('invalid_cell_flow');return {kind:'request',id,version,data:{source_id:flowUuid(d.source_id),target_cell_id:flowUuid(d.target_cell_id),source_version:integer(d.source_version,1)}}}
 if(v.kind!=='accept'&&v.kind!=='reject'&&v.kind!=='cancel'||version<1)throw Error('invalid_cell_flow');keys(d,[]);return {kind:v.kind,id,version,data:{}};
}
export function flowQuery(request:Request){const p=new URL(request.url).searchParams;for(const k of ['unitId','kind','after'])if(p.getAll(k).length>1)throw Error('invalid_cell_flow');const kind=p.get('kind');if(kind!=='hierarchy'&&kind!=='transfers')throw Error('invalid_cell_flow');return {unitId:flowUuid(p.get('unitId')),kind:kind as FlowKind,after:p.has('after')?flowUuid(p.get('after')):null}}
export function flowPage(value:unknown):FlowPage{const v=object(value);keys(v,['unitId','kind','items','nextCursor','canManage']);const unitId=flowUuid(v.unitId),nextCursor=v.nextCursor===null?null:flowUuid(v.nextCursor);if(v.kind!=='hierarchy'&&v.kind!=='transfers'||typeof v.canManage!=='boolean'||!Array.isArray(v.items)||v.items.length>100)throw Error('invalid_cell_flow');
 const items=v.items.map(raw=>{const r=object(raw),id=flowUuid(r.id),version=integer(r.version,v.kind==='hierarchy'?0:1);
 if(v.kind==='hierarchy'){keys(r,['id','name','status','parent_id','parent_name','version','path']);if(r.status!=='active'&&r.status!=='archived'||(r.parent_id===null)!==(r.parent_name===null))throw Error('invalid_cell_flow');return {id,version,name:text(r.name,2,100),status:r.status,parent_id:r.parent_id===null?null:flowUuid(r.parent_id),parent_name:r.parent_name===null?null:text(r.parent_name,2,100),path:text(r.path)} as HierarchyItem}
 keys(r,['id','source_id','source_cell_id','target_cell_id','source_name','target_name','person_id','person_name','source_version','status','version','created_at','resolved_at','can_cancel']);
 if(!['pending','accepted','rejected','cancelled'].includes(String(r.status))||typeof r.can_cancel!=='boolean'||(r.status==='pending')!==(r.resolved_at===null)||r.source_cell_id===r.target_cell_id)throw Error('invalid_cell_flow');
 return {id,version,source_id:flowUuid(r.source_id),source_cell_id:flowUuid(r.source_cell_id),target_cell_id:flowUuid(r.target_cell_id),source_name:text(r.source_name,2,120),target_name:text(r.target_name,2,120),person_id:flowUuid(r.person_id),person_name:text(r.person_name,1,200),source_version:integer(r.source_version,1),status:r.status,created_at:date(r.created_at),resolved_at:r.resolved_at===null?null:date(r.resolved_at),can_cancel:r.can_cancel} as TransferItem});
 if(new Set(items.map(r=>r.id)).size!==items.length||items.some((r,i)=>i>0&&r.id<=items[i-1].id)||nextCursor&&(items.length!==100||nextCursor!==items.at(-1)?.id))throw Error('invalid_cell_flow');
 return {unitId,kind:v.kind,items,nextCursor,canManage:v.canManage};
}
