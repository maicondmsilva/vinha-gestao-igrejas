import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {supabaseAdminClient} from '../../lib/supabase/server-admin';
import {boundedBody, uuidPattern} from '../../lib/private-files';
import {imageMime} from '../../../shared/image-files.ts';

// Capas das células e redes (cartões do módulo Células).
// GET ?unit=&list=1 → {covers:{'cell:id':versão}} · GET ?unit=&kind=&id= → imagem (link temporário)
// POST ?unit=&kind=&id= (bytes da imagem, até 3 MB) troca a capa · DELETE ?unit=&kind=&id= remove.
// O banco (cell_cover) confere quem vê e quem edita; o arquivo fica em bucket privado.
const bucket = 'vinha-cell-covers';
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const ext: Record<string, string> = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'};

async function context(request: Request, needTarget: boolean) {
  const a = await authorizeSupabaseChurch(request, 'units.read');
  if (!a || a.response) return {response: a?.response || json({error: 'Serviço indisponível.'}, 503)};
  const q = new URL(request.url).searchParams,
    unit = q.get('unit') || '',
    kind = q.get('kind') || '',
    id = q.get('id') || '';
  if (!uuidPattern.test(unit) || !a.access!.membership.units.some((u) => u.id === unit)) return {response: json({error: 'Igreja sem acesso.'}, 403)};
  if (needTarget && (!['cell', 'network'].includes(kind) || !uuidPattern.test(id))) return {response: json({error: 'Capa inválida.'}, 400)};
  return {org: a.access!.membership.organization_id, unit, kind, id, client: db(request)};
}
const fail = (e: {code?: string} | null) =>
  json(
    {error: e?.code === '42501' ? 'Sem permissão para alterar esta capa.' : e?.code === 'P0002' ? 'Cadastro não encontrado.' : 'Não foi possível concluir.'},
    e?.code === '42501' ? 403 : e?.code === 'P0002' ? 404 : 503,
  );

export async function GET(request: Request) {
  try {
    const list = new URL(request.url).searchParams.get('list') === '1';
    const c = await context(request, !list);
    if ('response' in c) return c.response;
    if (list) {
      const r = await c.client.rpc('cell_cover', {p_org: c.org, p_unit: c.unit, p_kind: null, p_id: null, p_action: 'list', p_data: {}});
      return r.error ? fail(r.error) : json(r.data);
    }
    const r = await c.client.rpc('cell_cover', {p_org: c.org, p_unit: c.unit, p_kind: c.kind, p_id: c.id, p_action: 'read', p_data: {}});
    const path = (r.data as {path?: string} | null)?.path;
    if (r.error || !path || path.startsWith('pending/')) return new Response(null, {status: 404});
    const s = await supabaseAdminClient().storage.from(bucket).createSignedUrl(path, 3600);
    if (!s.data?.signedUrl) return new Response(null, {status: 404});
    return new Response(null, {status: 302, headers: {Location: s.data.signedUrl, 'Cache-Control': 'private, max-age=1800'}});
  } catch {
    return new Response(null, {status: 503});
  }
}

export async function POST(request: Request) {
  try {
    const c = await context(request, true);
    if ('response' in c) return c.response;
    const bytes = await boundedBody(request, 3145728),
      mime = imageMime(bytes);
    if (!mime || !ext[mime]) return json({error: 'Envie uma imagem JPEG, PNG ou WebP de até 3 MB.'}, 400);
    const args = {p_org: c.org, p_unit: c.unit, p_kind: c.kind, p_id: c.id};
    const prep = await c.client.rpc('cell_cover', {...args, p_action: 'prepare', p_data: {ext: ext[mime]}});
    if (prep.error) return fail(prep.error);
    const path = (prep.data as {path: string}).path,
      storage = supabaseAdminClient().storage.from(bucket);
    const up = await storage.upload(path, bytes, {contentType: mime, upsert: false, cacheControl: '3600'});
    if (up.error) return json({error: 'Imagem não enviada. Tente novamente.'}, 503);
    const done = await c.client.rpc('cell_cover', {...args, p_action: 'finish', p_data: {path}});
    if (done.error) {
      await storage.remove([path]);
      return fail(done.error);
    }
    const d = done.data as {version: number; old: string | null};
    if (d.old) await storage.remove([d.old]);
    return json({ok: true, version: d.version});
  } catch {
    return json({error: 'Não foi possível enviar. Use JPEG, PNG ou WebP de até 3 MB.'}, 400);
  }
}

export async function DELETE(request: Request) {
  try {
    const c = await context(request, true);
    if ('response' in c) return c.response;
    const r = await c.client.rpc('cell_cover', {p_org: c.org, p_unit: c.unit, p_kind: c.kind, p_id: c.id, p_action: 'remove', p_data: {}});
    if (r.error) return fail(r.error);
    const old = (r.data as {old: string | null}).old;
    if (old) await supabaseAdminClient().storage.from(bucket).remove([old]);
    return json({ok: true});
  } catch {
    return json({error: 'Não foi possível remover.'}, 503);
  }
}
