import {timingSafeEqual} from 'node:crypto';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {processPushQueue} from '../../../lib/push-campaigns';
import {syncYoutubeLives} from '../../../lib/live-detection';

export const maxDuration = 60;

function authorized(request: Request) {
  const expected = process.env.PUSH_CRON_SECRET,
    actual = request.headers.get('authorization') || '';
  if (!expected || expected.length < 32) return false;
  const wanted = 'Bearer ' + expected;
  return Buffer.byteLength(actual) === Buffer.byteLength(wanted) && timingSafeEqual(Buffer.from(actual), Buffer.from(wanted));
}

/** Called every minute by Supabase (pg_cron + pg_net) with the shared secret kept in Vault. */
async function run(request: Request) {
  if (!authorized(request)) return Response.json({error: 'Acesso restrito.'}, {status: 403});
  if (process.env.PUSH_CAMPAIGNS_ENABLED === 'false') return Response.json({enabled: false});
  try {
    const client = supabaseAdminClient();
    const rpc = async (action: string, data: Record<string, unknown> = {}) => {
      const r = await client.rpc('push_engine', {p_action: action, p_data: data});
      if (r.error) throw Error('Push operation failed');
      return r.data;
    };
    // Lives first: a live that just started creates its push campaign, sent in this same tick.
    const live = await syncYoutubeLives(async (action, data = {}) => {
      const r = await client.rpc('live_engine', {p_action: action, p_data: data});
      if (r.error) throw Error('Live operation failed');
      return r.data;
    }, process.env.YOUTUBE_API_KEY).catch(() => ({enabled: true, changed: 0, failed: true}));
    const summary = await processPushQueue(rpc, {accessToken: process.env.EXPO_ACCESS_TOKEN});
    return Response.json({...summary, live}, {headers: {'Cache-Control': 'no-store'}});
  } catch {
    return Response.json({error: 'Processamento não confirmado.'}, {status: 503});
  }
}
export const POST = run;
export const GET = run;
