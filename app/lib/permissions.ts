import {uuidPattern} from './private-files.ts';

/** Actions a section may offer, in the order the matrix shows them. */
export const permissionActions=[['view','Ver'],['create','Criar'],['edit','Editar'],['delete','Excluir'],['approve','Aprovar'],['export','Exportar']] as const;
/** Kinds of group a section may be limited to (Células, Escalas, Kids). */
export const groupKinds=[['cell','Células'],['network','Redes'],['scale_team','Equipes de escala'],['kids_class','Turmas Kids']] as const;
export type GroupOption={id:string;name:string;unit:string};
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
  exact(d,['membership','permission','unit','includeChildren','actions','groupKind','groups']);
  const kind=d.groupKind?String(d.groupKind):'';if(kind&&!groupKinds.some(([k])=>k===kind))throw Error('Tipo de grupo inválido.');
  const groups=Array.isArray(d.groups)?[...new Set(d.groups.map(String))]:[];if(groups.some(g=>!uuidPattern.test(g))||groups.length>200)throw Error('Grupo inválido.');if(Boolean(kind)!==(groups.length>0))throw Error('Escolha ao menos um grupo ou tire o limite.');
  if(!Array.isArray(d.actions)||!d.actions.length||d.actions.some(a=>!actionCodes.includes(String(a))))throw Error('Escolha ao menos uma ação.');
  if(typeof d.includeChildren!=='boolean')throw Error('Abrangência inválida.');
  return {action,data:{membership:uuid(d.membership),permission:code(d.permission),unit:d.unit?uuid(d.unit):'',includeChildren:d.includeChildren,actions:[...new Set(d.actions.map(String))],...(kind?{groupKind:kind,groups}:{})}};
 }
 if(action==='remove'){exact(d,['membership','permission','unit']);return {action,data:{membership:uuid(d.membership),permission:code(d.permission),unit:d.unit?uuid(d.unit):''}}}
 if(action==='apply_template'){exact(d,['membership','template','unit']);const t=String(d.template||'');if(!/^[a-z_]{2,40}$/.test(t))throw Error('Modelo inválido.');return {action,data:{membership:uuid(d.membership),template:t,unit:d.unit?uuid(d.unit):''}}}
 if(action==='clear'){exact(d,['membership']);return {action,data:{membership:uuid(d.membership)}}}
 if(action==='save_custom_template'){exact(d,['id','name','description','items']);const name=String(d.name||'').trim(),description=String(d.description||'').trim();
  if(name.length<2||name.length>60)throw Error('Dê ao modelo um nome de 2 a 60 letras.');if(description.length>240)throw Error('Descrição muito longa.');
  if(!d.items||typeof d.items!=='object'||Array.isArray(d.items))throw Error('Marque ao menos uma seção no modelo.');
  const items:Record<string,string[]>={};for(const [k,v] of Object.entries(d.items as Record<string,unknown>)){code(k);if(!Array.isArray(v)||!v.length||v.some(a=>!actionCodes.includes(String(a))))throw Error('Ações inválidas no modelo.');items[k]=[...new Set(v.map(String))]}
  if(!Object.keys(items).length)throw Error('Marque ao menos uma seção no modelo.');
  return {action,data:{...(d.id?{id:uuid(d.id)}:{}),name,description,items}}}
 if(action==='delete_custom_template'){exact(d,['id']);return {action,data:{id:uuid(d.id)}}}
 if(action==='apply_custom_template'){exact(d,['membership','template','units']);const units=Array.isArray(d.units)?[...new Set(d.units.map(String))]:[];if(units.some(u=>!uuidPattern.test(u))||units.length>200)throw Error('Igreja inválida.');return {action,data:{membership:uuid(d.membership),template:uuid(d.template),units}}}
 throw Error('Ação inválida.');
}

/** Tipos de usuário que a igreja escolhe. "Equipe" é automático: membro com alguma permissão ou função. */
export const userTypes=[['admin','Administrador'],['pastor','Pastor'],['team','Equipe'],['member','Membro (usuário do app)']] as const;
export type UserType=typeof userTypes[number][0]|'owner';
/** Papéis antigos (secretaria, liderança, tesouraria) continuam valendo e aparecem como Equipe. */
export const legacyTeamRoles=['secretary','leader','finance'];
export function userType(role:string,team:boolean):UserType{
 if(role==='owner'||role==='admin'||role==='pastor')return role;
 if(legacyTeamRoles.includes(role)||team)return 'team';
 return 'member';
}
export function userTypeName(role:string,team:boolean){const t=userType(role,team);return t==='owner'?'Dono do ministério':userTypes.find(([k])=>k===t)![1]}
/** Papel gravado ao escolher um tipo: Equipe mantém o papel antigo ou fica membro (o acesso vem das permissões). */
export function roleForType(type:string,current:string){
 if(type==='admin'||type==='pastor')return type;
 if(type==='team')return legacyTeamRoles.includes(current)?current:'member';
 return 'member';
}
/** Compatibilidade: rótulo antigo da ficha. */
export function userTypeLabel(role:string,grants:number,_unitScoped:boolean){return userTypeName(role,grants>0)}
