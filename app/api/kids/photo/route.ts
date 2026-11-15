import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {uuidPattern} from '../../../lib/private-files';

// Foto da criança para quem opera o Kids nesta igreja: GET ?unit=&profile= devolve um link temporário (10 min).
// O banco (kids_child_photo) confere a permissão; o arquivo continua privado.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      unit = q.get('unit') || '',
      profile = q.get('profile') || '';
    if (!uuidPattern.test(unit) || !uuidPattern.test(profile)) return json({url: ''}, 400);
    const r = await db(request).rpc('kids_child_photo', {p_org: a.access!.membership.organization_id, p_unit: unit, p_profile: profile});
    const path = String(r.data || '');
    if (r.error || !path.startsWith('member-photos/')) return json({url: ''});
    const s = await supabaseAdminClient()
      .storage.from('member-photos')
      .createSignedUrl(path.replace(/^member-photos\//, ''), 600);
    return json({url: s.data?.signedUrl || ''});
  } catch {
    return json({url: ''});
  }
}
