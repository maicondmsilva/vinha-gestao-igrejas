import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {uuidPattern} from '../../../lib/private-files';

export async function GET(request: Request) {
  const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      unit = q.get('unit') || '',
      days = Number(q.get('days') || 30);
    if (!uuidPattern.test(unit) || ![7, 30, 90].includes(days)) return json({error: 'Período ou igreja inválidos.'}, 400);
    const r = await db(request).rpc('communication_metrics', {p_org: a.access!.membership.organization_id, p_unit: unit, p_days: days});
    if (r.error) return json({error: r.error.code === '42501' ? 'Seu acesso não permite ver as métricas.' : 'Métricas indisponíveis.'}, r.error.code === '42501' ? 403 : 503);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
