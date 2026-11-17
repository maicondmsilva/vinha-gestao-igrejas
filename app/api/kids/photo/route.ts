import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {uuidPattern} from '../../../lib/private-files';

// Foto da criança para quem opera o Kids nesta igreja: GET ?unit=&profile= devolve um link temporário (10 min).
// Em lote: GET ?unit=&profiles=a,b,c (até 100) devolve {urls:{perfil:link}} numa consulta e uma assinatura só.
// O banco (kids_child_photo / kids_child_photos) confere a permissão; o arquivo continua privado.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const q = new URL(request.url).searchParams,
      unit = q.get('unit') || '',
      profile = q.get('profile') || '';
    if (q.has('profiles')) return await batch(request, a.access!.membership.organization_id, unit, q.get('profiles') || '');
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

async function batch(request: Request, org: string, unit: string, list: string) {
  const ids = [...new Set(list.split(',').filter(Boolean))];
  if (!uuidPattern.test(unit) || !ids.length || ids.length > 100 || ids.some((id) => !uuidPattern.test(id))) return json({urls: {}}, 400);
  const r = await db(request).rpc('kids_child_photos', {p_org: org, p_unit: unit, p_profiles: ids});
  const paths = Object.entries((r.error ? {} : r.data || {}) as Record<string, string>).filter(([, p]) => String(p).startsWith('member-photos/'));
  if (!paths.length) return json({urls: {}});
  const s = await supabaseAdminClient()
    .storage.from('member-photos')
    .createSignedUrls(
      paths.map(([, p]) => p.replace(/^member-photos\//, '')),
      600,
    );
  const urls: Record<string, string> = {};
  (s.data || []).forEach((d, i) => {
    if (d.signedUrl) urls[paths[i]![0]] = d.signedUrl;
  });
  return json({urls});
}
