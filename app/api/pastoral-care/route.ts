import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../lib/private-files';
import {careCommand, careError} from '../../../shared/pastoral-care';

// Relatórios de atendimento (com sigilo por permissão) e regras do atendente. O banco confere quem lê e quem escreve.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      unit = q.get('unit') || '',
      person = q.get('person') || '',
      attendant = q.get('attendant') || '';
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja válida.'}, 400);
    const org = a.access!.membership.organization_id;
    const r = uuidPattern.test(attendant)
      ? await db(request).rpc('pastoral_rules', {p_org: org, p_unit: unit, p_attendant: attendant, p_data: {}})
      : uuidPattern.test(person)
        ? await db(request).rpc('pastoral_reports', {p_org: org, p_unit: unit, p_action: 'history', p_data: {person}})
        : null;
    if (!r) return json({error: 'Pedido inválido.'}, 400);
    if (r.error) {
      const e = careError(r.error.code || '', r.error.message || '');
      return json({error: e.error}, e.status);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}

export async function POST(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    let c;
    try {
      c = careCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request, 24000))));
    } catch {
      c = null;
    }
    if (!c) return json({error: 'Revise os campos.'}, 400);
    const org = a.access!.membership.organization_id;
    const r =
      c.action === 'rules'
        ? await db(request).rpc('pastoral_rules', {p_org: org, p_unit: c.unit, p_attendant: String(c.data.attendant || ''), p_data: c.data.rules || {}})
        : await db(request).rpc('pastoral_reports', {p_org: org, p_unit: c.unit, p_action: c.action, p_data: c.data});
    if (r.error) {
      const e = careError(r.error.code || '', r.error.message || '');
      return json({error: e.error}, e.status);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Atualize antes de repetir.'}, 503);
  }
}
