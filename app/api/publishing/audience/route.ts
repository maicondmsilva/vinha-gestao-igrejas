import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

// Comunicação › aviso, banner ou arquivo só para Grupos: POST {id, groups: uuid[]} (vazio = todos). O banco confere quem publica.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function POST(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    let b: {id?: unknown; groups?: unknown};
    try {
      b = JSON.parse(new TextDecoder().decode(await boundedBody(request, 4000)));
    } catch {
      return json({error: 'Formato inválido.'}, 400);
    }
    if (
      typeof b.id !== 'string' ||
      !uuidPattern.test(b.id) ||
      !Array.isArray(b.groups) ||
      b.groups.length > 20 ||
      b.groups.some((g) => typeof g !== 'string' || !uuidPattern.test(g))
    )
      return json({error: 'Pedido inválido.'}, 400);
    const r = await db(request).rpc('publishing_audience', {p_org: a.access!.membership.organization_id, p_item: b.id, p_groups: b.groups});
    if (r.error)
      return /denied/.test(r.error.message)
        ? json({error: 'Sem permissão para publicar nestas igrejas.'}, 403)
        : json({error: /changed/.test(r.error.message) ? 'Salve o rascunho antes de escolher os grupos.' : 'Revise os grupos escolhidos.'}, 400);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
