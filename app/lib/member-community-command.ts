import {uuidPattern} from './private-files.ts';
const text=(v:unknown,min:number,max:number)=>typeof v==='string'&&v.trim().length>=min&&v.length<=max;
export function parseCommunityAdmin(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))return null;const b=value as Record<string,unknown>;if(Object.keys(b).some(k=>!['action','unit','id','version','data','offset'].includes(k))||typeof b.unit!=='string'||!uuidPattern.test(b.unit)||typeof b.action!=='string')return null;
 const reads=['prayers','testimonies','groups','participants'],write=['prayer.review','testimony.review','group.create','group.edit','participant.review'];if(![...reads,...write].includes(b.action))return null;
 const offset=b.offset??0;if(!Number.isSafeInteger(offset)||Number(offset)<0||Number(offset)>100000)return null;
 const d=(b.data??{}) as Record<string,unknown>;if(!d||typeof d!=='object'||Array.isArray(d))return null;
 const id=b.id??null,version=b.version??null;if(!reads.includes(b.action)&&b.action!=='group.create'&&(typeof id!=='string'||!uuidPattern.test(id)||!Number.isSafeInteger(version)||Number(version)<1))return null;
 if(reads.includes(b.action)){if(Object.keys(d).length)return null;}
 else if(b.action.startsWith('group.')){if(Object.keys(d).some(k=>!['nonce','name','description','kind','active','accepting'].includes(k))||!text(d.name,2,160)||!text(d.description,0,2000)||!['ministry','department'].includes(String(d.kind))||typeof d.active!=='boolean'||typeof d.accepting!=='boolean'||b.action==='group.create'&&!text(d.nonce,10,100))return null;}
 else{const field=b.action==='prayer.review'?'reply':'reason',statuses=b.action==='prayer.review'?['care','completed']:b.action==='testimony.review'?['published','rejected']:['approved','rejected'];if(Object.keys(d).some(k=>!['status',field].includes(k))||!statuses.includes(String(d.status))||!text(d[field],d.status==='rejected'?3:0,2000))return null;}
 return {action:b.action,unit:b.unit,id:id as string|null,version:version as number|null,data:d,offset:Number(offset)};
}
