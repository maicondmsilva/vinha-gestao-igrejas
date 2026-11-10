import {cellUuid} from './cell-directory';
export type Category={id:string;name:string;status:'active'|'archived';version:number};
export type Participant={id:string;person_id:string;name:string;status:'active'|'inactive';version:number};
export type Meeting={id:string;cell_id:string;topic:string;meeting_date:string;meeting_time:string;status:'scheduled'|'completed'|'cancelled';version:number};
export type Roster={id:string;name:string;present:boolean};
export type PersonChoice={id:string;name:string};
export type CellReport={id:string;name:string;status:'active'|'archived';category:string;participants:number;meetings:number;expected:number;present:number};
export type OperationRow=Category|Participant|Meeting|Roster|PersonChoice|CellReport;
export type CellReadKind='categories'|'participants'|'meetings'|'roster'|'people'|'report';
export type CellWriteKind='category'|'assign_category'|'participant'|'meeting';
const object=(v:unknown):Record<string,unknown>=>{if(!v||typeof v!=='object'||Array.isArray(v))throw Error('invalid_input');return v as Record<string,unknown>};
const keys=(v:Record<string,unknown>,fields:string[])=>{if(Object.keys(v).length!==fields.length||fields.some(k=>!Object.hasOwn(v,k)))throw Error('invalid_input')};
export function operationUuid(v:unknown):string{if(typeof v!=='string'||!cellUuid.test(v))throw Error('invalid_input');return v}
export function operationText(v:unknown,min:number,max:number):string{if(typeof v!=='string'||v.trim().length<min||v.length>max||/[\x00-\x1f\x7f]/.test(v))throw Error('invalid_input');return v.trim()}
const integer=(v:unknown,min=0)=>{if(!Number.isSafeInteger(v)||Number(v)<min)throw Error('invalid_input');return Number(v)};
export function calendarDate(v:unknown):string{if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(v)||v<'1900-01-01'||v>'2200-12-31'||Number.isNaN(Date.parse(v+'T12:00:00Z'))||new Date(v+'T12:00:00Z').toISOString().slice(0,10)!==v)throw Error('invalid_input');return v}
function choice<T extends string>(v:unknown,values:readonly T[]):T{if(typeof v!=='string'||!values.includes(v as T))throw Error('invalid_input');return v as T}
export function cellWriteInput(value:unknown){
 const v=object(value);keys(v,['kind','cellId','id','version','data']);
 const kind=choice(v.kind,['category','assign_category','participant','meeting'] as const),id=operationUuid(v.id),version=integer(v.version),data=object(v.data);
 const cellId=kind==='category'?(v.cellId===null?null:operationUuid(v.cellId)):operationUuid(v.cellId);
 if(kind==='category'){if(cellId!==null)throw Error('invalid_input');keys(data,['name','status']);return {kind,cellId,id,version,data:{name:operationText(data.name,2,80),status:choice(data.status,['active','archived'] as const)}}}
 if(kind==='assign_category'){if(id!==cellId)throw Error('invalid_input');keys(data,['category_id']);return {kind,cellId,id,version,data:{category_id:data.category_id===null?null:operationUuid(data.category_id)}}}
 if(kind==='participant'){keys(data,['person_id','status']);return {kind,cellId,id,version,data:{person_id:operationUuid(data.person_id),status:choice(data.status,['active','inactive'] as const)}}}
 keys(data,['topic','meeting_date','meeting_time','status','present']);
 const status=choice(data.status,['scheduled','completed','cancelled'] as const),meeting_time=operationText(data.meeting_time,5,5);
 if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(meeting_time)||!Array.isArray(data.present)||data.present.length>500)throw Error('invalid_input');
 const present=data.present.map(operationUuid);if(new Set(present).size!==present.length||(status!=='completed'&&present.length))throw Error('invalid_input');
 return {kind,cellId,id,version,data:{topic:operationText(data.topic,2,120),meeting_date:calendarDate(data.meeting_date),meeting_time,status,present}};
}
export function cellReadQuery(request:Request){
 const p=new URL(request.url).searchParams;
 for(const key of ['unitId','kind','cellId','recordId','after','q','from','to'])if(p.getAll(key).length>1)throw Error('invalid_input');
 const kind=choice(p.get('kind'),['categories','participants','meetings','roster','people','report'] as const),unitId=operationUuid(p.get('unitId'));
 const cellId=p.has('cellId')?operationUuid(p.get('cellId')):null,recordId=p.has('recordId')?operationUuid(p.get('recordId')):null,after=p.has('after')?operationUuid(p.get('after')):null;
 if((['participants','roster'].includes(kind)&&!cellId)||(recordId&&kind!=='roster'))throw Error('invalid_input');
 const today=new Date().toISOString().slice(0,10),from=calendarDate(p.get('from')||today.slice(0,8)+'01'),to=calendarDate(p.get('to')||today);
 if(to<from||(Date.parse(to)-Date.parse(from))/86400000>366)throw Error('invalid_input');
 return {kind,unitId,cellId,recordId,after,from,to,search:kind==='people'?operationText(p.get('q'),2,80):''};
}
export function cellOperationsPage(value:unknown,kind:CellReadKind){
 const v=object(value);const unitId=operationUuid(v.unitId),cellId=v.cellId===null?null:operationUuid(v.cellId);
 if(v.kind!==kind||typeof v.canManage!=='boolean'||!Array.isArray(v.items)||v.items.length>(kind==='roster'?500:kind==='people'?30:100))throw Error('invalid_response');
 const items:OperationRow[]=v.items.map(raw=>{
  const r=object(raw),id=operationUuid(r.id);
  if(kind==='categories'){keys(r,['id','name','status','version']);return{id,name:operationText(r.name,2,80),status:choice(r.status,['active','archived'] as const),version:integer(r.version,1)}}
  if(kind==='participants'){keys(r,['id','person_id','name','status','version']);return{id,person_id:operationUuid(r.person_id),name:operationText(r.name,2,160),status:choice(r.status,['active','inactive'] as const),version:integer(r.version,1)}}
  if(kind==='meetings'){keys(r,['id','cell_id','topic','meeting_date','meeting_time','status','version']);const meeting_time=operationText(r.meeting_time,5,5);if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(meeting_time))throw Error();return{id,cell_id:operationUuid(r.cell_id),topic:operationText(r.topic,2,120),meeting_date:calendarDate(r.meeting_date),meeting_time,status:choice(r.status,['scheduled','completed','cancelled'] as const),version:integer(r.version,1)}}
  if(kind==='roster'){keys(r,['id','name','present']);if(typeof r.present!=='boolean')throw Error();return{id,name:operationText(r.name,2,160),present:r.present}}
  if(kind==='people'){keys(r,['id','name']);return{id,name:operationText(r.name,2,160)}}
  keys(r,['id','name','status','category','participants','meetings','expected','present']);const present=integer(r.present),expected=integer(r.expected);if(present>expected)throw Error();return{id,name:operationText(r.name,2,120),status:choice(r.status,['active','archived'] as const),category:operationText(r.category,2,80),participants:integer(r.participants),meetings:integer(r.meetings),expected,present};
 });
 if(new Set(items.map(i=>i.id)).size!==items.length)throw Error('invalid_response');
 let assignment:{category_id:string|null;version:number}|null=null;
 if(v.assignment!==null){const a=object(v.assignment);keys(a,['category_id','version']);assignment={category_id:a.category_id===null?null:operationUuid(a.category_id),version:integer(a.version,1)}}
 return {unitId,cellId,kind,items,canManage:v.canManage,nextCursor:v.nextCursor===null?null:operationUuid(v.nextCursor),assignment};
}
