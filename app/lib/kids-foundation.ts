export const kidsUuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export type KidsAction='profile'|'guardian'|'care'|'review'|'person'|'personReview';
export type KidsCommand={requestId:string;action:KidsAction;id:string;version:number;data:Record<string,unknown>};
export type KidsProfile={id:string;personId:string;name:string;birthDate:string|null;personStatus:string;status:'active'|'archived';reviewStatus:'pending'|'approved';version:number;authorizedCount?:number};
export type KidsGuardian={id:string;personId:string;name:string;phone:string|null;personStatus:string;relationship:string;verificationNote:string;canPickup:boolean;canEdit:boolean;isEmergency:boolean;status:'pending'|'approved'|'revoked';validUntil:string|null;version:number};
export type KidsDetail=KidsProfile&{guardians:KidsGuardian[];care:{instructions:string;source:string;version:number}|null;history:{id:string;action:string;fields:string[];at:string;actor:string}[]};
export type KidsPage={unitId:string;items:KidsProfile[];nextCursor:string|null;pendingNextCursor:string|null;canManage:boolean;canApprove:boolean;canCare:boolean;detail:KidsDetail|null;pendingPeople:{id:string;name:string;birthDate:string|null}[]};
const object=(v:unknown):Record<string,unknown>=>{if(!v||typeof v!=='object'||Array.isArray(v))throw Error('Dados inválidos.');return v as Record<string,unknown>};
const text=(v:unknown,min:number,max:number)=>{if(typeof v!=='string'||v.trim().length<min||v.length>max||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v))throw Error('Revise os campos informados.');return v};
const uuid=(v:unknown)=>typeof v==='string'&&kidsUuid.test(v);
const date=(v:unknown)=>typeof v==='string'&&(v===''||/^\d{4}-\d{2}-\d{2}$/.test(v)&&Number.isFinite(Date.parse(v+'T12:00:00Z'))&&new Date(v+'T12:00:00Z').toISOString().slice(0,10)===v);
export function kidsCommand(value:unknown):KidsCommand{
 const v=object(value),data=object(v.data);
 if(Object.keys(v).sort().join(',')!=='action,data,id,requestId,version'||!uuid(v.id)||!uuid(v.requestId)||!Number.isSafeInteger(v.version)||Number(v.version)<0||Number(v.version)>2147483646)throw Error('Operação inválida.');
 let allowed:string[]=[];
 switch(v.action){
  case 'profile':allowed=['personId','status'];if(!uuid(data.personId)||!['active','archived'].includes(String(data.status)))throw Error('Selecione uma criança cadastrada.');break;
  case 'review':case 'personReview':break;
  case 'person':allowed=['name','birthDate','phone'];text(data.name,2,160);text(data.phone,0,40);if(!data.birthDate||!date(data.birthDate)||v.version!==0)throw Error('Informe uma data de nascimento válida.');break;
  case 'care':allowed=['instructions','source'];text(data.instructions,0,3000);text(data.source,3,300);break;
  case 'guardian':allowed=['profileId','personId','relationship','verificationNote','canPickup','canEdit','isEmergency','status','validUntil'];
   if(!uuid(data.profileId)||!uuid(data.personId)||!['canPickup','canEdit','isEmergency'].every(k=>typeof data[k]==='boolean')||!['pending','approved','revoked'].includes(String(data.status))||!date(data.validUntil))throw Error('Responsável inválido.');
   text(data.relationship,2,80);text(data.verificationNote,data.status==='approved'?10:0,500);break;
  default:throw Error('Operação não disponível.');
 }
 if(Object.keys(data).some(k=>!allowed.includes(k))||allowed.some(k=>!(k in data)))throw Error('Campos não suportados.');
 return v as KidsCommand;
}
export function kidsQuery(request:Request){
 const p=new URL(request.url).searchParams;
 if(p.getAll('unitId').length!==1||!uuid(p.get('unitId')))throw Error('Selecione uma igreja.');
 for(const key of ['profileId','after'])if(p.getAll(key).length>1||p.has(key)&&!uuid(p.get(key)))throw Error('Cadastro inválido.');
 if(p.getAll('search').length>1||p.getAll('q').length>1)throw Error('Filtro inválido.');
 const search=text(p.get('search')||'',0,100),q=p.get('q');if(q!==null)text(q,2,80);
 return {unitId:p.get('unitId')!,profileId:p.get('profileId'),after:p.get('after'),search,q};
}
export function kidsPage(value:unknown,unitId:string):KidsPage{
 const v=object(value);
 if(v.unitId!==unitId||!Array.isArray(v.items)||v.items.length>50||!Array.isArray(v.pendingPeople)||v.pendingPeople.length>50||!['canManage','canApprove','canCare'].every(k=>typeof v[k]==='boolean')||v.nextCursor!==null&&!uuid(v.nextCursor))throw Error('Resposta Kids inválida.');
 const profile=(raw:unknown):KidsProfile=>{const p=object(raw);if(!uuid(p.id)||!uuid(p.personId)||typeof p.name!=='string'||!date(p.birthDate??'')||!Number.isSafeInteger(p.version)||Number(p.version)<1||typeof p.personStatus!=='string'||!['active','archived'].includes(String(p.status))||!['pending','approved'].includes(String(p.reviewStatus)))throw Error('Cadastro Kids inválido.');
  if(p.authorizedCount!==undefined&&(!Number.isSafeInteger(p.authorizedCount)||Number(p.authorizedCount)<0))throw Error('Contagem inválida.');
  return {id:p.id as string,personId:p.personId as string,name:p.name,birthDate:p.birthDate as string|null,personStatus:p.personStatus,status:p.status as KidsProfile['status'],reviewStatus:p.reviewStatus as KidsProfile['reviewStatus'],version:Number(p.version),...p.authorizedCount!==undefined?{authorizedCount:Number(p.authorizedCount)}:{}};
 };
 const items=v.items.map(profile);let detail:KidsDetail|null=null;
 if(v.detail!==null){const basic=profile(v.detail),d=object(v.detail);if(!Array.isArray(d.guardians)||!Array.isArray(d.history)||d.history.length>50)throw Error('Detalhes inválidos.');
  const guardians=d.guardians.map(raw=>{const g=object(raw);if(!uuid(g.id)||!uuid(g.personId)||!Number.isSafeInteger(g.version)||Number(g.version)<1||!['canPickup','canEdit','isEmergency'].every(k=>typeof g[k]==='boolean')||!['pending','approved','revoked'].includes(String(g.status))||!date(g.validUntil??'')||g.phone!==null&&typeof g.phone!=='string')throw Error('Responsável inválido.');
   return {id:g.id as string,personId:g.personId as string,name:text(g.name,2,160),phone:g.phone as string|null,personStatus:text(g.personStatus,1,30),relationship:text(g.relationship,2,80),verificationNote:v.canApprove?text(g.verificationNote,0,500):'',canPickup:g.canPickup as boolean,canEdit:g.canEdit as boolean,isEmergency:g.isEmergency as boolean,status:g.status as KidsGuardian['status'],validUntil:g.validUntil as string|null,version:Number(g.version)};
  });
  const history=d.history.map(raw=>{const h=object(raw);if(typeof h.id!=='string'||!/^\d+$/.test(h.id)||typeof h.at!=='string'||!Number.isFinite(Date.parse(h.at))||!Array.isArray(h.fields)||!h.fields.every(f=>typeof f==='string'))throw Error('Histórico inválido.');return {id:h.id,action:text(h.action,1,50),fields:h.fields as string[],at:h.at,actor:text(h.actor,1,200)};});
  let care:KidsDetail['care']=null;if(v.canCare&&d.care!==null){const c=object(d.care);if(!Number.isSafeInteger(c.version)||Number(c.version)<1)throw Error('Cuidado inválido.');care={instructions:text(c.instructions,0,3000),source:text(c.source,3,300),version:Number(c.version)};}
  detail={...basic,guardians,care,history};
 }
 const pendingPeople=v.pendingPeople.map(raw=>{const p=object(raw);if(!uuid(p.id)||!date(p.birthDate??''))throw Error('Pessoa inválida.');return{id:p.id as string,name:text(p.name,2,160),birthDate:p.birthDate as string|null};});
 if(v.pendingNextCursor!==null&&!uuid(v.pendingNextCursor))throw Error('Paginação inválida.');
 return {unitId,items,nextCursor:v.nextCursor as string|null,pendingNextCursor:v.pendingNextCursor as string|null,canManage:v.canManage as boolean,canApprove:v.canApprove as boolean,canCare:v.canCare as boolean,detail,pendingPeople};
}
export const kidsActionLabels:Record<string,string>={'kids.profile':'Cadastro Kids atualizado','kids.guardian':'Vínculo de responsável atualizado','kids.care':'Cuidados atualizados','kids.review':'Cadastro Kids revisado','kids.person':'Pessoa cadastrada para revisão','kids.personReview':'Cadastro de pessoa aprovado'};
