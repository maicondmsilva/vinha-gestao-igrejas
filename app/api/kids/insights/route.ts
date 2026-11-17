import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {uuidPattern} from '../../../lib/private-files';

// Kids · aniversariantes (próximos 7 dias) e crianças ausentes (vinham e não vêm há 4 semanas).
// GET ?unit=&kind=birthdays|absent. O banco (kids_insights) confere quem opera o Kids nesta igreja.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      unit = q.get('unit') || '',
      kind = q.get('kind') || '';
    if (!uuidPattern.test(unit) || !['birthdays', 'absent'].includes(kind)) return json({error: 'Consulta inválida.'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    const r = await db(request).rpc('kids_insights', {p_org: a.access!.membership.organization_id, p_unit: unit, p_kind: kind});
    if (r.error)
      return json(
        {error: r.error.code === '42501' ? 'Sem acesso ao Kids desta igreja.' : 'Não foi possível consultar agora.'},
        r.error.code === '42501' ? 403 : 503,
      );
    const items = (r.data as {items?: unknown})?.items;
    return json({items: Array.isArray(items) ? items : []});
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
