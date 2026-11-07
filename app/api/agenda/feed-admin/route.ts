import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

// Subscription link of a church agenda: GET ?unit= (current), POST {action:'rotate'|'disable'} — agenda managers only.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  return run(request, 'get');
}
export async function POST(request: Request) {
  let action = '';
  try {
    const b = JSON.parse(new TextDecoder().decode(await boundedBody(request, 200))) as {action?: unknown};
    if (b && typeof b === 'object' && Object.keys(b).join() === 'action' && (b.action === 'rotate' || b.action === 'disable')) action = b.action;
  } catch {}
  return action ? run(request, action) : json({error: 'Ação inválida.', code: 'validation'}, 400);
}

async function run(request: Request, action: string) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const unit = new URL(request.url).searchParams.get('unit') || '';
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.', code: 'validation'}, 400);
    const r = await db(request).rpc('agenda_feed_admin', {p_org: a.access!.membership.organization_id, p_unit: unit, p_action: action});
    if (r.error)
      return r.error.code === '42501'
        ? json({error: 'Somente quem gerencia a agenda desta igreja pode criar ou trocar o link.'}, 403)
        : json({error: 'Não foi possível concluir agora.'}, 503);
    const token = (r.data as {token?: string | null})?.token || null,
      origin = new URL(request.url).origin;
    return json({ok: true, url: token ? `${origin}/api/agenda/feed?t=${token}` : null});
  } catch {
    return json({error: 'Conexão interrompida. Atualize antes de repetir.'}, 503);
  }
}
