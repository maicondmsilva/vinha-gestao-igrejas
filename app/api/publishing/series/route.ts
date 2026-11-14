import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
export const GET = (request: Request) => run(request, false);
export const POST = (request: Request) => run(request, true);
/** Episódios de uma série: consulta (GET) e ordem completa (POST). */
async function run(request: Request, write: boolean) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    let unit = '',
      series = '',
      items: string[] | null = null;
    if (write) {
      try {
        const b = JSON.parse(new TextDecoder().decode(await boundedBody(request, 24000))) as Record<string, unknown>;
        if (
          Object.keys(b).sort().join(',') === 'items,series,unit' &&
          Array.isArray(b.items) &&
          b.items.length <= 500 &&
          b.items.every((x) => typeof x === 'string' && uuidPattern.test(x)) &&
          new Set(b.items).size === b.items.length
        ) {
          unit = String(b.unit);
          series = String(b.series);
          items = b.items as string[];
        }
      } catch {}
    } else {
      const q = new URL(request.url).searchParams;
      unit = q.get('unit') || '';
      series = q.get('series') || '';
    }
    if (!uuidPattern.test(unit) || !uuidPattern.test(series) || (write && !items)) return json({error: 'Revise a série e os episódios.'}, 400);
    const r = await db(request).rpc('publishing_series_episodes', {
      p_org: a.access!.membership.organization_id,
      p_unit: unit,
      p_series: series,
      p_items: items,
    });
    if (r.error)
      return json(
        {
          error:
            r.error.code === '42501'
              ? 'Seu acesso não permite organizar esta série.'
              : r.error.code === '40001'
                ? 'Os episódios mudaram. Atualize a lista antes de salvar.'
                : 'Revise a série e os episódios.',
        },
        r.error.code === '42501' ? 403 : r.error.code === '40001' ? 409 : 400,
      );
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Consulte a lista antes de repetir.'}, 503);
  }
}
