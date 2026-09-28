import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize } from '../_auth';

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

export async function GET(request:Request) {
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

export async function POST(request: Request) {
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

export async function PATCH(request: Request) {
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
