import {db} from '../../../lib/supabase/operations';
import {icsCalendar} from '../../../../shared/ics.ts';

// Church agenda subscription (webcal/https): GET ?t=<secret>. Published events only, last 30 days and next 12 months.
export async function GET(request: Request) {
  const url = new URL(request.url),
    token = url.searchParams.get('t') || '';
  if (!/^[0-9a-f]{40}$/.test(token)) return new Response('Agenda não encontrada.', {status: 404, headers: {'Cache-Control': 'no-store'}});
  try {
    const r = await db(request).rpc('agenda_feed', {p_token: token});
    if (r.error) return new Response('Agenda indisponível no momento.', {status: 503, headers: {'Cache-Control': 'no-store', 'Retry-After': '300'}});
    const feed = r.data as {church: string; unit: string; timezone: string; events: Parameters<typeof icsCalendar>[0]['events']} | null;
    if (!feed) return new Response('Agenda não encontrada ou desativada.', {status: 404, headers: {'Cache-Control': 'no-store'}});
    const body = icsCalendar({
      name: feed.unit && feed.unit !== feed.church ? `${feed.church} · ${feed.unit}` : feed.church,
      timezone: feed.timezone,
      host: url.hostname,
      events: feed.events.map((e) => ({...e, url: `${url.origin}/eventos/${e.id}`})),
    });
    return new Response(body, {
      headers: {
        'Content-Type': 'text/calendar; charset=utf-8',
        'Content-Disposition': 'inline; filename="agenda.ics"',
        'Cache-Control': 'public, max-age=900',
        'X-Robots-Tag': 'noindex',
      },
    });
  } catch {
    return new Response('Agenda indisponível no momento.', {status: 503, headers: {'Cache-Control': 'no-store'}});
  }
}
