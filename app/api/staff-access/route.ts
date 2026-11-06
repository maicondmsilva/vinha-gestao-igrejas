import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {validationBody} from '../../../shared/contract/errors.ts';
import {staffAccessCommandSchema} from '../../../shared/contract/staff.ts';

// Fine-grained access: GET ?action=mine (what I can do in each church) or ?action=list (team and grants, administration only);
// POST {action:'grant'|'timezone', data}. Every rule is checked again in private.staff_access.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const reasons: Record<string, [string, string | null, number]> = {
  staff_access_denied: ['Somente a administração, o pastor ou o responsável gerenciam permissões.', null, 403],
  staff_access_role: ['Permissões finas são para secretaria e liderança. Ajuste o perfil em Usuários e permissões.', 'user', 400],
  staff_access_unit: ['A pessoa precisa ter acesso a esta igreja antes de receber permissões nela.', 'unit', 400],
  invalid_timezone: ['Escolha um fuso horário válido.', 'timezone', 400],
  invalid_staff_access: ['Revise as permissões escolhidas.', null, 400],
};

export async function GET(request: Request) {
  return run(request, null);
}
export async function POST(request: Request) {
  let body: unknown = null;
  try {
    body = JSON.parse(new TextDecoder().decode(await boundedBody(request, 8000)));
  } catch {}
  return run(request, body);
}

async function run(request: Request, body: unknown) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    let action: string, data: Record<string, unknown>;
    if (body === null) {
      action = new URL(request.url).searchParams.get('action') || 'mine';
      if (!['mine', 'list'].includes(action)) return json({error: 'Consulta inválida.', code: 'validation'}, 400);
      data = {};
    } else {
      const c = staffAccessCommandSchema.safeParse(body);
      if (!c.success) return json(validationBody(c.error, 'Revise as permissões escolhidas.'), 400);
      action = c.data.action;
      data = c.data.data;
    }
    const r = await db(request).rpc('staff_access', {p_org: a.access!.membership.organization_id, p_action: action, p_data: data});
    if (r.error) {
      const hit = Object.entries(reasons).find(([k]) => r.error!.message?.includes(k));
      if (hit) {
        const [error, field, status] = hit[1];
        return json({error, ...(field ? {fields: {[field]: error}} : {}), code: hit[0]}, status);
      }
      return json(
        {error: r.error.code === '42501' ? 'Seu acesso não permite esta operação.' : 'Não foi possível concluir agora.'},
        r.error.code === '42501' ? 403 : 503,
      );
    }
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Atualize antes de repetir.'}, 503);
  }
}
