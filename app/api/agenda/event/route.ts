import {db} from '../../../lib/supabase/operations';
import {uuidPattern} from '../../../lib/private-files';
import {icsCalendar, icsFileName, type IcsEvent} from '../../../../shared/ics.ts';

// "Adicionar ao calendário" for one published event: GET ?id=<event>.
export async function GET(request: Request) {
  const url = new URL(request.url),
    id = url.searchParams.get('id') || '';
  if (!uuidPattern.test(id)) return new Response('Evento indisponível.', {status: 404});
  try {
    const r = await db(request).rpc('member_event_page', {p_event: id});
    if (r.error) return new Response('Evento indisponível no momento.', {status: 503, headers: {'Cache-Control': 'no-store'}});
    const page = r.data as {event: IcsEvent; church?: {name?: string}} | null;
    if (!page?.event) return new Response('Evento não publicado ou indisponível.', {status: 404, headers: {'Cache-Control': 'no-store'}});
    const body = icsCalendar({
      name: page.church?.name || 'Vinha',
      host: url.hostname,
      events: [{...page.event, url: `${url.origin}/eventos/${page.event.id}`}],
    });
    return new Response(body, {
      headers: {
        'Content-Type': 'text/calendar; charset=utf-8',
        'Content-Disposition': `attachment; filename="${icsFileName(page.event.title)}"`,
        'Cache-Control': 'public, max-age=300',
      },
    });
  } catch {
    return new Response('Evento indisponível no momento.', {status: 503, headers: {'Cache-Control': 'no-store'}});
  }
}
