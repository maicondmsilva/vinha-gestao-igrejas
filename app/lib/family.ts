// Vínculos familiares: validação dos pedidos, rótulos e mensagens de erro.
import {uuidPattern} from './private-files.ts';
import {relations,relationLabels,type Relation} from '../../shared/relations.ts';
export {relations,relationLabels,type Relation};

export const journeys=['Membro','Em integração','Visitante'] as const;

const id=(v:unknown):v is string=>typeof v==='string'&&uuidPattern.test(v);
const fail=(m='Revise os dados informados.')=>{throw Error(m)};
const only=(o:Record<string,unknown>,keys:string[])=>{for(const k of Object.keys(o))if(!keys.includes(k))fail()};
const date=(v:unknown)=>v===undefined||v===null||v===''?null:typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)?v:fail('Data inválida.');
const relation=(v:unknown)=>typeof v==='string'&&(relations as readonly string[]).includes(v)?v:fail('Escolha o parentesco.');
const bool=(v:unknown)=>v===undefined?false:typeof v==='boolean'?v:fail();

export function familyQuery(request:Request){
 const q=new URL(request.url).searchParams;
 if(q.get('suggest')==='1'){const child=q.get('child');if(!id(child))fail();return{action:'suggest_guardians',data:{child}}}
 const person=q.get('person');if(!id(person))fail();
 return{action:'list',data:{person}};
}

export function familyCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))fail();
 const v=value as Record<string,unknown>;only(v,['action','data']);
 const d=(v.data&&typeof v.data==='object'&&!Array.isArray(v.data)?v.data:fail()) as Record<string,unknown>;
 if(v.action==='remove'){only(d,['id','version']);if(!id(d.id)||!Number.isInteger(d.version))fail();return{action:'remove',data:{id:d.id,version:d.version}}}
 if(v.action==='set'){
  only(d,['id','version','person','related','relation','same_household','marriage_date','copy_address']);
  if(!id(d.person)||!id(d.related)||d.id!==undefined&&!id(d.id)||d.version!==undefined&&!Number.isInteger(d.version))fail();
  return{action:'set',data:{...(d.id?{id:d.id,version:d.version}:{}),person:d.person,related:d.related,relation:relation(d.relation),same_household:bool(d.same_household),marriage_date:date(d.marriage_date),copy_address:bool(d.copy_address)}};
 }
 if(v.action==='quick_create'){
  only(d,['person','name','birth_date','journey','relation','same_household','copy_address']);
  const name=typeof d.name==='string'?d.name.trim():'';
  if(!id(d.person)||name.length<2||name.length>160)fail('Informe o nome do familiar.');
  if(typeof d.journey!=='string'||!(journeys as readonly string[]).includes(d.journey))fail('Escolha a etapa.');
  return{action:'quick_create',data:{person:d.person,name,birth_date:date(d.birth_date),journey:d.journey,relation:relation(d.relation),same_household:bool(d.same_household),copy_address:bool(d.copy_address)}};
 }
 return fail();
}

export function familyFailure(code?:string,_message?:string){
 if(code==='23505')return{status:409,error:'Essa pessoa já está ligada a este cadastro. Edite o vínculo existente.'};
 if(code==='23514')return{status:400,error:'Uma pessoa não pode ser ligada a ela mesma.'};
 if(code==='40001')return{status:409,error:'O vínculo foi alterado por outra pessoa. Atualize e tente de novo.'};
 if(code==='42501')return{status:403,error:'Você não pode alterar a família de uma destas pessoas.'};
 if(code==='P0002')return{status:404,error:'Vínculo não encontrado. Atualize a lista.'};
 if(code==='22023'||code==='22P02'||code==='22007'||code==='22008')return{status:400,error:'Revise os dados informados.'};
 return{status:503,error:'Não foi possível concluir. Atualize e tente de novo.'};
}
