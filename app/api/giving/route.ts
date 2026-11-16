import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../lib/private-files';

// Financeiro › Contribua no app: GET ?unit= lista cartões, conta principal e categorias; POST {action:'save'|'delete'|'reorder', data}.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const actions = ['save', 'delete', 'reorder'];
const reasons: [RegExp, string, number][] = [
  [/giving_denied/, 'Somente a administração da igreja configura a contribuição no app.', 403],
  [/giving_no_primary/, 'Marque uma conta recebedora como principal (Financeiro › Contas recebedoras) antes de criar os cartões.', 400],
  [/giving_no_purpose/, 'Crie antes uma finalidade em Financeiro › Recebimentos digitais (ela define as categorias de taxa e devolução).', 400],
  [/giving_category/, 'Escolha a categoria de receita do cartão.', 400],
  [/giving_changed/, 'Alguém alterou este cartão agora. Atualize e tente de novo.', 409],
  [/giving_invalid/, 'Revise o nome, a cor, a imagem e os valores do cartão.', 400],
];

export const GET = (request: Request) => run(request, null);
export async function POST(request: Request) {
  try {
    return run(request, JSON.parse(new TextDecoder().decode(await boundedBody(request, 12000))));
  } catch {
    return json({error: 'Formato inválido.'}, 400);
  }
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const unit = new URL(request.url).searchParams.get('unit') || '';
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    let action = 'list',
      data: Record<string, unknown> = {};
    if (body) {
      const b = body as {action?: unknown; data?: unknown};
      if (typeof b.action !== 'string' || !actions.includes(b.action) || !b.data || typeof b.data !== 'object' || Array.isArray(b.data))
        return json({error: 'Pedido inválido.'}, 400);
      action = b.action;
      data = b.data as Record<string, unknown>;
    }
    const r = await db(request).rpc('giving_admin', {p_org: a.access!.membership.organization_id, p_unit: unit, p_action: action, p_data: data});
    if (r.error) {
      const hit = reasons.find(([re]) => re.test(r.error!.message));
      return json({error: hit?.[1] || 'Não foi possível concluir agora.'}, hit?.[2] || 503);
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida.'}, 503);
  }
}
