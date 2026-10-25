export const memberFields=['name','email','phone','status','group','birthDate','gender','maritalStatus','cpf','firstVisit','joined','baptized','baptismDate','tags','address','number','extra','district','city','state','zip','emergencyName','emergencyPhone','notes','privacy','imageConsent','messages'] as const;
import {normalizeRegistrationField} from '../../shared/brazil-registration.ts';
const consentFields=new Set(['privacy','imageConsent','messages']);
const presentationFields=new Set(['id','initials','since','campus','campusId','access']);
export function memberWriteInput(value:unknown,update:boolean){
 if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Cadastro inválido.');
 const source=value as Record<string,unknown>,changes:Record<string,string|boolean|null>={};
 const id=typeof source.id==='string'?source.id:undefined;
 if(update&&(!id||!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)))throw new Error('Identificador de cadastro inválido.');
 if(!update&&id)throw new Error('O identificador é gerado pela plataforma.');
 for(const [key,item] of Object.entries(source)){
  if(presentationFields.has(key))continue;
  if(!(memberFields as readonly string[]).includes(key))throw new Error('Há campos não suportados neste cadastro.');
  if(consentFields.has(key)?typeof item!=='boolean':item!==null&&typeof item!=='string')throw new Error('Revise os tipos dos campos informados.');
  changes[key]=typeof item==='string'&&['phone','emergencyPhone','cpf','zip','birthDate'].includes(key)?normalizeRegistrationField(key,item):item as string|boolean|null;
 }
 if(!update&&(!changes.name||typeof changes.name!=='string'||changes.name.trim().length<2))throw new Error('Informe o nome completo.');
 if('name' in changes&&(typeof changes.name!=='string'||changes.name.trim().length<2))throw new Error('Informe o nome completo.');
 if('campus' in source&&(typeof source.campus!=='string'||!source.campus.trim()))throw new Error('Selecione uma unidade válida.');
 return {id:update?id:undefined,campus:typeof source.campus==='string'?source.campus:undefined,changes};
}
export function memberFormPayload(draft:Record<string,unknown>,initial:Record<string,unknown>|null,changedConsents:readonly string[]){
 const payload:Record<string,unknown>={};
 for(const key of memberFields){
  if(!(key in draft))continue;
  if(consentFields.has(key)&&initial&&!changedConsents.includes(key))continue;
  // Pastoral history is append-only; an empty editor does not erase a note.
  if(key==='notes'&&!draft.notes)continue;
  payload[key]=typeof draft[key]==='string'&&['phone','emergencyPhone','cpf','zip','birthDate'].includes(key)?normalizeRegistrationField(key,draft[key] as string):draft[key];
 }
 if(draft.campus)payload.campus=draft.campus;
 if(initial?.id)payload.id=initial.id;
 return payload;
}
