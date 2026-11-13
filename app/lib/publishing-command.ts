import {uuidPattern} from './private-files.ts';
import {publishingKinds,publicationSource,type PublishingKind} from '../../shared/publishing.ts';
import {mediaHttps} from '../../shared/ministry-media.ts';
const ids=(v:unknown)=>Array.isArray(v)&&v.length<=200&&new Set(v).size===v.length&&v.every(x=>typeof x==='string'&&uuidPattern.test(x));
export function publishingCommand(value:unknown){if(!value||typeof value!=='object'||Array.isArray(value))return null;const b=value as Record<string,unknown>,d=b.data as Record<string,unknown>;
 if(Object.keys(b).some(k=>!['unit','action','id','version','data'].includes(k))||typeof b.unit!=='string'||!uuidPattern.test(b.unit)||typeof b.id!=='string'||!uuidPattern.test(b.id)||!Number.isInteger(b.version)||Number(b.version)<0||!d||typeof d!=='object'||Array.isArray(d))return null;
 if(b.action==='group'){
  if(Object.keys(d).sort().join(',')!=='active,targets,title'||typeof d.title!=='string'||d.title.trim().length<2||d.title.length>100||!ids(d.targets)||!(d.targets as string[]).length||typeof d.active!=='boolean')return null;
 }else if(b.action==='save'){
  const fields=['kind','title','body','source','poster','category','channel','scope','targets','group','groupVersion','provider','starts','ends','download','share'];
  if(Object.keys(d).length!==fields.length||Object.keys(d).some(k=>!fields.includes(k))||!publishingKinds.includes(d.kind as PublishingKind)||typeof d.title!=='string'||d.title.trim().length<2||d.title.length>160||typeof d.body!=='string'||d.body.length>(d.kind==='page'?12000:4000)||typeof d.source!=='string'||typeof d.poster!=='string'||d.poster!==''&&!mediaHttps(d.poster)||!['local','selected','all','group'].includes(String(d.scope))||!ids(d.targets)||!['','youtube','vimeo','hls'].includes(String(d.provider))||typeof d.download!=='boolean'||typeof d.share!=='boolean')return null;
  for(const k of ['category','channel','group'])if(d[k]!==''&&(typeof d[k]!=='string'||!uuidPattern.test(d[k] as string)))return null;
  if(!Number.isInteger(d.groupVersion)||Number(d.groupVersion)<0||['starts','ends'].some(k=>typeof d[k]!=='string'||d[k]!==''&&!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(d[k] as string)||d[k]!==''&&!Number.isFinite(Date.parse(d[k] as string))))return null;
  const source=publicationSource(d.kind as PublishingKind,d.source,String(d.provider));if(source===null)return null;
  if(d.kind==='live'&&(!d.starts||!d.ends)||d.starts&&d.ends&&Date.parse(d.ends as string)<=Date.parse(d.starts as string)||d.download&&(d.kind!=='video'||!new URL(source).pathname.toLowerCase().endsWith('.mp4')))return null;
  d.source=source;
 }else if(!['publish','archive','live','end'].includes(String(b.action))||Number(b.version)<1||Object.keys(d).length)return null;
 return{unit:b.unit,action:String(b.action),id:b.id,version:Number(b.version),data:d};
}
