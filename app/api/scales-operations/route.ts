import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../lib/private-files';
import {scaleOperationError} from '../../../shared/scale-operations';
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
async function run(request: Request, write: boolean) {
  const auth = await authorizeSupabaseChurch(request, 'units.read');
  if (!auth || auth.response) return auth?.response || json({error: 'Acesso indisponível.'}, 503);
  try {
    let unit: string, action: string, data: Record<string, unknown>;
    try {
      if (write) {
        const b = JSON.parse(new TextDecoder().decode(await boundedBody(request, 16000)));
        if (!b || Object.keys(b).some((k) => !['unit', 'action', 'data'].includes(k))) throw Error();
        unit = b.unit;
        action = b.action;
        data = b.data;
      } else {
        const p = new URL(request.url).searchParams;
        for (const k of p.keys())
          if (!['unit', 'action', 'service', 'team', 'role', 'ordinal', 'page', 'search', 'scope', 'tenant'].includes(k) || p.getAll(k).length !== 1)
            throw Error();
        unit = p.get('unit') || '';
        action = p.get('action') || 'view';
        data = {};
        for (const [k, v] of p) if (!['unit', 'action', 'tenant'].includes(k)) data[k] = ['page', 'ordinal'].includes(k) ? Number(v) : v;
      }
      if (
        !uuidPattern.test(unit) ||
        !data ||
        typeof data !== 'object' ||
        Array.isArray(data) ||
        ![
          'view',
          'pending',
          'settings',
          'suggest',
          ...(write ? ['qualify', 'policy', 'publish', 'revise', 'cancel', 'close', 'reply', 'replace', 'fill', 'presence', 'decision'] : []),
        ].includes(action) ||
        Object.keys(data).some(
          (k) =>
            ![
              'service',
              'team',
              'id',
              'member',
              'role',
              'ordinal',
              'page',
              'search',
              'scope',
              'request',
              'token',
              'version',
              'reason',
              'override',
              'response',
              'presence',
              'active',
              'parallel',
              'travel',
              'decision',
            ].includes(k),
        )
      )
        throw Error();
      for (const k of ['service', 'team', 'id', 'member', 'role', 'request'])
        if (data[k] && (typeof data[k] !== 'string' || !uuidPattern.test(data[k] as string))) throw Error();
      if (write && !['view', 'pending', 'settings', 'suggest'].includes(action) && !data.request) throw Error();
    } catch {
      return json({error: 'Selecione a igreja e revise os dados da operação.'}, 400);
    }
    if (!auth.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    const r = await (auth.access!.client as unknown as OperationsClient).rpc('scale_operations', {
      p_org: auth.access!.membership.organization_id,
      p_unit: unit,
      p_action: action,
      p_data: data,
    });
    if (r.error)
      return json({error: scaleOperationError(r.error.message, r.error.code)}, r.error.code === '42501' ? 403 : r.error.code === '40001' ? 409 : 400);
    return json(r.data);
  } catch {
    return json({error: 'Não foi possível confirmar. Atualize a escala antes de repetir.'}, 503);
  }
}
export const GET = (r: Request) => run(r, false);
export const POST = (r: Request) => run(r, true);
