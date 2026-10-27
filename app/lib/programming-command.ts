import {uuidPattern} from './private-files.ts';
import {parseAgendaCommand} from './member-agenda-command.ts';
import {coverUrl} from '../../shared/programming.ts';
export function programmingCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))return null;
 const b=value as Record<string,unknown>,data=b.data as Record<string,unknown>;
 if(Object.keys(b).some(k=>!['unit','action','id','version','data'].includes(k))||typeof b.unit!=='string'||!uuidPattern.test(b.unit)||typeof b.action!=='string'||!data||typeof data!=='object'||Array.isArray(data))return null;
 const id=typeof b.id==='string'&&uuidPattern.test(b.id)?b.id:null,version=Number.isSafeInteger(b.version)&&Number(b.version)>0?Number(b.version):null;
 if(['create','edit'].includes(b.action)){
  if(!id||b.action==='edit'&&!version||Object.keys(data).some(k=>!['title','description','kind','startsLocal','endsLocal','location','address','capacity','category','cover','repeat','count','future','versions'].includes(k)))return null;
  const fields=Object.fromEntries(['title','description','kind','startsLocal','endsLocal','location','address','capacity'].map(k=>[k,data[k]]));
  if(!parseAgendaCommand({action:b.action,unit:b.unit,id,version,data:fields})||!(data.category===''||typeof data.category==='string'&&uuidPattern.test(data.category))||coverUrl(data.cover)===null)return null;
  if(b.action==='create'&&(!['none','daily','weekly','monthly'].includes(String(data.repeat))||!Number.isInteger(data.count)||Number(data.count)<1||Number(data.count)>52||data.repeat==='none'&&data.count!==1||'future'in data||'versions'in data))return null;
  if(b.action==='edit'&&(typeof data.future!=='boolean'||!data.versions||typeof data.versions!=='object'||Array.isArray(data.versions)||Object.entries(data.versions).some(([k,v])=>!uuidPattern.test(k)||!Number.isInteger(v)||Number(v)<1)||Object.keys(data.versions).length>52||'repeat'in data||'count'in data))return null;
 }else if(b.action==='category'){
  if(!id||!Number.isInteger(b.version)||Number(b.version)<0||Object.keys(data).sort().join(',')!=='active,color,name'||typeof data.name!=='string'||data.name.trim().length<2||data.name.length>80||typeof data.color!=='string'||!/^#[0-9a-f]{6}$/i.test(data.color)||typeof data.active!=='boolean')return null;
 }else if(['publish','cancel'].includes(b.action)){
  if(!id||!version||Object.keys(data).sort().join(',')!=='future,versions'||typeof data.future!=='boolean'||!data.versions||typeof data.versions!=='object'||Array.isArray(data.versions)||Object.keys(data.versions).length>52||Object.entries(data.versions).some(([k,v])=>!uuidPattern.test(k)||!Number.isInteger(v)||Number(v)<1))return null;
 }else if(b.action==='price'){
  if(!id||!version||Object.keys(data).sort().join(',')!=='amount,purpose'||typeof data.amount!=='string'||!/^\d{1,8}$/.test(data.amount)||Number(data.amount)!==0&&Number(data.amount)<100||typeof data.purpose!=='string'||!(data.purpose===''&&Number(data.amount)===0||uuidPattern.test(data.purpose)))return null;
 }else if(b.action==='checkin'){if(!parseAgendaCommand(b))return null}
 else return null;
 return{unit:b.unit,action:b.action,id,version:b.action==='category'?Number(b.version):version,data};
}
