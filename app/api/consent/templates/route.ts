import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody} from '../../../lib/private-files';
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const kinds = ['adult_data', 'adult_image', 'kids_guardian', 'kids_image'];
/** Textos dos termos da igreja (padrão e criados pela igreja). Ler, publicar nova versão e retirar: dono, administração e pastores (conferido no banco). */
async function run(request: Request, write: boolean) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Acesso indisponível.'}, 503);
    let data: Record<string, unknown> = {};
    if (write) {
      try {
        data = JSON.parse(new TextDecoder().decode(await boundedBody(request, 12000)));
      } catch {
        return json({error: 'Revise o texto.'}, 400);
      }
      // {kind,title,body[,audience]} publica nova versão; {action:'archive',kind} tira do app um termo criado pela igreja.
      const keys = Object.keys(data || {}).sort().join(',');
      const kindOk = typeof data?.kind === 'string' && (kinds.includes(data.kind) || /^custom_[a-z0-9]{6,40}$/.test(data.kind));
      const save = (keys === 'body,kind,title' || keys === 'audience,body,kind,title') && typeof data.title === 'string' && typeof data.body === 'string';
      const archive = keys === 'action,kind' && data.action === 'archive';
      if (!kindOk || !(save || archive) || (data.audience !== undefined && data.audience !== 'adult' && data.audience !== 'kids'))
        return json({error: 'Revise o texto.'}, 400);
    }
    const r = await db(request).rpc('consent_templates_admin', {p_org: a.access!.membership.organization_id, p_action: write ? (data.action === 'archive' ? 'archive' : 'save') : 'list', p_data: write && data.action === 'archive' ? {kind: data.kind} : data});
    if (r.error)
      return json(
        {error: r.error.code === '42501' ? 'Só dono, administração e pastores editam os termos.' : 'Revise o título (3 a 120 letras) e o texto (20 a 8.000).'},
        r.error.code === '42501' ? 403 : 400,
      );
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
export const GET = (r: Request) => run(r, false);
export const POST = (r: Request) => run(r, true);
