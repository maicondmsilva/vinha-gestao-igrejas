import {supabase} from './supabase';

export const apiBase = 'https://app.vinhaigrejas.com.br';

/** Calls the Vinha panel API with the staff member's own session and the chosen ministry. */
export async function api<T>(path: string, org: string, init: {method?: 'GET' | 'POST'; body?: unknown} = {}): Promise<T> {
  if (!supabase) throw Error('Aplicativo sem configuração do servidor.');
  const s = await supabase.auth.getSession();
  const token = s.data.session?.access_token;
  if (!token) throw Error('Entre novamente.');
  let r: Response;
  try {
    r = await fetch(apiBase + path, {
      method: init.method || 'GET',
      headers: {
        Authorization: 'Bearer ' + token,
        'x-vinha-tenant': org,
        ...(init.body !== undefined ? {'Content-Type': 'application/json'} : {}),
      },
      ...(init.body !== undefined ? {body: JSON.stringify(init.body)} : {}),
    });
  } catch {
    throw Error('Sem conexão. Confira a internet e tente de novo.');
  }
  const d = (await r.json().catch(() => ({}))) as T & {error?: string};
  if (!r.ok) throw Error(d.error || 'Não foi possível concluir agora.');
  return d;
}

export type Unit = {id: string; name: string};
export type Ministry = {organization_id: string; organization_name: string; role: string; status: string; units: Unit[]; default_unit_id: string | null; primary_color?: string};

/** The ministries this person works in, straight from their access context. */
export async function ministries(): Promise<Ministry[]> {
  if (!supabase) return [];
  const r = await supabase.rpc('access_context');
  if (r.error) throw Error('Não foi possível carregar seus ministérios.');
  const list = ((r.data as {memberships?: Ministry[]} | null)?.memberships || []).filter((m) => m.status === 'active');
  return list.filter((m) => m.role !== 'member' && m.role !== 'viewer');
}

const uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
/** Ticket QR codes carry the ticket code (alone or inside a link). */
export function ticketCode(scanned: string) {
  return uuid.exec(scanned || '')?.[0].toLowerCase() || null;
}
