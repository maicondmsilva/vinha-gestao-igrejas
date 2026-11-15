import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

// Kids › Equipe fixa e repetições: GET ?unit= (visão geral) ou ?unit=&q= (buscar pessoas); POST {action, data}.
// O banco (kids_setup) confere quem configura e todas as regras.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const actions = ['team_save', 'team_remove', 'series_save', 'series_options', 'series_delete', 'series_skip', 'bookable'];
const reasons: [RegExp, string, number][] = [
  [/kids_access_denied/, 'Somente a coordenação do Kids configura equipe e repetições.', 403],
  [/kids_staff_identity_required/, 'A pessoa precisa ser adulta e ter conta ativa no app da igreja.', 400],
  [/kids_version_conflict/, 'Alguém alterou isso agora. Atualize e tente de novo.', 409],
  [/kids_invalid/, 'Revise os dados da repetição ou da equipe.', 400],
];

export const GET = (request: Request) => run(request, null);
export async function POST(request: Request) {
  try {
    return run(request, JSON.parse(new TextDecoder().decode(await boundedBody(request, 16000))));
  } catch {
    return json({error: 'Formato inválido.'}, 400);
  }
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      unit = q.get('unit') || '';
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    let action = q.get('report') === '1' ? 'report' : q.get('q') ? 'people' : 'overview',
      data: Record<string, unknown> = q.get('q') ? {q: (q.get('q') || '').slice(0, 80)} : {};
    if (body) {
      const b = body as {action?: unknown; data?: unknown};
      if (typeof b.action !== 'string' || !actions.includes(b.action) || !b.data || typeof b.data !== 'object' || Array.isArray(b.data))
        return json({error: 'Pedido inválido.'}, 400);
      action = b.action;
      data = b.data as Record<string, unknown>;
    }
    const r = await db(request).rpc('kids_setup', {p_org: a.access!.membership.organization_id, p_unit: unit, p_action: action, p_data: data});
    if (r.error) {
      const hit = reasons.find(([re]) => re.test(r.error!.message));
      return json({error: hit?.[1] || 'Não foi possível concluir agora.'}, hit?.[2] || 503);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
