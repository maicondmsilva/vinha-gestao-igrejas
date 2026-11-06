import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../lib/private-files';
import {kidsStationCommand} from '../../../shared/contract/kids.ts';

// Reception stations for Kids (Vinha Equipe station mode): GET ?unit= lists; POST registers, keeps alive or turns one off.
// The database decides who may do each action and ends the login of a station that is turned off.
const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const reasons: Record<string, [string, number]> = {
  kids_station_revoked: ['Esta estação foi desativada pela coordenação. Entre novamente para continuar.', 423],
  kids_station_limit: ['Esta igreja já tem 50 estações ativas. Desative as que não usa mais.', 400],
  invalid_kids_station: ['Revise o nome da estação.', 400],
  kids_station_denied: ['Somente a coordenação do Kids ou a supervisão da sessão gerencia estações.', 403],
};

export async function GET(request: Request) {
  return run(request, false);
}
export async function POST(request: Request) {
  return run(request, true);
}

async function run(request: Request, write: boolean) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    const unit = new URL(request.url).searchParams.get('unit') || '';
    if (!uuidPattern.test(unit)) return json({error: 'Selecione uma igreja.', code: 'validation'}, 400);
    if (!a.access!.membership.units.some((u) => u.id === unit)) return json({error: 'Igreja sem acesso.'}, 403);
    let action = 'list',
      id: string | null = null,
      data: Record<string, unknown> = {};
    if (write) {
      let body: unknown;
      try {
        body = JSON.parse(new TextDecoder().decode(await boundedBody(request, 4000)));
      } catch {
        return json({error: 'Formato inválido.', code: 'validation'}, 400);
      }
      let c;
      try {
        c = kidsStationCommand(body);
      } catch (e) {
        return json({error: (e as Error).message, fields: {name: (e as Error).message}, code: 'validation'}, 400);
      }
      action = c.action;
      if (c.action === 'register') data = c.data;
      else id = c.id;
    }
    const r = await db(request).rpc('kids_station', {p_org: a.access!.membership.organization_id, p_unit: unit, p_action: action, p_id: id, p_data: data});
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
