// Panel addresses. Programação and Comunicação have their own paths (/painel/programacao/agenda,
// /painel/comunicacao/push); the other modules keep /painel?pagina=…&secao=…. Old links keep working and are
// rewritten to the new path when the panel opens.

/** Module slug (pagina) → path segment. */
export const dashboardPaths: Record<string, string> = {eventos: 'programacao', comunicacao: 'comunicacao'};
const byPath = Object.fromEntries(Object.entries(dashboardPaths).map(([page, path]) => [path, page]));
const sectionPattern = /^[a-z0-9-]{1,40}$/;

/** Effective query of a panel address: path segments become `pagina`/`secao`; an explicit `?pagina=` wins (other modules). */
export function dashboardQuery(pathname: string, search: string) {
  const q = new URLSearchParams(search);
  if (q.has('pagina')) return q;
  const m = /^\/painel\/([a-z]+)(?:\/([^/?#]+))?\/?$/.exec(pathname);
  const page = m && byPath[m[1]];
  if (page) {
    q.set('pagina', page);
    if (m![2] && sectionPattern.test(m![2])) q.set('secao', m![2]);
  }
  return q;
}

/** Current panel query (browser only). */
export const currentDashboardQuery = () => (typeof location === 'undefined' ? new URLSearchParams() : dashboardQuery(location.pathname, location.search));

/** Address of a module and section, keeping the other filters (tenant, unidade…). */
export function dashboardUrl(page: string, section?: string | null, search = '') {
  const q = new URLSearchParams(search);
  q.delete('pagina');
  q.delete('secao');
  q.delete('celula');
  const path = dashboardPaths[page];
  if (path) {
    const rest = q.toString();
    return `/painel/${path}${section && sectionPattern.test(section) ? '/' + section : ''}${rest ? '?' + rest : ''}`;
  }
  q.set('pagina', page);
  if (section) q.set('secao', section);
  return '/painel?' + q;
}

/** Canonical address for what is on screen (rewrites `/painel?pagina=eventos&secao=agenda` to `/painel/programacao/agenda`). */
export function canonicalDashboardUrl(pathname: string, search: string) {
  const q = dashboardQuery(pathname, search),
    page = q.get('pagina') || '';
  if (!dashboardPaths[page]) return null;
  const target = dashboardUrl(page, q.get('secao'), search);
  return target === pathname + search ? null : target;
}
