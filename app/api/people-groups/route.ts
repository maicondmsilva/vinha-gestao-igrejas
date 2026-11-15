import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../lib/private-files';

// Configurações › Grupos (Pastores, Lideranças…): GET lista (ou ?person= com os grupos da pessoa, ?members= com as pessoas do grupo);
// POST {action:'save'|'delete'|'add'|'remove'|'set_person', data}. O banco confere quem pode gerenciar.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const actions = ['save', 'delete', 'add', 'remove', 'set_person'];

export const GET = (request: Request) => run(request, null);
export async function POST(request: Request) {
  try {
    return run(request, JSON.parse(new TextDecoder().decode(await boundedBody(request, 8000))));
  } catch {
    return json({error: 'Formato inválido.'}, 400);
  }
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const org = a.access!.membership.organization_id,
      rpc = (action: string, data: Record<string, unknown>) => db(request).rpc('people_groups', {p_org: org, p_action: action, p_data: data});
    let r;
    if (body) {
      const b = body as {action?: unknown; data?: unknown};
      if (typeof b.action !== 'string' || !actions.includes(b.action) || !b.data || typeof b.data !== 'object' || Array.isArray(b.data))
        return json({error: 'Pedido inválido.'}, 400);
      r = await rpc(b.action, b.data as Record<string, unknown>);
    } else {
      const q = new URL(request.url).searchParams,
        person = q.get('person') || '',
        members = q.get('members') || '';
      if (uuidPattern.test(members)) r = await rpc('members', {id: members});
      else {
        const list = await rpc('list', {});
        if (list.error || !uuidPattern.test(person)) r = list;
        else {
          const mine = await rpc('person', {person});
          return json({...(list.data as object), mine: mine.error ? [] : (mine.data as {items: string[]}).items});
        }
      }
    }
    if (r.error) {
      const denied = /denied/.test(r.error.message);
      return json({error: denied ? 'Somente administração, pastores e secretaria gerenciam grupos.' : 'Revise o nome do grupo.'}, denied ? 403 : 400);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
