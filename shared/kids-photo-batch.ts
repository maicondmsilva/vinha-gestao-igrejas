// Fotos das crianças em lote: os cartões pedidos no mesmo instante viram uma chamada só
// (/api/kids/photo?profiles=...), e o link fica guardado por 9 minutos (o servidor assina por 10).
type Loader = (unit: string, profiles: string[]) => Promise<Record<string, string>>;
const ttl = 9 * 60_000;
export function kidsPhotoBatcher(load: Loader) {
  const cache = new Map<string, {url: string; until: number}>();
  const queue = new Map<string, {profiles: Set<string>; waiters: Map<string, ((url: string) => void)[]>}>();
  return function photo(unit: string, profile: string): Promise<string> {
    const key = unit + ':' + profile,
      hit = cache.get(key);
    if (hit && hit.until > Date.now()) return Promise.resolve(hit.url);
    return new Promise((resolve) => {
      let q = queue.get(unit);
      if (!q) {
        q = {profiles: new Set(), waiters: new Map()};
        queue.set(unit, q);
        setTimeout(() => void flush(unit), 25);
      }
      q.profiles.add(profile);
      q.waiters.set(profile, [...(q.waiters.get(profile) || []), resolve]);
    });
  };
  async function flush(unit: string) {
    const q = queue.get(unit);
    queue.delete(unit);
    if (!q) return;
    const all = [...q.profiles];
    for (let i = 0; i < all.length; i += 100) {
      const part = all.slice(i, i + 100);
      const urls = await load(unit, part).catch(() => ({}) as Record<string, string>);
      for (const p of part) {
        const url = urls[p] || '';
        cache.set(unit + ':' + p, {url, until: Date.now() + ttl});
        for (const w of q.waiters.get(p) || []) w(url);
      }
    }
  }
}
