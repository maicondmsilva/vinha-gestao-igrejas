import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {uuidPattern} from '../../../lib/private-files';
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
/** Termos assinados que envolvem a pessoa (como titular ou responsável). O banco confere se quem pede pode ver o cadastro. */
export async function GET(request: Request) {
  try {
    const a = await authorizeSupabaseChurch(request, 'people.read');
    if (!a || a.response) return a?.response || json({error: 'Acesso indisponível.'}, 503);
    const person = new URL(request.url).searchParams.get('person') || '';
    if (!uuidPattern.test(person)) return json({error: 'Escolha a pessoa.'}, 400);
    const r = await db(request).rpc('people_consents', {p_org: a.access!.membership.organization_id, p_person: person});
    if (r.error) return json({error: 'Sem acesso aos termos desta pessoa.'}, 403);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
