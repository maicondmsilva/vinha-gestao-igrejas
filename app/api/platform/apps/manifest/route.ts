import {timingSafeEqual} from 'node:crypto';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';

// Lista dos apps para o robô de geração e atualização (GitHub Actions). Só com a chave VINHA_APPS_MANIFEST_TOKEN
// (mínimo de 32 caracteres), guardada como segredo no servidor e no GitHub. Não traz dados pessoais nem chaves secretas.
function authorized(request: Request) {
  const expected = process.env.VINHA_APPS_MANIFEST_TOKEN || '',
    actual = request.headers.get('authorization') || '';
  if (expected.length < 32) return false;
  const wanted = 'Bearer ' + expected;
  return Buffer.byteLength(actual) === Buffer.byteLength(wanted) && timingSafeEqual(Buffer.from(actual), Buffer.from(wanted));
}
export async function GET(request: Request) {
  if (!authorized(request)) return Response.json({error: 'Acesso restrito.'}, {status: 403});
  try {
    const r = await supabaseAdminClient().rpc('platform_apps', {p_action: 'manifest', p_org: null, p_data: {}});
    if (r.error) return Response.json({error: 'Lista indisponível.'}, {status: 503});
    // Endereço e chave PÚBLICOS do banco (os mesmos que já vão dentro do app), para o robô gerar o app sem segredos extras.
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL || '',
      key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || '';
    const supabase = /^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url) && /^sb_publishable_[A-Za-z0-9_-]+$/.test(key) ? {url, publishableKey: key} : null;
    return Response.json({...(r.data as Record<string, unknown>), supabase}, {headers: {'Cache-Control': 'no-store'}});
  } catch {
    return Response.json({error: 'Lista indisponível.'}, {status: 503});
  }
}
