import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';
import {pushAudienceSchema} from '../../../../shared/contract/push.ts';

// Públicos salvos do push: GET ?unit= lista; POST {unit, action:'save'|'delete', data}. Quem envia push na igreja gerencia.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export const GET = (request: Request) => run(request, null);
export async function POST(request: Request) {
  try {
    return run(request, JSON.parse(new TextDecoder().decode(await boundedBody(request, 8000))));
  } catch {
    return json({error: 'Formato inválido.', code: 'validation'}, 400);
  }
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const b = (body || {}) as {unit?: unknown; action?: unknown; data?: {id?: unknown; name?: unknown; audience?: unknown}};
    const unit = String(body ? b.unit : new URL(request.url).searchParams.get('unit') || '');
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.', code: 'validation'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    let action = 'list',
      data: Record<string, unknown> = {};
    if (body) {
      if (b.action === 'delete' && typeof b.data?.id === 'string' && uuidPattern.test(b.data.id)) {
        action = 'delete';
        data = {id: b.data.id};
      } else if (b.action === 'save') {
        const aud = pushAudienceSchema.safeParse(b.data?.audience);
        const name = typeof b.data?.name === 'string' ? b.data.name.trim() : '';
        if (!aud.success || !Object.keys(aud.data).length) return json({error: 'Escolha ao menos um filtro de público.', code: 'validation'}, 400);
        if (name.length < 2 || name.length > 60)
          return json({error: 'Dê um nome de 2 a 60 letras ao público.', fields: {name: 'Use de 2 a 60 letras.'}, code: 'validation'}, 400);
        action = 'save';
        data = {name, audience: aud.data, ...(typeof b.data?.id === 'string' && uuidPattern.test(b.data.id) ? {id: b.data.id} : {})};
      } else return json({error: 'Ação inválida.', code: 'validation'}, 400);
    }
    const r = await db(request).rpc('push_segments', {p_org: a.access!.membership.organization_id, p_unit: unit, p_action: action, p_data: data});
    if (r.error)
      return json(
        {error: /push_denied/.test(r.error.message) ? 'Seu acesso não permite enviar push nesta igreja.' : 'Revise o nome e os filtros do público.'},
        /push_denied/.test(r.error.message) ? 403 : 400,
      );
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
