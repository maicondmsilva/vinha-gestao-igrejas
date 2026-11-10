import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  return run(request, null);
}
export async function POST(request: Request) {
  let b: {unit?: unknown; version?: unknown; data?: unknown} | null = null;
  try {
    b = JSON.parse(new TextDecoder().decode(await boundedBody(request, 4000)));
  } catch {}
  return run(request, b);
}

async function run(request: Request, b: {unit?: unknown; version?: unknown; data?: unknown} | null) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const unit = b ? b.unit : new URL(request.url).searchParams.get('unit');
    if (typeof unit !== 'string' || !uuidPattern.test(unit)) return json({error: 'Selecione uma igreja válida.'}, 400);
    if (b && (!Number.isInteger(b.version) || !b.data || typeof b.data !== 'object')) return json({error: 'Revise as automações.'}, 400);
    const r = await db(request).rpc('push_automation', {
      p_org: a.access!.membership.organization_id,
      p_unit: unit,
      p_action: b ? 'save' : 'get',
      p_version: b ? b.version : null,
      p_data: b ? b.data : {},
    });
    if (r.error)
      return json(
        {
          error:
            r.error.code === '42501'
              ? 'Somente dono, pastor ou administração altera as automações.'
              : r.error.code === '40001'
                ? 'As automações mudaram. Atualize a tela.'
                : 'Revise os textos das automações.',
        },
        r.error.code === '42501' ? 403 : r.error.code === '40001' ? 409 : 400,
      );
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
