import {supabase} from './supabase';

// Where a tapped notification leads. Campaign pushes carry {screen, id?, campaign, message}.
export type PushTarget =
  | {kind: 'detail'; detail: 'inbox' | 'live'}
  | {kind: 'tab'; tab: 'agenda' | 'contribute' | 'home'; event?: string};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function pushTarget(data: unknown): PushTarget | null {
  if (!data || typeof data !== 'object') return null;
  const d = data as Record<string, unknown>;
  const id = typeof d.id === 'string' && uuid.test(d.id) ? d.id : undefined;
  switch (d.screen) {
    case 'inbox':
    case 'notice':
      return {kind: 'detail', detail: 'inbox'};
    case 'live':
    case 'media':
      return {kind: 'detail', detail: 'live'};
    case 'agenda':
      return {kind: 'tab', tab: 'agenda'};
    case 'event':
      return {kind: 'tab', tab: 'agenda', event: id};
    case 'giving':
      return {kind: 'tab', tab: 'contribute'};
    case 'services':
      return {kind: 'tab', tab: 'home'};
    default:
      return null;
  }
}

const api = 'https://app.vinhaigrejas.com.br';
async function report(path: string, body: Record<string, string>) {
  try {
    const s = await supabase?.auth.getSession();
    const token = s?.data.session?.access_token;
    if (!token) return;
    await fetch(api + path, {method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + token}, body: JSON.stringify(body)});
  } catch {
    /* Metrics never block the member. */
  }
}

/** Counts the opening of a campaign push (metric only). */
export function reportPushOpened(data: unknown) {
  const message = data && typeof data === 'object' ? (data as Record<string, unknown>).message : null;
  if (typeof message === 'string' && uuid.test(message)) void report('/api/push/opened', {message});
}

/** Counts a banner or notice tap (metric only). */
export function reportPublishingClick(item: string | null | undefined) {
  if (item && uuid.test(item)) void report('/api/publishing/click', {item});
}
