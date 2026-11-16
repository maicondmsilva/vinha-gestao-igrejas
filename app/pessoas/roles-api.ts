// Chamadas de Cargos e funções (leve: usada pela lista de Pessoas sem carregar o editor).
import type {RolesCatalog} from '../../shared/church-roles';

const tenantQuery = () => {
  const t = typeof window === 'undefined' ? '' : new URLSearchParams(location.search).get('tenant');
  return t ? '&tenant=' + encodeURIComponent(t) : '';
};
export async function rolesCall<T>(action: string | null, data?: Record<string, unknown>, query = ''): Promise<T> {
  const url = '/api/church-roles?' + query + tenantQuery();
  const r = await fetch(url, action ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action, data: data || {}})} : {cache: 'no-store'});
  const d = (await r.json().catch(() => ({}))) as T & {error?: string};
  if (!r.ok) throw Error(d.error || 'Não foi possível concluir.');
  return d;
}

let catalogCache: Promise<RolesCatalog> | null = null;
export const loadCatalog = (fresh = false) => {
  if (fresh || !catalogCache) catalogCache = rolesCall<RolesCatalog>(null).catch((e) => ((catalogCache = null), Promise.reject(e)));
  return catalogCache;
};
