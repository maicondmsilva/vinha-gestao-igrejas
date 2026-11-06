import {createClient} from '@supabase/supabase-js';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

/** The member app reports a tapped notification (metric only). */
export async function POST(request: Request) {
  const token = request.headers.get('authorization') || '';
  if (!/^Bearer [A-Za-z0-9_.-]+$/.test(token)) return Response.json({error: 'Sessão inválida.'}, {status: 401});
  let message = '';
  try {
    message = String(JSON.parse(new TextDecoder().decode(await boundedBody(request, 256)))?.message || '');
  } catch {}
  if (!uuidPattern.test(message)) return Response.json({error: 'Mensagem inválida.'}, {status: 400});
  const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    global: {headers: {Authorization: token}},
    auth: {persistSession: false, autoRefreshToken: false},
  });
  const r = await client.rpc('push_opened', {p_message: message});
  return Response.json(r.error ? {ok: false} : {ok: true}, {status: r.error ? 503 : 200, headers: {'Cache-Control': 'no-store'}});
}
