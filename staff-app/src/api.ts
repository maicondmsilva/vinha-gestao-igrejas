import {Platform} from 'react-native';
import {supabase} from './supabase';
import pkg from '../package.json';
import {ApiError, readApiError} from '../../shared/contract/errors.ts';
import {clientHeader, clientHeaderValue, type CompatResponse} from '../../shared/contract/apps.ts';
import {isStaff, type Ministry, type StaffUnitAccess} from '../../shared/contract/staff.ts';

export {ticketCode, type Ministry, type Unit} from '../../shared/contract/staff.ts';
export {ApiError};

export const apiBase = 'https://app.vinhaigrejas.com.br';
export const appVersion = pkg.version;
const client = clientHeaderValue({app: 'staff', version: appVersion, platform: Platform.OS === 'android' || Platform.OS === 'ios' ? Platform.OS : 'other'});

/** Calls the Vinha panel API with the staff member's own session and the chosen ministry. */
export async function api<T>(path: string, org: string, init: {method?: 'GET' | 'POST'; body?: unknown} = {}): Promise<T> {
  if (!supabase) throw new ApiError({error: 'Aplicativo sem configuração do servidor.'}, 0);
  const s = await supabase.auth.getSession();
  const token = s.data.session?.access_token;
  if (!token) throw new ApiError({error: 'Entre novamente.'}, 401);
  let r: Response;
  try {
    r = await fetch(apiBase + path, {
      method: init.method || 'GET',
      headers: {
        Authorization: 'Bearer ' + token,
        'x-vinha-tenant': org,
        [clientHeader]: client,
        ...(init.body !== undefined ? {'Content-Type': 'application/json'} : {}),
      },
      ...(init.body !== undefined ? {body: JSON.stringify(init.body)} : {}),
    });
  } catch {
    throw new ApiError({error: 'Sem conexão. Confira a internet e tente de novo.'}, 0);
  }
  const d = (await r.json().catch(() => ({}))) as T;
  if (!r.ok) throw new ApiError(readApiError(d), r.status);
  return d;
}

/** Asks the platform whether this build may keep running (no session needed). Offline: keep working. */
export async function compat(): Promise<CompatResponse | null> {
  try {
    const r = await fetch(apiBase + '/api/app/compat?' + new URLSearchParams({app: 'staff', version: appVersion}), {headers: {[clientHeader]: client}});
    return r.ok ? ((await r.json()) as CompatResponse) : null;
  } catch {
    return null;
  }
}

/** The ministries this person works in, straight from their access context. */
export async function ministries(): Promise<Ministry[]> {
  if (!supabase) return [];
  const r = await supabase.rpc('access_context');
  if (r.error) throw Error('Não foi possível carregar seus ministérios.');
  return ((r.data as {memberships?: Ministry[]} | null)?.memberships || []).filter(isStaff);
}

/** What the signed-in person may do in each church of the ministry (agenda, entrance, publishing, push). */
export async function myAccess(org: string): Promise<StaffUnitAccess[]> {
  return (await api<{units: StaffUnitAccess[]}>('/api/staff-access?action=mine', org)).units || [];
}
