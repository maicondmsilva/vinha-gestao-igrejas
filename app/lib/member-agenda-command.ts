import {uuidPattern} from './private-files.ts';
type Command={action:string;unit:string;id:string|null;version:number|null;data:Record<string,unknown>};
export function parseAgendaCommand(value:unknown):Command|null{
 if(!value||typeof value!=='object'||Array.isArray(value))return null;const b=value as Record<string,unknown>;
 if(Object.keys(b).some(k=>!['action','unit','id','version','data'].includes(k))||typeof b.action!=='string'||!['create','edit','publish','cancel','checkin'].includes(b.action)||typeof b.unit!=='string'||!uuidPattern.test(b.unit))return null;
 const id=typeof b.id==='string'&&uuidPattern.test(b.id)?b.id:null,version=Number.isInteger(b.version)&&Number(b.version)>0?Number(b.version):null;
 const data=(b.data||{}) as Record<string,unknown>;if(typeof data!=='object'||Array.isArray(data))return null;
 if(b.action!=='create'&&!id)return null;if(['edit','publish','cancel'].includes(b.action)&&!version)return null;
 if(['create','edit'].includes(b.action)){
  const fields=['title','description','kind','startsLocal','endsLocal','location','address','capacity'];if(Object.keys(data).length!==fields.length||Object.keys(data).some(k=>!fields.includes(k))||fields.filter(k=>k!=='capacity').some(k=>typeof data[k]!=='string'))return null;
  if(String(data.title).trim().length<2||String(data.title).length>160||String(data.description).length>4000||String(data.location).length>160||String(data.address).length>300||!['event','service'].includes(String(data.kind))||!Number.isInteger(data.capacity)||Number(data.capacity)<1||Number(data.capacity)>50000||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(String(data.startsLocal))||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(String(data.endsLocal)))return null;
 }else if(b.action==='checkin'){if(Object.keys(data).length!==1||typeof data.code!=='string'||!uuidPattern.test(data.code))return null}
 else if(Object.keys(data).length)return null;
 return{action:b.action,unit:b.unit,id,version,data};
}
