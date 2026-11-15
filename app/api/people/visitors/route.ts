import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {uuidPattern} from '../../../lib/private-files';

// Visitantes: GET ?unit= (cadastros dos últimos 7 dias) ou ?person= (visitas de uma pessoa, para a ficha).
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'people.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      org = a.access!.membership.organization_id,
      unit = q.get('unit') || '',
      person = q.get('person') || '';
    if (uuidPattern.test(person)) {
      const r = await db(request).rpc('person_visits', {p_org: org, p_person: person});
      return r.error ? json({items: []}) : json(r.data);
    }
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.', code: 'validation'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    const r = await db(request).rpc('visitor_staff', {p_org: org, p_unit: unit, p_action: 'recent', p_data: {}});
    if (r.error)
      return json({error: /visitor_denied/.test(r.error.message) ? 'Sem permissão para ver visitantes desta igreja.' : 'Não foi possível carregar.'}, 403);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
