// Shape check for the push panel API. The database repeats every rule; this only refuses obvious garbage early.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const actions = ['list', 'detail', 'options', 'preview', 'create', 'edit', 'cancel'] as const;
export type PushCommand = {unit: string; action: (typeof actions)[number]; id: string | null; version: number | null; data: Record<string, unknown>};

export function pushCommand(v: unknown): PushCommand | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const o = v as Record<string, unknown>;
  if (Object.keys(o).some((k) => !['unit', 'action', 'id', 'version', 'data'].includes(k))) return null;
  if (typeof o.unit !== 'string' || !uuid.test(o.unit)) return null;
  if (!actions.includes(o.action as PushCommand['action'])) return null;
  const action = o.action as PushCommand['action'];
  const id = o.id == null || o.id === '' ? null : typeof o.id === 'string' && uuid.test(o.id) ? o.id : undefined;
  if (id === undefined || (['detail', 'edit', 'cancel'].includes(action) && !id)) return null;
  const version = o.version == null ? null : Number.isInteger(o.version) && (o.version as number) > 0 ? (o.version as number) : undefined;
  if (version === undefined || (['edit', 'cancel'].includes(action) && !version)) return null;
  const data = o.data ?? {};
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  if (['preview', 'create', 'edit'].includes(action) && (!Array.isArray(d.targets) || !d.targets.length || d.targets.length > 200 || d.targets.some((t) => typeof t !== 'string' || !uuid.test(t))))
    return null;
  if (['create', 'edit'].includes(action)) {
    if (typeof d.title !== 'string' || d.title.trim().length < 2 || d.title.trim().length > 65) return null;
    if (typeof d.body !== 'string' || d.body.trim().length < 2 || d.body.trim().length > 240) return null;
    if (action === 'create' && (typeof d.request !== 'string' || !uuid.test(d.request))) return null;
  }
  return {unit: o.unit, action, id, version, data: d};
}
