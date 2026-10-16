import { NextResponse } from 'next/server';
import {authorizeSupabaseChurch,supabaseAudit,type SupabaseChurchAccess} from '../../lib/supabase/church-access';
import {resolveUnitSelection} from '../../lib/unit-integrity';

type PersonInput = {
  id?: string; name?: string; email?: string; phone?: string; status?: string; group?: string;
  birthDate?: string; gender?: string; maritalStatus?: string; cpf?: string; campus?: string;
  firstVisit?: string; joined?: string; baptized?: string; baptismDate?: string; tags?: string;
  access?: string; address?: string; number?: string; extra?: string; district?: string; city?: string;
  state?: string; zip?: string; emergencyName?: string; emergencyPhone?: string; notes?: string;
  privacy?: boolean; imageConsent?: boolean; messages?: boolean;
};

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
 const [addresses,contacts,notes,units]=await Promise.all([
  ids.length?access.client.from('person_addresses').select('*').eq('organization_id',organizationId).in('person_id',ids):Promise.resolve({data:empty,error:null}),
  ids.length?access.client.from('emergency_contacts').select('*').eq('organization_id',organizationId).in('person_id',ids):Promise.resolve({data:empty,error:null}),
  ids.length&&['owner','pastor'].includes(access.membership.role)?access.client.from('pastoral_notes').select('*').eq('organization_id',organizationId).in('person_id',ids).order('created_at',{ascending:false}):Promise.resolve({data:empty,error:null}),
  access.client.from('organization_units').select('id,name').eq('organization_id',organizationId),
 ]);
 if([addresses,contacts,notes,units].some(result=>result.error))return NextResponse.json({error:'Não foi possível carregar os dados complementares dos membros.'},{status:503});
 const addressByPerson=new Map((addresses.data||[]).map(item=>[item.person_id,item]));
 const contactByPerson=new Map((contacts.data||[]).map(item=>[item.person_id,item]));
 const noteByPerson=new Map<string,any>();for(const item of notes.data||[])if(!noteByPerson.has(item.person_id))noteByPerson.set(item.person_id,item);
 const unitNames=new Map((units.data||[]).map(unit=>[unit.id,unit.name]));
 return NextResponse.json((people||[]).map(person=>{const address=addressByPerson.get(person.id),contact=contactByPerson.get(person.id),note=noteByPerson.get(person.id);return{
  id:person.id,name:person.full_name,email:person.email||'',phone:person.phone||'',status:person.journey_status,group:person.group_name||'Sem grupo',
  initials:person.full_name.split(' ').map(part=>part[0]).join('').slice(0,2).toUpperCase(),since:displayPostgresDate(person.joined_at),
  birthDate:person.birth_date||'',gender:person.gender||'',maritalStatus:person.marital_status||'',cpf:person.cpf||'',campus:person.unit_id?unitNames.get(person.unit_id)||'':'',
  baptized:person.baptized?'Sim':'Não',baptismDate:person.baptism_date||'',tags:(person.tags||[]).join(', '),access:person.app_role||'member',
  address:address?.street||'',number:address?.number||'',extra:address?.complement||'',district:address?.district||'',city:address?.city||'',state:address?.state||'',zip:address?.postal_code||'',
  emergencyName:contact?.name||'',emergencyPhone:contact?.phone||'',notes:note?.content||'',
 }}));
}

async function supabasePOST(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.write');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,data=await request.json<PersonInput>();
 if(!data.name?.trim())return NextResponse.json({error:'Nome é obrigatório.'},{status:400});
 const organizationId=access.membership.organization_id,unitId=await resolveUnit(access,data.campus),tags=(data.tags||'').split(',').map(tag=>tag.trim()).filter(Boolean);
 if(!unitId)return NextResponse.json({error:'Selecione uma unidade ativa e válida.'},{status:400});
 const {data:person,error}=await access.client.from('people').insert({organization_id:organizationId,unit_id:unitId,full_name:data.name.trim(),birth_date:data.birthDate||null,gender:data.gender||null,marital_status:data.maritalStatus||null,cpf:data.cpf||null,email:data.email||null,phone:data.phone||null,journey_status:data.status||'Visitante',group_name:data.group||'Sem grupo',first_visit_at:data.firstVisit?`${data.firstVisit}T00:00:00Z`:null,joined_at:data.joined?`${data.joined}T00:00:00Z`:new Date().toISOString(),baptized:data.baptized==='Sim',baptism_date:data.baptismDate||null,tags,app_role:data.access||'member',status:'active'}).select('id').single();
 if(error||!person)return NextResponse.json({error:error?.code==='23505'?'Já existe um membro com este e-mail nesta organização.':'Não foi possível cadastrar o membro.'},{status:400});
 const cleanup=async()=>{await access.client.from('people').delete().eq('id',person.id).eq('organization_id',organizationId)};
 const operations=[];
 operations.push(access.client.from('person_addresses').insert({organization_id:organizationId,person_id:person.id,postal_code:data.zip||null,street:data.address||null,number:data.number||null,complement:data.extra||null,district:data.district||null,city:data.city||null,state:data.state||null}));
 if(data.emergencyName&&data.emergencyPhone)operations.push(access.client.from('emergency_contacts').insert({organization_id:organizationId,person_id:person.id,name:data.emergencyName,phone:data.emergencyPhone}));
 if(data.notes&&['owner','pastor'].includes(access.membership.role))operations.push(access.client.from('pastoral_notes').insert({organization_id:organizationId,person_id:person.id,author_user_id:access.userId,content:data.notes,visibility:'pastoral'}));
 operations.push(access.client.from('person_consents').insert([
  {organization_id:organizationId,person_id:person.id,consent_type:'privacy',granted:Boolean(data.privacy),source:'admin',granted_at:data.privacy?new Date().toISOString():null},
  {organization_id:organizationId,person_id:person.id,consent_type:'image',granted:Boolean(data.imageConsent),source:'admin',granted_at:data.imageConsent?new Date().toISOString():null},
  {organization_id:organizationId,person_id:person.id,consent_type:'messages',granted:Boolean(data.messages),source:'admin',granted_at:data.messages?new Date().toISOString():null},
 ]));
 const results=await Promise.all(operations);if(results.some(result=>result.error)){await cleanup();return NextResponse.json({error:'Não foi possível concluir o cadastro do membro.'},{status:400})}
 await supabaseAudit(request,access,'person.created','person',person.id,{name:data.name});
 return NextResponse.json({id:person.id},{status:201});
}

async function supabasePATCH(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.write');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,data=await request.json<PersonInput>();if(!data.id||!data.name?.trim())return NextResponse.json({error:'Cadastro inválido.'},{status:400});
 const organizationId=access.membership.organization_id;
 const {data:original,error:readError}=await access.client.from('people').select('id,unit_id').eq('id',data.id).eq('organization_id',organizationId).maybeSingle();
 if(readError)return NextResponse.json({error:'Não foi possível validar o cadastro.'},{status:503});
 if(!original)return NextResponse.json({error:'Cadastro não encontrado ou sem acesso.'},{status:404});
 const unitId=data.campus===undefined?original.unit_id:await resolveUnit(access,data.campus),tags=(data.tags||'').split(',').map(tag=>tag.trim()).filter(Boolean);
 if(data.campus!==undefined&&!unitId)return NextResponse.json({error:'Selecione uma unidade ativa e válida.'},{status:400});
 const {data:updated,error}=await access.client.from('people').update({unit_id:unitId,full_name:data.name.trim(),birth_date:data.birthDate||null,gender:data.gender||null,marital_status:data.maritalStatus||null,cpf:data.cpf||null,email:data.email||null,phone:data.phone||null,journey_status:data.status||'Visitante',group_name:data.group||'Sem grupo',baptized:data.baptized==='Sim',baptism_date:data.baptismDate||null,tags,app_role:data.access||'member'}).eq('id',data.id).eq('organization_id',organizationId).select('id').maybeSingle();
 if(error)return NextResponse.json({error:'Não foi possível atualizar o cadastro.'},{status:400});
 if(!updated)return NextResponse.json({error:'Cadastro não encontrado ou sem permissão para editar.'},{status:404});
 const {error:addressError}=await access.client.from('person_addresses').upsert({organization_id:organizationId,person_id:data.id,postal_code:data.zip||null,street:data.address||null,number:data.number||null,complement:data.extra||null,district:data.district||null,city:data.city||null,state:data.state||null},{onConflict:'organization_id,person_id'});
 if(addressError)return NextResponse.json({error:'Cadastro atualizado, mas não foi possível salvar o endereço.'},{status:400});
 await supabaseAudit(request,access,'person.updated','person',data.id,{name:data.name});return NextResponse.json({ok:true});
}

export {supabaseGET as GET,supabasePOST as POST,supabasePATCH as PATCH};
