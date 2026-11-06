import {createClient} from '@supabase/supabase-js';
import {db} from '../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {boundedBody} from '../../../lib/private-files';
import {trustedSessionRequest} from '../../../lib/access-security';

const json = (data: unknown, status = 200) =>
  Response.json(data, {status, headers: {'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer'}});

const refusals: Record<string, string> = {
  privileged_role:
    'Sua conta é responsável (dono, pastor, administração ou financeiro) por um ministério. Transfira essa função a outra pessoa no painel antes de excluir a conta.',
  platform_operator: 'Contas da equipe Vinha são encerradas pela administração da plataforma.',
};

/**
 * Closes the caller's own account (App Store 5.1.1(v) / Google Play account deletion).
 * Identity comes only from the caller's session; the body carries just the typed confirmation.
 */
export async function POST(request: Request) {
  try {
    const token = request.headers.get('authorization');
    if (!token && !trustedSessionRequest(request)) return json({error: 'Origem não autorizada.'}, 403);
    if (token && !/^Bearer [A-Za-z0-9_.-]+$/.test(token)) return json({error: 'Sessão inválida.'}, 401);
    const client = token
      ? createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
          global: {headers: {Authorization: token}},
          auth: {persistSession: false, autoRefreshToken: false},
        })
      : db(request);
    const identity = await client.auth.getUser();
    const user = identity.data.user;
    if (identity.error || !user) return json({error: 'Entre novamente na sua conta para confirmar.'}, 401);
    let body: unknown;
    try {
      body = JSON.parse(new TextDecoder().decode(await boundedBody(request, 1024)));
    } catch {
      return json({error: 'Confirmação inválida.'}, 400);
    }
    const b = body as {confirm?: unknown; via?: unknown} | null;
    if (!b || typeof b !== 'object' || Object.keys(b).some((k) => !['confirm', 'via'].includes(k)) || b.confirm !== 'EXCLUIR' || !['app', 'web'].includes(String(b.via)))
      return json({error: 'Digite EXCLUIR para confirmar.'}, 400);
    const server = supabaseAdminClient();
    const closed = await server.rpc('account_close', {p_user: user.id, p_via: b.via});
    if (closed.error) return json({error: 'Não foi possível excluir agora. Tente novamente em instantes.'}, 503);
    if (closed.data?.ok !== true) return json({error: refusals[closed.data?.reason] || 'Exclusão indisponível para esta conta.'}, 409);
    // Soft delete: Auth anonymizes e-mail/phone and ends every session, while legal records keep their references.
    const removed = await server.auth.admin.deleteUser(user.id, true);
    if (removed.error && !/not.?found/i.test(removed.error.message))
      return json({error: 'Seu acesso foi encerrado, mas a confirmação final ficou pendente. Tente novamente para concluir.'}, 503);
    return json({ok: true});
  } catch {
    return json({error: 'Não foi possível excluir agora. Tente novamente em instantes.'}, 503);
  }
}
