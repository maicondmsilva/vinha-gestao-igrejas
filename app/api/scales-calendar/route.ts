import {db} from '../../lib/supabase/operations';
import {icsCalendar, type IcsEvent} from '../../../shared/ics';

const headers = {'Cache-Control': 'private, no-store', 'X-Robots-Tag': 'noindex', 'Referrer-Policy': 'no-referrer'};

export async function GET(request: Request) {
  const token = new URL(request.url).searchParams.get('t') || '';
  const notFound = () => new Response('Calendário não encontrado ou desativado.', {status: 404, headers});
  if (!/^[0-9a-f]{64}$/.test(token)) return notFound();
  try {
    const result = await db(request).rpc('scale_calendar_feed', {p_token: token});
    if (result.error) throw new Error('Consulta indisponível');
    const feed = result.data as {timezone: string; events: IcsEvent[]} | null;
    if (!feed) return notFound();
    return new Response(icsCalendar({name: 'Minhas escalas · Vinha', timezone: feed.timezone, events: feed.events}), {
      headers: {...headers, 'Content-Type': 'text/calendar; charset=utf-8', 'Content-Disposition': 'inline; filename="minhas-escalas.ics"'},
    });
  } catch {
    return new Response('Calendário indisponível no momento.', {status: 503, headers});
  }
}
