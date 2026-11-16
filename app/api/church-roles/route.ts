import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../lib/private-files';
import {rolesActions, rolesError} from '../../../shared/church-roles';

// Cargos e funções: GET catálogo (ou ?person= com os cargos e grupos da pessoa, ?q= busca de grupos);
// POST {action, data}. O banco confere quem gerencia o catálogo, quem edita a pessoa e quem confirma acessos.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export const GET = (request: Request) => run(request, null);
export async function POST(request: Request) {
  try {
    return run(request, JSON.parse(new TextDecoder().decode(await boundedBody(request, 12000))));
  } catch {
    return json({error: 'Formato inválido.'}, 400);
  }
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const org = a.access!.membership.organization_id,
      rpc = (action: string, data: Record<string, unknown>) => db(request).rpc('church_roles', {p_org: org, p_action: action, p_data: data});
    let r;
    if (body) {
      const b = body as {action?: unknown; data?: unknown};
      if (typeof b.action !== 'string' || !rolesActions.includes(b.action as never) || !b.data || typeof b.data !== 'object' || Array.isArray(b.data))
        return json({error: 'Pedido inválido.'}, 400);
      r = await rpc(b.action, b.data as Record<string, unknown>);
    } else {
      const q = new URL(request.url).searchParams,
        person = q.get('person') || '',
        search = q.get('q');
      if (uuidPattern.test(person)) r = await rpc('person', {person});
      else if (search !== null) r = await rpc('groups.search', {q: search.slice(0, 80)});
      else if (q.get('view') === 'ministries') r = await rpc('ministries', {});
      else if (q.get('view') === 'access') r = await rpc('access.list', {});
      else if (q.get('view') === 'review') r = await rpc('review.list', {});
      else r = await rpc('catalog', {});
    }
    if (r.error) {
      const e = rolesError(r.error.code || '', r.error.message || '');
      return json({error: e.message}, e.status);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Tente novamente.'}, 503);
  }
}
