import { NextResponse } from 'next/server';
import {authorizeSupabaseChurch,type SupabaseChurchAccess} from '../../lib/supabase/church-access';
import {resolveUnitSelection} from '../../lib/unit-integrity';

import {memberWriteInput} from '../../lib/member-write';
import type {Json} from '../../lib/supabase/database.types';

function displayPostgresDate(value:string|null){
 if(!value)return 'Hoje';
 return new Intl.DateTimeFormat('pt-BR',{day:'2-digit',month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(value));
}

async function resolveUnit(access:SupabaseChurchAccess,campus?:string){
 const {data,error}=await access.client.from('organization_units').select('id,name').eq('organization_id',access.membership.organization_id).eq('status','active');
 if(error)return null;
 return resolveUnitSelection(data||[],campus,access.membership.default_unit_id);
}

async function supabaseGET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,organizationId=access.membership.organization_id;
 const {data:people,error}=await access.client.from('people').select('*').eq('organization_id',organizationId).order('created_at',{ascending:false});
 if(error)return NextResponse.json({error:'Não foi possível carregar os membros.'},{status:500});
 const ids=(people||[]).map(person=>person.id);
 const empty:any[]=[];
 const [addresses,contacts,notes,units,consents]=await Promise.all([
  ids.length?access.client.from('person_addresses').select('*').eq('organization_id',organizationId).in('person_id',ids):Promise.resolve({data:empty,error:null}),
  ids.length?access.client.from('emergency_contacts').select('*').eq('organization_id',organizationId).in('person_id',ids).order('created_at').order('id'):Promise.resolve({data:empty,error:null}),
  ids.length&&['owner','pastor'].includes(access.membership.role)?access.client.from('pastoral_notes').select('*').eq('organization_id',organizationId).in('person_id',ids).order('created_at',{ascending:false}):Promise.resolve({data:empty,error:null}),
  access.client.from('organization_units').select('id,name').eq('organization_id',organizationId),
  ids.length?access.client.from('person_consents').select('id,person_id,consent_type,granted,created_at').eq('organization_id',organizationId).in('person_id',ids).order('created_at',{ascending:false}).order('id',{ascending:false}):Promise.resolve({data:empty,error:null}),
 ]);
 if([addresses,contacts,notes,units,consents].some(result=>result.error))return NextResponse.json({error:'Não foi possível carregar os dados complementares dos membros.'},{status:503});
 const addressByPerson=new Map((addresses.data||[]).map(item=>[item.person_id,item]));
 const contactByPerson=new Map<string,any>();for(const item of contacts.data||[])if(!contactByPerson.has(item.person_id))contactByPerson.set(item.person_id,item);
 const consentByPerson=new Map<string,boolean>();for(const item of consents.data||[]){const key=item.person_id+':'+item.consent_type;if(!consentByPerson.has(key))consentByPerson.set(key,item.granted)}
 const noteByPerson=new Map<string,any>();for(const item of notes.data||[])if(!noteByPerson.has(item.person_id))noteByPerson.set(item.person_id,item);
 const unitNames=new Map((units.data||[]).map(unit=>[unit.id,unit.name]));
 return NextResponse.json((people||[]).map(person=>{const address=addressByPerson.get(person.id),contact=contactByPerson.get(person.id),note=noteByPerson.get(person.id);return{
  id:person.id,name:person.full_name,email:person.email||'',phone:person.phone||'',status:person.journey_status,group:person.group_name||'Sem grupo',
  initials:person.full_name.split(' ').map(part=>part[0]).join('').slice(0,2).toUpperCase(),since:displayPostgresDate(person.joined_at),
  birthDate:person.birth_date||'',gender:person.gender||'',maritalStatus:person.marital_status||'',cpf:person.cpf||'',campusId:person.unit_id||'',firstVisit:person.first_visit_at?.slice(0,10)||'',joined:person.joined_at?.slice(0,10)||'',campus:person.unit_id?unitNames.get(person.unit_id)||'':'',
  baptized:person.baptized?'Sim':'Não',baptismDate:person.baptism_date||'',tags:(person.tags||[]).join(', '),access:person.app_role||'member',
  address:address?.street||'',number:address?.number||'',extra:address?.complement||'',district:address?.district||'',city:address?.city||'',state:address?.state||'',zip:address?.postal_code||'',
  emergencyName:contact?.name||'',emergencyPhone:contact?.phone||'',notes:note?.content||'',privacy:consentByPerson.get(person.id+':privacy'),imageConsent:consentByPerson.get(person.id+':image'),messages:consentByPerson.get(person.id+':messages'),
 }}));
}

function saveFailure(code?:string){
 const status=code==='P0002'?404:code==='42501'||code==='28000'?403:code==='23505'?409:['22023','22P02','22007','22008','23514','23502'].includes(code||'')?400:503;
 const error=status===404?'Cadastro não encontrado ou sem acesso.':status===403?'Você não possui permissão para salvar estes dados.':status===409?'Já existe um cadastro com este e-mail nesta organização.':status===400?'Revise os dados informados. O cadastro não foi alterado.':'Não foi possível confirmar a gravação. Atualize a lista antes de tentar novamente.';
 return NextResponse.json({error},{status});
}
async function saveMember(request:Request,update:boolean){
 const auth=await authorizeSupabaseChurch(request,'people.write');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!;
 let input:ReturnType<typeof memberWriteInput>;
 try{input=memberWriteInput(await request.json(),update)}catch(error){return NextResponse.json({error:error instanceof Error?error.message:'Cadastro inválido.'},{status:400})}
 let unitId:string|null=null;
 if(!update||input.campus!==undefined){
  unitId=await resolveUnit(access,input.campus);
  if(!unitId)return NextResponse.json({error:'Selecione uma unidade ativa e autorizada.'},{status:400});
 }
 const {data,error}=await access.client.rpc('save_person_record',{p_organization:access.membership.organization_id,p_unit:unitId,p_person:input.id||null,p_data:input.changes as Json});
 if(error)return saveFailure(error.code);
 if(typeof data!=='string'||!data)return saveFailure();
 return NextResponse.json(update?{ok:true,id:data}:{id:data},{status:update?200:201});
}
async function supabasePOST(request:Request){return saveMember(request,false)}
async function supabasePATCH(request:Request){return saveMember(request,true)}
export {supabaseGET as GET,supabasePOST as POST,supabasePATCH as PATCH};
