import {uuidPattern} from './private-files.ts';

/** Actions a section may offer, in the order the matrix shows them. */
export const permissionActions=[['view','Ver'],['create','Criar'],['edit','Editar'],['delete','Excluir'],['approve','Aprovar'],['export','Exportar']] as const;
export type PermissionAction=typeof permissionActions[number][0];
export type PermissionSection={code:string;module:string|null;area:string;label:string;actions:PermissionAction[];group_kinds:string[];position:number;owner_only:boolean};
export type PermissionTemplate={code:string;label:string;description:string;items:Record<string,PermissionAction[]>};
export type PermissionGrant={id:string;membership_id:string;permission:string;unit_id:string|null;include_children:boolean;actions:PermissionAction[];group_kind:string|null;group_ids:string[];version:number};

const actionCodes:readonly string[]=permissionActions.map(([a])=>a);
const uuid=(v:unknown)=>{const s=String(v||'');if(!uuidPattern.test(s))throw Error('Cadastro inválido.');return s};
const code=(v:unknown)=>{const s=String(v||'');if(!/^[a-z]+\.[a-z_]+$/.test(s))throw Error('Seção inválida.');return s};
function exact(o:Record<string,unknown>,keys:string[]){for(const k of Object.keys(o))if(!keys.includes(k))throw Error('Campo inválido.')}

/** Strict command for /api/permissions: never forwards unknown fields to the database. */
export function permissionCommand(input:unknown){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Dados inválidos.');
 const raw=input as Record<string,unknown>;exact(raw,['action','data']);
 const action=String(raw.action);
 if(!raw.data||typeof raw.data!=='object'||Array.isArray(raw.data))throw Error('Dados inválidos.');
 const d=raw.data as Record<string,unknown>;
 if(action==='set'){
  exact(d,['membership','permission','unit','includeChildren','actions']);
  if(!Array.isArray(d.actions)||!d.actions.length||d.actions.some(a=>!actionCodes.includes(String(a))))throw Error('Escolha ao menos uma ação.');
  if(typeof d.includeChildren!=='boolean')throw Error('Abrangência inválida.');
  return {action,data:{membership:uuid(d.membership),permission:code(d.permission),unit:d.unit?uuid(d.unit):'',includeChildren:d.includeChildren,actions:[...new Set(d.actions.map(String))]}};
 }
 if(action==='remove'){exact(d,['membership','permission','unit']);return {action,data:{membership:uuid(d.membership),permission:code(d.permission),unit:d.unit?uuid(d.unit):''}}}
 if(action==='apply_template'){exact(d,['membership','template','unit']);const t=String(d.template||'');if(!/^[a-z_]{2,40}$/.test(t))throw Error('Modelo inválido.');return {action,data:{membership:uuid(d.membership),template:t,unit:d.unit?uuid(d.unit):''}}}
 if(action==='clear'){exact(d,['membership']);return {action,data:{membership:uuid(d.membership)}}}
 throw Error('Ação inválida.');
}

/** User type shown in the user sheet, from the current role and explicit grants (P2; P3 makes it editable). */
export function userTypeLabel(role:string,grants:number,unitScoped:boolean){
 if(role==='owner')return 'Dono do ministério';
 if(role==='admin')return unitScoped?'Administrador local':'Administrador do ministério';
 if(role==='member'||role==='viewer')return grants?'Membro de equipe':'Usuário do app';
 return 'Membro de equipe';
}
