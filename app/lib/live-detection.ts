// Ao vivo automático: reads YouTube's own live status for scheduled lives and moves them to live/ended.
const videoId = /^[A-Za-z0-9_-]{11}$/;

/** Video id from the URLs churches paste: watch?v=, youtu.be/, /live/, /embed/, /shorts/. Channel URLs return null. */
export function youtubeVideoId(source: string): string | null {
  try {
    const u = new URL(source);
    const host = u.hostname.replace(/^www\.|^m\./, '');
    if (u.protocol !== 'https:') return null;
    if (host === 'youtu.be') return videoId.test(u.pathname.slice(1)) ? u.pathname.slice(1) : null;
    if (host !== 'youtube.com' && host !== 'youtube-nocookie.com') return null;
    const v = u.searchParams.get('v');
    if (v && videoId.test(v)) return v;
    const m = /^\/(?:live|embed|shorts)\/([A-Za-z0-9_-]{11})(?:\/|$)/.exec(u.pathname);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

type Details = {actualStartTime?: string; actualEndTime?: string};
/** Up to 50 videos per call (1 quota unit). */
export async function youtubeLiveStates(ids: string[], key: string, transport: typeof fetch = fetch) {
  const unique = [...new Set(ids.filter((i) => videoId.test(i)))].slice(0, 50);
  if (!unique.length) return {} as Record<string, 'scheduled' | 'live' | 'ended'>;
  const url = new URL('https://www.googleapis.com/youtube/v3/videos');
  url.searchParams.set('part', 'liveStreamingDetails');
  url.searchParams.set('id', unique.join(','));
  url.searchParams.set('key', key);
  const r = await transport(url, {redirect: 'error', signal: AbortSignal.timeout(10000)});
  if (!r.ok) throw Error('YouTube indisponível.');
  const text = await r.text();
  if (text.length > 262144) throw Error('Resposta inválida.');
  const items = (JSON.parse(text)?.items || []) as {id: string; liveStreamingDetails?: Details}[];
  const out: Record<string, 'scheduled' | 'live' | 'ended'> = {};
  for (const it of items) {
    if (!videoId.test(it.id) || !it.liveStreamingDetails) continue;
    const d = it.liveStreamingDetails;
    out[it.id] = d.actualEndTime ? 'ended' : d.actualStartTime ? 'live' : 'scheduled';
  }
  return out;
}

type Rpc = (action: string, data?: Record<string, unknown>) => Promise<{items?: {id: string; source: string; state: string}[]; changed?: boolean}>;

export async function syncYoutubeLives(rpc: Rpc, key: string | undefined, transport: typeof fetch = fetch) {
  if (!key) return {enabled: false, changed: 0};
  const due = (await rpc('due')).items || [];
  const withVideo = due.flatMap((i) => {
    const v = youtubeVideoId(i.source);
    return v ? [{...i, video: v}] : [];
  });
  if (!withVideo.length) return {enabled: true, changed: 0};
  const states = await youtubeLiveStates(
    withVideo.map((i) => i.video),
    key,
    transport,
  );
  let changed = 0;
  for (const i of withVideo) {
    const s = states[i.video];
    if ((s === 'live' || s === 'ended') && s !== i.state && (await rpc('set', {id: i.id, state: s})).changed) changed++;
  }
  return {enabled: true, changed};
}
