import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';
import {pushCommand} from '../../../lib/push-command';

const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const reasons: Record<string, [string, number]> = {
  '42501': ['Seu acesso não permite enviar push para esta igreja ou algum dos destinos.', 403],
  '40001': ['A campanha mudou ou já foi enviada. Atualize a lista antes de repetir.', 409],
  '22023': ['Revise título, texto, link, público e agendamento.', 400],
};

export const GET = (request: Request) => run(request, false);
export const POST = (request: Request) => run(request, true);

async function run(request: Request, write: boolean) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    let b: ReturnType<typeof pushCommand> = null;
    if (write) {
      try {
        b = pushCommand(JSON.parse(new TextDecoder().decode(await boundedBody(request, 16000))));
      } catch {}
    } else {
      const q = new URL(request.url).searchParams;
      b = pushCommand({
        unit: q.get('unit'),
        action: q.get('id') ? 'detail' : q.get('options') === '1' ? 'options' : 'list',
        id: q.get('id') || null,
        version: null,
        data: Object.fromEntries(['page', 'size', 'status'].flatMap((k) => (q.has(k) ? [[k, k === 'status' ? q.get(k) : Number(q.get(k))]] : []))),
      });
    }
    if (!b || !uuidPattern.test(b.unit)) return json({error: 'Revise os campos da campanha.'}, 400);
    const r = await db(request).rpc('push_admin', {
      p_org: a.access!.membership.organization_id,
      p_unit: b.unit,
      p_action: b.action,
      p_id: b.id,
      p_version: b.version,
      p_data: b.data,
    });
    if (r.error) {
      const [error, status] = reasons[r.error.code || ''] || ['Não foi possível concluir agora.', 503];
      return json({error}, status);
    }
    if (['create', 'edit', 'cancel'].includes(b.action) && r.data?.ok !== true) return json({error: 'Sem confirmação. Consulte a lista antes de repetir.'}, 503);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Consulte a lista antes de repetir.'}, 503);
  }
}
