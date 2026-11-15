import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {uuidPattern} from '../../../lib/private-files';

// Foto do cadastro (enviada pelo app do membro): GET ?id=<pessoa> devolve um link temporário (10 min).
// Só quem já enxerga o cadastro pela sessão do painel recebe o link; o arquivo continua privado.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});

export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'people.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const id = new URL(request.url).searchParams.get('id') || '';
    if (!uuidPattern.test(id)) return json({error: 'Cadastro inválido.'}, 400);
    const r = await db(request)
      .from('people')
      .select('photo_path')
      .eq('id', id)
      .eq('organization_id', a.access!.membership.organization_id)
      .maybeSingle();
    const path = String((r.data as {photo_path?: string | null} | null)?.photo_path || '');
    if (r.error || !path.startsWith('member-photos/')) return json({url: ''});
    const s = await supabaseAdminClient().storage.from('member-photos').createSignedUrl(path.replace(/^member-photos\//, ''), 600);
    return json({url: s.data?.signedUrl || ''});
  } catch {
    return json({url: ''});
  }
}
