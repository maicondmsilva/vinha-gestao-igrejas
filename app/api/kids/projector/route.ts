import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

// Telão Kids pelo Holyrics: GET ?unit= mostra se está configurado; POST {action:'save'|'test', data}.
// A chave e o token vão para o cofre do banco e nunca voltam nesta resposta.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const reasons: Record<string, [string, number]> = {
  kids_access_denied: ['Somente a coordenação do Kids ou a administração configura o telão.', 403],
  kids_projector_missing: ['Informe a chave da API e o token do Holyrics antes de ligar ou testar.', 400],
  invalid_kids_projector: ['Revise a chave e o token.', 400],
};

export async function GET(request: Request) {
  return run(request, null);
}
export async function POST(request: Request) {
  let body: unknown = null;
  try {
    body = JSON.parse(new TextDecoder().decode(await boundedBody(request, 2000)));
  } catch {
    return json({error: 'Formato inválido.', code: 'validation'}, 400);
  }
  return run(request, body);
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const unit = new URL(request.url).searchParams.get('unit') || '';
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.', code: 'validation'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    let action = 'get',
      data: Record<string, unknown> = {};
    if (body !== null) {
      const b = body as {action?: unknown; data?: Record<string, unknown>};
      if (b.action === 'test') action = 'test';
      else if (b.action === 'save' && b.data && typeof b.data === 'object' && typeof b.data.enabled === 'boolean') {
        action = 'save';
        data = {
          enabled: b.data.enabled,
          apiKey: typeof b.data.apiKey === 'string' ? b.data.apiKey.slice(0, 200) : '',
          token: typeof b.data.token === 'string' ? b.data.token.slice(0, 200) : '',
        };
      } else return json({error: 'Revise a configuração do telão.', code: 'validation'}, 400);
    }
    const r = await db(request).rpc('kids_projector', {p_org: a.access!.membership.organization_id, p_unit: unit, p_action: action, p_data: data});
    if (r.error) {
      const hit = Object.entries(reasons).find(([k]) => r.error!.message?.includes(k));
      if (hit) return json({error: hit[1][0], code: hit[0]}, hit[1][1]);
      return json({error: 'Não foi possível concluir agora.'}, 503);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Atualize antes de repetir.'}, 503);
  }
}
