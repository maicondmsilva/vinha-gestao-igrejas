import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize } from '../_auth';
import {authorizeSupabaseChurch,supabaseAudit,type SupabaseChurchAccess} from '../../lib/supabase/church-access';
import {supabaseServerConfigured} from '../../lib/supabase/request';

type PersonInput = {
  id?: string; name?: string; email?: string; phone?: string; status?: string; group?: string;
  birthDate?: string; gender?: string; maritalStatus?: string; cpf?: string; campus?: string;
  firstVisit?: string; joined?: string; baptized?: string; baptismDate?: string; tags?: string;
  access?: string; address?: string; number?: string; extra?: string; district?: string; city?: string;
  state?: string; zip?: string; emergencyName?: string; emergencyPhone?: string; notes?: string;
  privacy?: boolean; imageConsent?: boolean; messages?: boolean;
};

function displayDate(value: number | null) {
  if (!value) return 'Hoje';
  return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(new Date(value));
}

function displayPostgresDate(value:string|null){
 if(!value)return 'Hoje';
 return new Intl.DateTimeFormat('pt-BR',{day:'2-digit',month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(value));
}

async function resolveUnit(access:SupabaseChurchAccess,campus?:string){
 if(!campus)return access.membership.default_unit_id||access.membership.units[0]?.id||null;
 const local=access.membership.units.find(unit=>unit.id===campus||unit.name.toLocaleLowerCase('pt-BR')===campus.toLocaleLowerCase('pt-BR'));
 if(local)return local.id;
 const {data}=await access.client.from('organization_units').select('id,name').eq('organization_id',access.membership.organization_id).ilike('name',campus).limit(1).maybeSingle();
 return data?.id||access.membership.default_unit_id||null;
}

async function supabaseGET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,organizationId=access.membership.organization_id;
 const {data:people,error}=await access.client.from('people').select('*').eq('organization_id',organizationId).order('created_at',{ascending:false});
 if(error)return NextResponse.json({error:'Não foi possível carregar os membros.'},{status:500});
 const ids=(people||[]).map(person=>person.id);
 const empty:any[]=[];
 const [addresses,contacts,notes,units]=await Promise.all([
  ids.length?access.client.from('person_addresses').select('*').in('person_id',ids):Promise.resolve({data:empty,error:null}),
  ids.length?access.client.from('emergency_contacts').select('*').in('person_id',ids):Promise.resolve({data:empty,error:null}),
  ids.length?access.client.from('pastoral_notes').select('*').in('person_id',ids).order('created_at',{ascending:false}):Promise.resolve({data:empty,error:null}),
  access.client.from('organization_units').select('id,name').eq('organization_id',organizationId),
 ]);
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
 const {data:person,error}=await access.client.from('people').insert({organization_id:organizationId,unit_id:unitId,full_name:data.name.trim(),birth_date:data.birthDate||null,gender:data.gender||null,marital_status:data.maritalStatus||null,cpf:data.cpf||null,email:data.email||null,phone:data.phone||null,journey_status:data.status||'Visitante',group_name:data.group||'Sem grupo',first_visit_at:data.firstVisit?`${data.firstVisit}T00:00:00Z`:null,joined_at:data.joined?`${data.joined}T00:00:00Z`:new Date().toISOString(),baptized:data.baptized==='Sim',baptism_date:data.baptismDate||null,tags,app_role:data.access||'member',status:'active'}).select('id').single();
 if(error||!person)return NextResponse.json({error:error?.code==='23505'?'Já existe um membro com este e-mail nesta organização.':'Não foi possível cadastrar o membro.'},{status:400});
 const cleanup=async()=>{await access.client.from('people').delete().eq('id',person.id)};
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
 const organizationId=access.membership.organization_id,unitId=await resolveUnit(access,data.campus),tags=(data.tags||'').split(',').map(tag=>tag.trim()).filter(Boolean);
 const {error}=await access.client.from('people').update({unit_id:unitId,full_name:data.name.trim(),birth_date:data.birthDate||null,gender:data.gender||null,marital_status:data.maritalStatus||null,cpf:data.cpf||null,email:data.email||null,phone:data.phone||null,journey_status:data.status||'Visitante',group_name:data.group||'Sem grupo',baptized:data.baptized==='Sim',baptism_date:data.baptismDate||null,tags,app_role:data.access||'member'}).eq('id',data.id).eq('organization_id',organizationId);
 if(error)return NextResponse.json({error:'Não foi possível atualizar o cadastro.'},{status:400});
 const {error:addressError}=await access.client.from('person_addresses').upsert({organization_id:organizationId,person_id:data.id,postal_code:data.zip||null,street:data.address||null,number:data.number||null,complement:data.extra||null,district:data.district||null,city:data.city||null,state:data.state||null},{onConflict:'organization_id,person_id'});
 if(addressError)return NextResponse.json({error:'Cadastro atualizado, mas não foi possível salvar o endereço.'},{status:400});
 await supabaseAudit(request,access,'person.updated','person',data.id,{name:data.name});return NextResponse.json({ok:true});
}

async function legacyGET(request:Request) {
  const auth=await authorize(request,'people.read'); if(auth.response)return auth.response;
  const churchId=auth.session!.churchId;
  const result = await env.DB.prepare(`SELECT p.*, a.postal_code, a.street, a.number, a.complement,
    a.district, a.city, a.state, e.name emergency_name, e.phone emergency_phone,
    n.content pastoral_notes
    FROM people p
    LEFT JOIN person_addresses a ON a.person_id = p.id AND a.church_id = p.church_id
    LEFT JOIN emergency_contacts e ON e.person_id = p.id AND e.church_id = p.church_id
    LEFT JOIN pastoral_notes n ON n.person_id = p.id AND n.church_id = p.church_id
    WHERE p.church_id = ? ORDER BY p.created_at DESC`).bind(churchId).all<Record<string, unknown>>();

  return NextResponse.json(result.results.map(row => ({
    id: String(row.id), name: String(row.full_name), email: String(row.email ?? ''), phone: String(row.phone ?? ''),
    status: String(row.journey_status), group: String(row.group_name ?? 'Sem grupo'),
    initials: String(row.full_name).split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase(),
    since: displayDate(row.joined_at as number | null), birthDate: row.birth_date ?? '', gender: row.gender ?? '',
    maritalStatus: row.marital_status ?? '', cpf: row.cpf ?? '', campus: row.campus ?? '',
    baptized: row.baptized ? 'Sim' : 'Não', baptismDate: row.baptism_date ?? '',
    tags: JSON.parse(String(row.tags ?? '[]')).join(', '), access: row.app_role ?? 'member',
    address: row.street ?? '', number: row.number ?? '', extra: row.complement ?? '', district: row.district ?? '',
    city: row.city ?? '', state: row.state ?? '', zip: row.postal_code ?? '', emergencyName: row.emergency_name ?? '',
    emergencyPhone: row.emergency_phone ?? '', notes: row.pastoral_notes ?? '',
  })));
}

async function legacyPOST(request: Request) {
  const auth=await authorize(request,'people.write'); if(auth.response)return auth.response;
  const churchId=auth.session!.churchId;
  const data = await request.json<PersonInput>();
  if (!data.name?.trim()) return NextResponse.json({ error: 'Nome é obrigatório.' }, { status: 400 });
  const id = crypto.randomUUID();
  const now = Date.now();
  const tags = (data.tags ?? '').split(',').map(tag => tag.trim()).filter(Boolean);
  const joinedAt = data.joined ? Date.parse(`${data.joined}T00:00:00Z`) : now;
  const firstVisitAt = data.firstVisit ? Date.parse(`${data.firstVisit}T00:00:00Z`) : null;

  const statements = [
    env.DB.prepare(`INSERT INTO people (id, church_id, full_name, birth_date, gender, marital_status, cpf, email,
      phone, journey_status, campus, group_name, first_visit_at, joined_at, baptized, baptism_date, tags, app_role, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)`)
      .bind(id, churchId, data.name.trim(), data.birthDate || null, data.gender || null, data.maritalStatus || null,
        data.cpf || null, data.email || null, data.phone || null, data.status || 'Visitante', data.campus || null,
        data.group || 'Sem grupo', firstVisitAt, joinedAt, data.baptized === 'Sim' ? 1 : 0,
        data.baptismDate || null, JSON.stringify(tags), data.access || 'member', now),
    env.DB.prepare(`INSERT INTO person_addresses (id, church_id, person_id, postal_code, street, number, complement,
      district, city, state, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(crypto.randomUUID(), churchId, id, data.zip || null, data.address || null, data.number || null,
        data.extra || null, data.district || null, data.city || null, data.state || null, now),
  ];
  if (data.emergencyName && data.emergencyPhone) statements.push(env.DB.prepare(`INSERT INTO emergency_contacts
    (id, church_id, person_id, name, phone, created_at) VALUES (?, ?, ?, ?, ?, ?)`)
    .bind(crypto.randomUUID(), churchId, id, data.emergencyName, data.emergencyPhone, now));
  if (data.notes) statements.push(env.DB.prepare(`INSERT INTO pastoral_notes
    (id, church_id, person_id, author_user_id, content, visibility, created_at) VALUES (?, ?, ?, ?, ?, 'pastoral', ?)`)
    .bind(crypto.randomUUID(), churchId, id, auth.session!.id, data.notes, now));
  for (const [type, granted] of [['privacy', data.privacy], ['image', data.imageConsent], ['messages', data.messages]] as const) {
    statements.push(env.DB.prepare(`INSERT INTO person_consents
      (id, church_id, person_id, consent_type, granted, source, granted_at) VALUES (?, ?, ?, ?, ?, 'admin', ?)`)
      .bind(crypto.randomUUID(), churchId, id, type, granted ? 1 : 0, granted ? now : null));
  }
  await env.DB.batch(statements);
  await audit(request,auth.session!,'person.created','person',id,{name:data.name});
  return NextResponse.json({ id }, { status: 201 });
}

async function legacyPATCH(request: Request) {
  const auth=await authorize(request,'people.write'); if(auth.response)return auth.response;
  const churchId=auth.session!.churchId;
  const data = await request.json<PersonInput>();
  if (!data.id || !data.name?.trim()) return NextResponse.json({ error: 'Cadastro inválido.' }, { status: 400 });
  const tags = (data.tags ?? '').split(',').map(tag => tag.trim()).filter(Boolean);
  await env.DB.batch([
    env.DB.prepare(`UPDATE people SET full_name=?, birth_date=?, gender=?, marital_status=?, cpf=?, email=?, phone=?,
      journey_status=?, campus=?, group_name=?, baptized=?, baptism_date=?, tags=?, app_role=? WHERE id=? AND church_id=?`)
      .bind(data.name.trim(), data.birthDate || null, data.gender || null, data.maritalStatus || null, data.cpf || null,
        data.email || null, data.phone || null, data.status || 'Visitante', data.campus || null, data.group || 'Sem grupo',
        data.baptized === 'Sim' ? 1 : 0, data.baptismDate || null, JSON.stringify(tags), data.access || 'member', data.id, churchId),
    env.DB.prepare(`UPDATE person_addresses SET postal_code=?, street=?, number=?, complement=?, district=?, city=?, state=?
      WHERE person_id=? AND church_id=?`).bind(data.zip || null, data.address || null, data.number || null, data.extra || null,
        data.district || null, data.city || null, data.state || null, data.id, churchId),
  ]);
  await audit(request,auth.session!,'person.updated','person',data.id,{name:data.name});
  return NextResponse.json({ ok: true });
}

export async function GET(request:Request){return supabaseServerConfigured?supabaseGET(request):legacyGET(request)}
export async function POST(request:Request){return supabaseServerConfigured?supabasePOST(request):legacyPOST(request)}
export async function PATCH(request:Request){return supabaseServerConfigured?supabasePATCH(request):legacyPATCH(request)}
