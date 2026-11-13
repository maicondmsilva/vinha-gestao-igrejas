import { NextResponse } from 'next/server';
import {authorizeSupabaseChurch,type SupabaseChurchAccess} from '../../lib/supabase/church-access';
import {resolveUnitSelection} from '../../lib/unit-integrity';

import {memberWriteInput} from '../../lib/member-write';
import type {Json,Tables} from '../../lib/supabase/database.types';
type PersonRow=Tables<'people'>&{converted_at?:string|null;followup_status?:string|null};
import {peopleQuery,peopleSearchFilter} from '../../lib/people-query';
import {hasAdvanced,peopleFilters} from '../../lib/people-tools';
import type {OperationsClient} from '../../lib/supabase/operations';

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
 let parameters:ReturnType<typeof peopleQuery>;
 try{parameters=peopleQuery(request)}catch(error){return NextResponse.json({error:error instanceof Error?error.message:'Filtros inválidos.'},{status:400})}
 let advanced:ReturnType<typeof peopleFilters>;
 try{advanced=peopleFilters(new URL(request.url).searchParams)}catch(error){return NextResponse.json({error:error instanceof Error?error.message:'Filtros inválidos.'},{status:400})}
 let people:PersonRow[]|null,error:unknown,count:number|null;
 if(hasAdvanced(advanced)&&!parameters.id){
  // Célula, rede, gênero, idade, batismo, marcador e novos convertidos: o banco filtra e devolve a página de ids.
  if(!parameters.unitId)return NextResponse.json({error:'Escolha a igreja para usar estes filtros.'},{status:400});
  const filters={...advanced,...(parameters.q?{q:parameters.q}:{}),...(parameters.status?{status:parameters.status}:{}),...(parameters.group?{group:parameters.group}:{})};
  const found=await (access.client as unknown as OperationsClient).rpc('people_search',{p_org:organizationId,p_unit:parameters.unitId,p_filters:filters,p_page:parameters.page,p_limit:parameters.limit});
  if(found.error)return NextResponse.json({error:found.error.code==='42501'?'Você não pode consultar as pessoas desta igreja.':'Não foi possível carregar os membros.'},{status:found.error.code==='42501'?403:found.error.code==='22023'?400:500});
  const result=found.data as {total:number;ids:string[]};
  const order=new Map(result.ids.map((id,index)=>[id,index]));
  const rows=result.ids.length?await access.client.from('people').select('*').eq('organization_id',organizationId).in('id',result.ids):{data:[],error:null};
  people=((rows.data||[]) as PersonRow[]).sort((a,b)=>(order.get(a.id)??0)-(order.get(b.id)??0));error=rows.error;count=result.total;
 }else{
  let query=access.client.from('people').select('*',{count:'exact'}).eq('organization_id',organizationId);
  if(parameters.unitId)query=query.eq('unit_id',parameters.unitId);
  if(parameters.id)query=query.eq('id',parameters.id);
  if(parameters.status)query=query.eq('journey_status',parameters.status);
  if(parameters.group)query=query.eq('group_name',parameters.group);
  if(parameters.q)query=query.or(peopleSearchFilter(parameters.q));
  ({data:people,error,count}=await query.order('created_at',{ascending:false}).order('id',{ascending:false}).range(parameters.from,parameters.to));
 }
 if(error)return NextResponse.json({error:'Não foi possível carregar os membros.'},{status:500});
 const ids=(people||[]).map(person=>person.id);
 const numbering=ids.length?await(access.client as unknown as OperationsClient).rpc('record_numbering',{p_org:organizationId,p_action:'people',p_data:{ids}}):{data:{codes:{}},error:null};
 if(numbering.error)return NextResponse.json({error:'Não foi possível consultar os códigos de cadastro.'},{status:503});
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
 const records=(people||[]).map(person=>{const address=addressByPerson.get(person.id),contact=contactByPerson.get(person.id),note=noteByPerson.get(person.id);return{
  id:person.id,code:numbering.data?.codes?.[person.id]||null,name:person.full_name,email:person.email||'',phone:person.phone||'',status:person.journey_status,group:person.group_name||'Sem grupo',
  initials:person.full_name.split(' ').map(part=>part[0]).join('').slice(0,2).toUpperCase(),since:displayPostgresDate(person.joined_at),
  birthDate:person.birth_date||'',gender:person.gender||'',maritalStatus:person.marital_status||'',cpf:person.cpf||'',campusId:person.unit_id||'',firstVisit:person.first_visit_at?.slice(0,10)||'',joined:person.joined_at?.slice(0,10)||'',campus:person.unit_id?unitNames.get(person.unit_id)||'':'',
  baptized:person.baptized?'Sim':'Não',baptismDate:person.baptism_date||'',tags:(person.tags||[]).join(', '),access:person.app_role||'member',
  address:address?.street||'',number:address?.number||'',extra:address?.complement||'',district:address?.district||'',city:address?.city||'',state:address?.state||'',zip:address?.postal_code||'',
  emergencyName:contact?.name||'',emergencyPhone:contact?.phone||'',notes:note?.content||'',privacy:consentByPerson.get(person.id+':privacy'),imageConsent:consentByPerson.get(person.id+':image'),messages:consentByPerson.get(person.id+':messages'),
  convertedAt:person.converted_at||'',followupStatus:person.followup_status||'',
 }});
 return NextResponse.json({people:records,pagination:{page:parameters.page,limit:parameters.limit,total:count||0,pages:Math.max(1,Math.ceil((count||0)/parameters.limit))}},{headers:{'Cache-Control':'no-store'}});
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
