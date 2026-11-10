import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {db} from '../../../lib/supabase/operations';
import {boundedBody, uuidPattern} from '../../../lib/private-files';
import {pushCommandResult} from '../../../lib/push-command';

const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {'Cache-Control': 'private, no-store'}});
const reasons: Record<string, [string, number]> = {
  '42501': ['Seu acesso não permite enviar push para esta igreja ou algum dos destinos.', 403],
  '40001': ['A campanha mudou ou já foi enviada. Atualize a lista antes de repetir.', 409],
  '22023': ['Revise título, texto, link, público e agendamento.', 400],
};

// Database refusals that belong to one input of the form (same paths as shared/contract/push.ts).
const databaseFields: Record<string, [string, string]> = {
  invalid_push_schedule: ['sendAt', 'Escolha uma data e hora futura, em até um ano, e o fim da repetição depois do primeiro envio.'],
  invalid_push_link: ['link.id', 'Escolha qual item abre ao tocar.'],
  invalid_push_audience: ['audience', 'Revise os filtros de público.'],
};

export const GET = (request: Request) => run(request, false);
export const POST = (request: Request) => run(request, true);

async function run(request: Request, write: boolean) {
  try {
    const a = await authorizeSupabaseChurch(request, 'units.read');
    if (!a || a.response) return a?.response || json({error: 'Serviço indisponível.'}, 503);
    let parsed: ReturnType<typeof pushCommandResult> | null = null;
    if (write) {
      try {
        parsed = pushCommandResult(JSON.parse(new TextDecoder().decode(await boundedBody(request, 16000))));
      } catch {}
    } else {
      const q = new URL(request.url).searchParams;
      parsed = pushCommandResult({
        unit: q.get('unit'),
        action: q.get('id') ? 'detail' : q.get('options') === '1' ? 'options' : 'list',
        id: q.get('id') || null,
        version: null,
        data: Object.fromEntries(['page', 'size', 'status'].flatMap((k) => (q.has(k) ? [[k, k === 'status' ? q.get(k) : Number(q.get(k))]] : []))),
      });
    }
    if (!parsed) return json({error: 'Revise os campos da campanha.', code: 'validation'}, 400);
    if (!parsed.ok) return json(parsed.body, 400);
    const b = parsed.value;
    if (!uuidPattern.test(b.unit)) return json({error: 'Revise os campos da campanha.', code: 'validation'}, 400);
    const r = await db(request).rpc('push_admin', {
      p_org: a.access!.membership.organization_id,
      p_unit: b.unit,
      p_action: b.action,
      p_id: b.id,
      p_version: b.version,
      p_data: b.data,
    });
    if (r.error) {
      const field = Object.entries(databaseFields).find(([k]) => r.error!.message?.includes(k));
      if (field) return json({error: field[1][1], fields: {[field[1][0]]: field[1][1]}, code: 'validation'}, 400);
      const [error, status] = reasons[r.error.code || ''] || ['Não foi possível concluir agora.', 503];
      return json({error}, status);
    }
    if (['create', 'edit', 'cancel'].includes(b.action) && r.data?.ok !== true)
      return json({error: 'Sem confirmação. Consulte a lista antes de repetir.'}, 503);
    return json(r.data);
  } catch {
    return json({error: 'Conexão interrompida. Consulte a lista antes de repetir.'}, 503);
  }
}
