import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {validationBody} from '../../../shared/contract/errors.ts';
import {chatCommandSchema, chatError, chatReadSchema} from '../../../shared/contract/chat.ts';

// Community chat for the panel (moderation and conversation). Members' apps call public.chat directly with their session.
// GET ?action=rooms|messages|message|reports|settings; POST {action, data}. Every rule is checked again in private.chat.
// Not under /api/chat: that path is the old contained D1 chat.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  // Only the chat keys: the panel also sends `tenant` (and previews add their own params).
  const params = new URL(request.url).searchParams,
    q = Object.fromEntries(['action', 'room', 'before', 'id'].flatMap((k) => (params.has(k) ? [[k, params.get(k)]] : [])));
  const c = chatReadSchema.safeParse({action: 'rooms', ...q});
  if (!c.success) return json({error: 'Consulta inválida.', code: 'validation'}, 400);
  const {action, ...data} = c.data;
  return run(request, action, data);
}

export async function POST(request: Request) {
  let body: unknown = null;
  try {
    body = JSON.parse(new TextDecoder().decode(await boundedBody(request, 24000)));
  } catch {}
  const c = chatCommandSchema.safeParse(body);
  if (!c.success) return json(validationBody(c.error, 'Revise os dados enviados.'), 400);
  return run(request, c.data.action, c.data.data);
}

async function run(request: Request, action: string, data: Record<string, unknown>) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const r = await db(request).rpc('chat', {p_org: a.access!.membership.organization_id, p_action: action, p_data: data});
    if (r.error) {
      const hit = chatError(r.error.message);
      if (hit) return json({error: hit.error, ...(hit.field ? {fields: {[hit.field]: hit.error}} : {}), code: hit.code}, hit.status);
      return json(
        {error: r.error.code === '42501' ? 'Seu acesso não permite esta operação.' : 'Não foi possível concluir agora.'},
        r.error.code === '42501' ? 403 : 503,
      );
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Atualize antes de repetir.'}, 503);
  }
}
