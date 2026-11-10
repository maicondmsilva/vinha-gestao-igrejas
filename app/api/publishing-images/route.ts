import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import {boundedBody, uuidPattern} from '../../lib/private-files';
import {imageMime} from '../../../shared/image-files.ts';

// Ministry image library for notices and banners.
// GET ?unit=&page=&search= lists; POST image bytes (?unit=&name=) uploads; POST JSON {action:'update'|'archive', id, data} edits.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const denied = () => json({error: 'Somente quem publica nesta igreja usa o banco de imagens.'}, 403);

async function access(request: Request) {
  const a = await authorizeSupabaseChurch(request, 'units.read');
  if (!a || a.response) return {response: a?.response || json({error: 'Serviço indisponível.'}, 503)};
  const unit = new URL(request.url).searchParams.get('unit') || '';
  if (!uuidPattern.test(unit)) return {response: json({error: 'Selecione uma igreja.', code: 'validation'}, 400)};
  return {org: a.access!.membership.organization_id, unit};
}

export async function GET(request: Request) {
  try {
    const a = await access(request);
    if ('response' in a) return a.response;
    const q = new URL(request.url).searchParams,
      page = Number(q.get('page') || '1'),
      search = (q.get('search') || '').slice(0, 80);
    if (!Number.isInteger(page) || page < 1 || page > 200) return json({error: 'Página inválida.'}, 400);
    const r = await db(request).rpc('publishing_image', {p_org: a.org, p_unit: a.unit, p_action: 'list', p_id: null, p_data: {page, search}});
    if (r.error) return r.error.code === '42501' ? denied() : json({error: 'Banco de imagens indisponível.'}, 503);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Atualize antes de repetir.'}, 503);
  }
}

export async function POST(request: Request) {
  try {
    const a = await access(request);
    if ('response' in a) return a.response;
    const client = db(request);
    if ((request.headers.get('content-type') || '').includes('application/json')) {
      let b: {action?: unknown; id?: unknown; data?: unknown} = {};
      try {
        b = JSON.parse(new TextDecoder().decode(await boundedBody(request, 2000)));
      } catch {}
      const data = b.data && typeof b.data === 'object' && !Array.isArray(b.data) ? (b.data as Record<string, unknown>) : {};
      if (
        !['update', 'archive'].includes(b.action as string) ||
        typeof b.id !== 'string' ||
        !uuidPattern.test(b.id) ||
        Object.keys(b).some((k) => !['action', 'id', 'data'].includes(k))
      )
        return json({error: 'Ação inválida.', code: 'validation'}, 400);
      const r = await client.rpc('publishing_image', {p_org: a.org, p_unit: a.unit, p_action: b.action, p_id: b.id, p_data: b.action === 'update' ? data : {}});
      if (r.error) return r.error.code === '42501' ? denied() : json({error: 'Revise o nome e a descrição da imagem.', code: 'validation'}, 400);
      return json(r.data);
    }
    const name = (new URL(request.url).searchParams.get('name') || 'Imagem').slice(0, 120).trim() || 'Imagem';
    const bytes = await boundedBody(request, 5242880),
      mime = imageMime(bytes);
    if (!mime) return json({error: 'Envie uma imagem JPEG, PNG ou WebP de até 5 MB.', code: 'validation'}, 400);
    const id = crypto.randomUUID(),
      args = {p_org: a.org, p_unit: a.unit, p_id: id};
    const prep = await client.rpc('publishing_image', {...args, p_action: 'prepare', p_data: {mime, bytes: bytes.length, name}});
    if (prep.error)
      return prep.error.code === '42501'
        ? denied()
        : json({error: prep.error.message?.includes('limit') ? 'O banco de imagens está cheio. Arquive imagens antigas.' : 'Imagem recusada.'}, 400);
    const upload = await supabaseAdminClient()
      .storage.from('vinha-publishing-images')
      .upload((prep.data as {path: string}).path, bytes, {contentType: mime, upsert: false});
    if (upload.error) return json({error: 'Imagem não enviada. Tente novamente.'}, 503);
    const done = await client.rpc('publishing_image', {...args, p_action: 'finish', p_data: {}});
    if (done.error) return json({error: 'Imagem sem confirmação. Tente novamente.'}, 503);
    return json({ok: true, id, name, mime, url: '/api/publishing-images/' + id});
  } catch {
    return json({error: 'Não foi possível enviar. Use JPEG, PNG ou WebP de até 5 MB.'}, 400);
  }
}
