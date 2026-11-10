// Push campaigns: Expo batch delivery. The database decides who receives what; this module only talks to Expo.
export type PushJob = {id: string; token: string; project: string; title: string; body: string; data: Record<string, unknown>};
export type PushResult = {id: string; state: 'submitted' | 'failed' | 'uncertain' | 'queued'; ticket?: string; error?: string};

const expoSend = 'https://exp.host/--/api/v2/push/send',
  expoReceipts = 'https://exp.host/--/api/v2/push/getReceipts';
const headers = (accessToken?: string) => ({
  'Content-Type': 'application/json',
  accept: 'application/json',
  ...(accessToken ? {Authorization: 'Bearer ' + accessToken} : {}),
});

/** Expo accepts up to 100 messages per request, all from the same Expo project. */
export function pushBatches(jobs: PushJob[], size = 100) {
  const byProject = new Map<string, PushJob[]>();
  for (const j of jobs) byProject.set(j.project, [...(byProject.get(j.project) || []), j]);
  const out: PushJob[][] = [];
  for (const group of byProject.values()) for (let i = 0; i < group.length; i += size) out.push(group.slice(i, i + size));
  return out;
}

export async function sendPushBatch(batch: PushJob[], transport: typeof fetch = fetch, accessToken?: string): Promise<PushResult[]> {
  if (!batch.length) return [];
  if (batch.length > 100 || new Set(batch.map((j) => j.project)).size > 1) throw Error('Lote inválido.');
  try {
    const r = await transport(expoSend, {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(20000),
      headers: headers(accessToken),
      body: JSON.stringify(
        batch.map((j) => ({
          to: j.token,
          title: j.title,
          body: j.body,
          sound: 'default',
          channelId: 'igreja',
          priority: 'high',
          data: j.data,
          ttl: 86400,
        })),
      ),
    });
    // Rate limit: keep queued for the next minute. Server errors are ambiguous: never resend blindly.
    if (r.status === 429) return batch.map((j) => ({id: j.id, state: 'queued'}));
    if (!r.ok) return batch.map((j) => ({id: j.id, state: r.status >= 500 ? 'uncertain' : 'failed', error: 'http_' + r.status}));
    const text = await r.text();
    if (text.length > 262144) return batch.map((j) => ({id: j.id, state: 'uncertain'}));
    const data = JSON.parse(text)?.data;
    if (!Array.isArray(data) || data.length !== batch.length) return batch.map((j) => ({id: j.id, state: 'uncertain'}));
    return batch.map((j, i) => {
      const d = data[i];
      if (d?.status === 'ok' && typeof d.id === 'string' && d.id.length < 200) return {id: j.id, state: 'submitted', ticket: d.id};
      const error = typeof d?.details?.error === 'string' ? d.details.error.slice(0, 80) : 'rejected';
      return {id: j.id, state: 'failed', error};
    });
  } catch {
    return batch.map((j) => ({id: j.id, state: 'uncertain'}));
  }
}

export async function pushReceipts(ids: string[], transport: typeof fetch = fetch, accessToken?: string) {
  if (!ids.length) return {};
  const r = await transport(expoReceipts, {
    method: 'POST',
    redirect: 'error',
    signal: AbortSignal.timeout(20000),
    headers: headers(accessToken),
    body: JSON.stringify({ids: ids.slice(0, 1000)}),
  });
  if (!r.ok) throw Error('Recibos indisponíveis.');
  const text = await r.text();
  if (text.length > 1048576) throw Error('Recibos inválidos.');
  return (JSON.parse(text)?.data || {}) as Record<string, {status: string; details?: {error?: string}}>;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- RPC payloads are validated by the database contract
type Rpc = (action: string, data?: Record<string, unknown>) => Promise<any>;

/** One worker tick: materialize due runs, check receipts, then send queued messages until the time budget ends. */
export async function processPushQueue(rpc: Rpc, options: {transport?: typeof fetch; accessToken?: string; budgetMs?: number; now?: () => number} = {}) {
  const now = options.now || Date.now,
    started = now(),
    budget = options.budgetMs ?? 40000,
    transport = options.transport || fetch;
  const summary = {runs: 0, submitted: 0, failed: 0, delivered: 0};
  summary.runs = Number((await rpc('materialize'))?.runs || 0);
  const previous = (await rpc('receipts'))?.items as {id: string; ticket: string}[];
  if (previous?.length) {
    const receipts = await pushReceipts(previous.map((x) => x.ticket), transport, options.accessToken).catch(() => null);
    if (receipts) {
      const settled = previous.flatMap((x) => {
        const r = receipts[x.ticket];
        if (!r) return [];
        if (r.status === 'ok') summary.delivered += 1;
        return [{id: x.id, state: r.status === 'ok' ? 'delivered' : 'failed', error: r.details?.error}];
      });
      for (let i = 0; i < settled.length; i += 500) await rpc('settle', {items: settled.slice(i, i + 500)});
    }
  }
  while (now() - started < budget) {
    const jobs = ((await rpc('claim', {limit: 300}))?.items || []) as PushJob[];
    if (!jobs.length) break;
    const results: PushResult[] = [];
    for (const batch of pushBatches(jobs)) results.push(...(await sendPushBatch(batch, transport, options.accessToken)));
    for (const r of results) {
      if (r.state === 'submitted') summary.submitted += 1;
      else if (r.state === 'failed') summary.failed += 1;
    }
    await rpc('settle', {items: results});
  }
  await rpc('materialize');
  return summary;
}
