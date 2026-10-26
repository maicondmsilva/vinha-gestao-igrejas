import {uuidPattern} from './private-files.ts';
const reads=['kids.requests','kids.reception','cells.requests','cells.catalog'];
export function parseFamilyAdmin(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))return null;const b=value as Record<string,unknown>,d=(b.data??{}) as Record<string,unknown>,offset=b.offset??0;
 if(Object.keys(b).some(k=>!['unit','action','id','version','data','offset'].includes(k))||typeof b.unit!=='string'||!uuidPattern.test(b.unit)||typeof b.action!=='string'||![...reads,'kids.review','cells.review','cells.publish'].includes(b.action)||!d||typeof d!=='object'||Array.isArray(d)||!Number.isInteger(offset)||Number(offset)<0||Number(offset)>100000)return null;
 if(!reads.includes(b.action)&&(typeof b.id!=='string'||!uuidPattern.test(b.id)||!Number.isInteger(b.version)||Number(b.version)<0))return null;
 if(reads.includes(b.action)&&Object.keys(d).length)return null;
 if(b.action==='cells.publish'&&(Object.keys(d).sort().join(',')!=='area,description,published'||typeof d.area!=='string'||d.area.length>160||typeof d.description!=='string'||d.description.length>2000||typeof d.published!=='boolean'))return null;
 if(b.action.endsWith('.review')&&(Object.keys(d).sort().join(',')!=='decision,existingProfile,reason,verification'||!['approved','rejected'].includes(String(d.decision))||typeof d.reason!=='string'||d.reason.trim().length<3||d.reason.length>1000||typeof d.verification!=='string'||d.verification.length>500||typeof d.existingProfile!=='string'||d.existingProfile!==''&&!uuidPattern.test(d.existingProfile)))return null;
 return{unit:b.unit,action:b.action,id:b.id??null,version:b.version??null,data:d,offset:Number(offset)};
}
