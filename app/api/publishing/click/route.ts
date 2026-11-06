import {createClient} from '@supabase/supabase-js';
import {boundedBody, uuidPattern} from '../../../lib/private-files';

/** The member app reports a banner or notice tap (metric only). */
export async function POST(request: Request) {
  const token = request.headers.get('authorization') || '';
  if (!/^Bearer [A-Za-z0-9_.-]+$/.test(token)) return Response.json({error: 'Sessão inválida.'}, {status: 401});
  let item = '';
  try {
    item = String(JSON.parse(new TextDecoder().decode(await boundedBody(request, 256)))?.item || '');
  } catch {}
  if (!uuidPattern.test(item)) return Response.json({error: 'Conteúdo inválido.'}, {status: 400});
  const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    global: {headers: {Authorization: token}},
    auth: {persistSession: false, autoRefreshToken: false},
  });
  const r = await client.rpc('publishing_click', {p_item: item});
  return Response.json({ok: !r.error}, {status: r.error ? 503 : 200, headers: {'Cache-Control': 'no-store'}});
}
